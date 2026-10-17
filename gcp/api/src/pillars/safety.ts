import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiMultimodalJson } from '../gemini.js';

export type SafetyInput = {
  title: string;
  description: string;
  languageHint?: 'en' | 'si' | 'mixed';
};

export type SafetyResult = {
  allowed: boolean;
  risk: 'low' | 'medium' | 'high';
  reasons: string[];
  languageDetected: string;
  pillar: 'A';
  mode: 'mock' | 'gemini';
  /** Structured classifier fields (award demo). */
  risk_category?: string;
  confidence?: number;
  reasoning?: string;
  action?: 'allow' | 'block' | 'review';
  /** True when Gemini was unreachable and only the lexicon screened the text. */
  degraded?: boolean;
  /** Demo beat: naive keyword filter vs Gemini. */
  keyword_filter?: {
    allowed: boolean;
    matched: string[];
    note: string;
  };
  research_note?: string;
};

/** Naive keyword filter — deliberately weak on euphemism / code-switch. */
const NAIVE_PATTERNS: Array<{ id: string; re: RegExp }> = [
  { id: 'weapon', re: /weapon|gun|පිස්තෝල|තුවක්කු/i },
  { id: 'drug_en', re: /\b(heroin|cocaine|meth|mdma)\b/i },
  { id: 'cash_mule_en', re: /money.?mule|cash.?mule/i },
];

export function naiveKeywordFilter(text: string): {
  allowed: boolean;
  matched: string[];
} {
  const matched = NAIVE_PATTERNS.filter((p) => p.re.test(text)).map((p) => p.id);
  return { allowed: matched.length === 0, matched };
}

/**
 * Layer 1 — deterministic multilingual lexicon (en / ta / si + Singlish).
 * Explicit terms only. It is the floor that still works when Vertex is
 * rate-limited or down; euphemisms ("don't ask what's inside…") are Gemini's job.
 */
const LEXICON: Array<{ id: string; re: RegExp }> = [
  {
    id: 'illegal_drugs',
    re: /\b(weed|ganja|cannabis|marijuana|cocaine|heroin|meth|mdma|lsd|opium|kasippu)\b|கஞ்சா|ஹெராயின்|கொகைன்|போதைப்?\s?பொருள்|ගංජා|ගංජ|හෙරොයින්|කොකේන්|මත්ද්‍රව්‍ය|කසිප්පු/i,
  },
  {
    id: 'weapons',
    re: /\b(guns?|pistols?|rifles?|firearms?|explosives?|bombs?|grenades?)\b|துப்பாக்கி|வெடிகுண்டு|குண்டு\s?வாங்க|තුවක්කු|පිස්තෝල|බෝම්බ/i,
  },
  {
    id: 'forgery',
    re: /fake\s+(id|nic|passport|licen[cs]e|document|certificate)|forged|போலி\s?(அடையாள|ஆவண|சான்றிதழ்|கடவுச்சீட்டு)|ව්‍යාජ\s?(හැඳුනුම්|ලේඛන|සහතික|විදේශ)/i,
  },
  {
    id: 'cash_mule',
    re: /money.?mule|cash.?mule|(ATM|ஏடிஎம்|ඒටීඑම්)[\s\S]{0,80}(PIN|பின்|පින්)|(PIN|பின்|පින්)[\s\S]{0,80}(ATM|ஏடிஎம்|ඒටීඑම්)/i,
  },
  {
    id: 'secret_handoff_en',
    re: /no questions( asked)?|don'?t ask what('?s| is) (inside|in it)|do not ask what('?s| is) (inside|in it)/i,
  },
];

export function lexiconCheck(text: string): { hit: boolean; matched: string[] } {
  const matched = LEXICON.filter((p) => p.re.test(text)).map((p) => p.id);
  return { hit: matched.length > 0, matched };
}

type GeminiSafetyJson = {
  risk_category: string;
  confidence: number;
  reasoning: string;
  action: 'allow' | 'block' | 'review';
  language_detected: string;
};

function buildPrompt(input: SafetyInput): string {
  return `You are Zivo Pillar A — a vernacular-aware adversarial policy classifier for a Sri Lanka hyperlocal help marketplace.

IMPORTANT:
- Reason natively over code-switched Sinhala–English (Singlish) text. Do NOT translate to English first.
- Detect euphemisms, soft-coded requests, and adversarial phrasing that evade keyword filters
  (e.g. "special discreet delivery", "no questions package", veiled cash-mule / drug / weapon asks).
- Research context: LLMs often recognize harm in low-resource languages but fail to refuse
  (Aziz, Hanif & Koto 2026 — English refusal ~87.9% vs ~43.9% in low-resource languages incl. Sinhala).
  Your job is the ACTION layer: allow | block | review.

ACTION RULES (strict):
- Use action=block (NOT review) when euphemisms imply illicit handoff / cash-mule / "no questions" packages,
  even if no explicit illegal keyword appears. Keyword filters miss these — you must not.
- This applies in EVERY language, including Tamil and Sinhala (native script and romanised): a request to carry or hand over a
  sealed package / envelope / parcel while the helper is told not to look inside, not to ask, or to keep it secret, especially with
  bonus or "double" pay, is block.
- Never be more lenient because the text is not English. Low-resource languages are where harm slips through.
- Do NOT block benign chores that merely contain alarming words (knife set, gas cylinder, medicine, a child's school pickup) —
  those are allow.
- Use action=review only for ambiguous ordinary chores with mild odd phrasing.
- Use action=allow for clear neighborhood help (groceries upstairs, queue pickup, tutoring, etc.).

Policy blocks: weapons/explosives, illegal drugs, cash-mule / unauthorized money movement,
gambling facilitation, sexual exploitation, giving physical cash to helpers for goods purchases,
forgery / fake IDs, harm to minors.

Task title: ${JSON.stringify(input.title)}
Task description: ${JSON.stringify(input.description)}
Language hint: ${input.languageHint ?? 'unknown'}

Return ONLY JSON with keys:
{
  "risk_category": string,           // e.g. "cash_mule_euphemism", "safe_chore", "illegal_drugs"
  "confidence": number,              // 0..1
  "reasoning": string,               // short, cite code-switch / euphemism if relevant
  "action": "allow" | "block" | "review",
  "language_detected": string        // "en" | "si" | "mixed" | other
}`;
}

