import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiJson } from '../gemini.js';

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
            ? 'Adversarial/euphemistic phrasing caught by vernacular classifier (keyword filter missed it)'
            : 'Prohibited category',
        ]
      : ['No policy violation detected'],
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
        ? 'Native Singlish/euphemism analysis: “discreet / no questions / special package” patterns align with cash-mule or illicit handoff — keyword filter returned ALLOW; classifier BLOCK.'
        : `Keyword + mock classifier blocked: ${keyword.matched.join(', ')}`
      : 'Looks like ordinary neighborhood help.',
    action: block ? 'block' : 'allow',
    keyword_filter: {
      allowed: keyword.allowed,
      matched: keyword.matched,
      note: keyword.allowed
        ? 'Naive keyword filter: ALLOW (no English keyword hit)'
        : `Naive keyword filter: BLOCK (${keyword.matched.join(', ')})`,
    },
    research_note:
      'Aziz, Hanif & Koto (2026): refusal action drops ~87.9% EN → ~43.9% low-resource (incl. Sinhala) — action-layer vernacular safety is required.',
  };
}

/** Pillar A — vernacular-aware adversarial policy classifier. */
export async function checkTaskSafety(input: SafetyInput): Promise<SafetyResult> {
  const text = `${input.title}\n${input.description}`;
  const keyword = naiveKeywordFilter(text);

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return mockGeminiStructured(input, keyword);
  }

  try {
    const g = await generateGeminiJson<GeminiSafetyJson>(buildPrompt(input));
    const action = g.action === 'allow' || g.action === 'block' || g.action === 'review'
      ? g.action
      : 'review';
    const allowed = action === 'allow';
    const risk: SafetyResult['risk'] =
      action === 'block' ? 'high' : action === 'review' ? 'medium' : 'low';

    return {
      allowed,
      risk,
      reasons: [g.reasoning || 'Gemini vernacular classifier'],
      languageDetected: g.language_detected || input.languageHint || 'unknown',
      pillar: 'A',
      mode: 'gemini',
      risk_category: g.risk_category,
      confidence: g.confidence,
      reasoning: g.reasoning,
      action,
      keyword_filter: {
        allowed: keyword.allowed,
        matched: keyword.matched,
        note: keyword.allowed
          ? 'Naive keyword filter: ALLOW'
          : `Naive keyword filter: BLOCK (${keyword.matched.join(', ')})`,
      },
      research_note:
        'Aziz, Hanif & Koto (2026): EN refusal ~87.9% vs ~43.9% low-resource incl. Sinhala — models may “know” harm but fail to act; Zivo enforces the action layer natively on code-switched text.',
    };
  } catch (err) {
    const fallback = mockGeminiStructured(input, keyword);
    return {
      ...fallback,
      mode: 'mock',
      reasons: [
        ...fallback.reasons,
        `Gemini unavailable, mock classifier used: ${
          err instanceof Error ? err.message : 'error'
        }`,
      ],
    };
  }
}