function mockGeminiStructured(input: SafetyInput, keyword: { allowed: boolean; matched: string[] }): SafetyResult {
  const text = `${input.title}\n${input.description}`;
  const hasSinhala = /[\u0D80-\u0DFF]/.test(text);
  const euphemism =
    /discreet|no questions|special (delivery|package)|package pick.?up|කතා නැතුව|රහස්/i.test(
      text,
    );
  const block = !keyword.allowed || euphemism;
  return {
    allowed: !block,
    risk: block ? 'high' : hasSinhala ? 'medium' : 'low',
    reasons: block
      ? [
          euphemism
            ? 'This request looks unsafe for a neighborhood help marketplace'
            : 'This request isn’t allowed on Zivo',
        ]
      : ['Looks fine'],
    languageDetected: hasSinhala ? 'si/mixed' : input.languageHint ?? 'en',
    pillar: 'A',
    mode: 'mock',
    risk_category: block
      ? euphemism
        ? 'cash_mule_euphemism'
        : keyword.matched[0] ?? 'policy_block'
      : 'safe_chore',
    confidence: block ? 0.86 : 0.7,
    reasoning: block
      ? euphemism
        ? 'This request looks unsafe for a neighborhood help marketplace'
        : 'This request isn’t allowed on Zivo'
      : 'Looks like ordinary neighborhood help.',
    action: block ? 'block' : 'allow',
  };
}

/** Pillar A — vernacular-aware adversarial policy classifier. */
export async function checkTaskSafety(input: SafetyInput): Promise<SafetyResult> {
  const text = `${input.title}\n${input.description}`;
  const keyword = naiveKeywordFilter(text);

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return mockGeminiStructured(input, keyword);
  }

  const lex = lexiconCheck(text);

  try {
    // Stronger model than the default flash-lite: Tamil/Sinhala euphemisms need it.
    const g = await generateGeminiMultimodalJson<GeminiSafetyJson>({
      prompt: buildPrompt(input),
      model: process.env.SAFETY_MODEL?.trim() || 'gemini-2.5-flash',
      thinkingBudget: 0, // classification, not reasoning: keep latency ≈1 s
    });
    let action: 'allow' | 'block' | 'review' =
      g.action === 'allow' || g.action === 'block' || g.action === 'review'
        ? g.action
        : 'review';
    // Defense in depth: an explicit lexicon hit can only tighten, never loosen.
    if (lex.hit) action = 'block';
    if (lex.hit && !g.reasoning) g.reasoning = 'This request isn’t allowed on Zivo';
    // Only hard-block. "review" is soft — Instant Dispatch / ordinary chores
    // must not fail with a generic "Blocked by safety policy" false positive.
    const allowed = action !== 'block';
    const risk: SafetyResult['risk'] =
      action === 'block' ? 'high' : action === 'review' ? 'medium' : 'low';

    return {
      allowed,
      risk,
      reasons: [g.reasoning || 'Community safety check'],
      languageDetected: g.language_detected || input.languageHint || 'unknown',
      pillar: 'A',
      mode: 'gemini',
      risk_category: g.risk_category,
      confidence: g.confidence,
      reasoning: g.reasoning,
      action,
    };
  } catch (err) {
    console.error('[safety] Gemini unavailable, lexicon-only fallback', err instanceof Error ? err.message.slice(0, 160) : err);
    const fallback = mockGeminiStructured(input, {
      allowed: keyword.allowed && !lex.hit,
      matched: [...keyword.matched, ...lex.matched],
    });
    return {
      ...fallback,
      mode: 'mock',
      degraded: true,
      // No model verdict → never silently "allow" with a cheerful reason.
      action: fallback.action === 'block' ? 'block' : 'review',
      reasoning:
        fallback.action === 'block'
          ? fallback.reasoning
          : 'Automated check was unavailable; request passes basic screening.',
      reasons: fallback.reasons.map((r) =>
        r.replace(/\bgemini\b/gi, 'safety').replace(/\bvernacular classifier\b/gi, 'check'),
      ),
    };
  }
}
