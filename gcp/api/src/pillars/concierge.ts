/**
 * Voice / text concierge agent — Gemini function-calling over Zivo tools.
 * Falls back to a deterministic tool path if the agent loop fails.
 */
import { Type as FunctionDeclarationSchemaType, type FunctionDeclaration } from '@google/genai';
import { useMockAi, gcpProjectId, MIN_DESCRIPTION_CHARS } from '../config.js';
import { generateWithTools } from '../gemini.js';
import { checkTaskSafety } from './safety.js';
import { quoteMicroPrice } from './pricing.js';
import { getResilienceStatus, triageTaskPriority } from './resilience.js';
import { translateTo, type AppLang } from './translate.js';

export type ConciergeResult = {
  pillar: 'voice_concierge';
  mode: 'mock' | 'gemini' | 'fallback';
  lang: AppLang;
  reply: string;
  reply_lang: AppLang;
  draft?: {
    title?: string;
    description?: string;
    category?: string;
    quote_lkr?: number;
  };
  safety?: { allowed: boolean; action?: string; reasoning?: string };
  resilience?: { hazard: string; priority?: string };
  tool_trace?: Array<{ name: string; args: unknown; result: unknown }>;
};

function tools(): FunctionDeclaration[] {
  return [
    {
      name: 'safety_check',
      description: 'Check if a neighbourhood help request is safe / allowed.',
      parameters: {
        type: FunctionDeclarationSchemaType.OBJECT,
        properties: {
          title: { type: FunctionDeclarationSchemaType.STRING },
          description: { type: FunctionDeclarationSchemaType.STRING },
        },
        required: ['title', 'description'],
      },
    },
    {
      name: 'price_quote',
      description: 'Get a fair LKR labour quote for a micro-task.',
      parameters: {
        type: FunctionDeclarationSchemaType.OBJECT,
        properties: {
          title: { type: FunctionDeclarationSchemaType.STRING },
          description: { type: FunctionDeclarationSchemaType.STRING },
          category: { type: FunctionDeclarationSchemaType.STRING },
          duration_minutes: { type: FunctionDeclarationSchemaType.NUMBER },
        },
        required: ['title', 'description'],
      },
    },
    {
      name: 'resilience_status',
      description: 'Check local flood / rain hazard for lat/lon.',
      parameters: {
        type: FunctionDeclarationSchemaType.OBJECT,
        properties: {
          lat: { type: FunctionDeclarationSchemaType.NUMBER },
          lon: { type: FunctionDeclarationSchemaType.NUMBER },
        },
        required: ['lat', 'lon'],
      },
    },
    {
      name: 'triage_priority',
      description: 'Triage task priority under current hazard.',
      parameters: {
        type: FunctionDeclarationSchemaType.OBJECT,
        properties: {
          title: { type: FunctionDeclarationSchemaType.STRING },
          description: { type: FunctionDeclarationSchemaType.STRING },
          category: { type: FunctionDeclarationSchemaType.STRING },
          hazard: { type: FunctionDeclarationSchemaType.STRING },
        },
        required: ['title', 'description', 'hazard'],
      },
    },
  ];
}

/** Model sometimes leaks tool_code / JSON instead of a spoken reply. */
function looksLikeLeak(text: string): boolean {
  const t = text.trim();
  if (!t) return true;
  return (
    /tool_code|default_api|print\(|```|functionCall|"reply"\s*:|^\s*[{[]/i.test(
      t,
    ) || /\b(safety_check|price_quote|resilience_status|triage_priority)\s*\(/i.test(t)
  );
}

function padDescription(text: string): string {
  const t = text.trim();
  if (t.length >= MIN_DESCRIPTION_CHARS) return t;
  return `${t} Neighbour help request via voice concierge.`.slice(
    0,
    Math.max(MIN_DESCRIPTION_CHARS, t.length + 40),
  );
}

function guessCategory(utterance: string): string {
  const u = utterance.toLowerCase();
  if (/mov(e|ing)|shift|box|furniture|அம்மா.*வீடு|ගෙදර/.test(u)) {
    return 'movingHelp';
  }
  if (/hospital|doctor|மருத்துவ|රෝහල/.test(u)) {
    return 'hospitalCompanion';
  }
  if (/elder|ammi|appachchi|grandma|grandpa|அம்மா|அப்பா|අම්මා/.test(u)) {
    return 'elderCare';
  }
  if (
    /grocery|market|shop|food|medicine|pharmacy|மளிகை|සාප්පු|ஆகாரம்|ආහාර|மருந்து|බෙහෙත්/.test(
      u,
    )
  ) {
    return 'groceryRun';
  }
  if (/queue|line|வரிசை|පෝලිම/.test(u)) return 'queueStanding';
  return 'errandRun';
}

/** Map model/tool categories onto Flutter TaskCategory names. */
function normalizeCategory(raw: string | undefined, utterance: string): string {
  const c = (raw ?? '').replace(/[_\s-]/g, '').toLowerCase();
  const map: Record<string, string> = {
    fooddelivery: 'groceryRun',
    food: 'groceryRun',
    grocery: 'groceryRun',
    groceryrun: 'groceryRun',
    medicine: 'hospitalCompanion',
    pharmacy: 'hospitalCompanion',
    hospitalcompanion: 'hospitalCompanion',
    eldercare: 'elderCare',
    elder: 'elderCare',
    errand: 'errandRun',
    errandrun: 'errandRun',
    movinghelp: 'movingHelp',
    queuestanding: 'queueStanding',
    sharetrip: 'errandRun',
  };
  if (map[c]) return map[c];
  if (
    [
      'groceryRun',
      'elderCare',
      'hospitalCompanion',
      'errandRun',
      'movingHelp',
      'queueStanding',
    ].includes(raw ?? '')
  ) {
    return raw as string;
  }
  return guessCategory(utterance);
}

async function replyInLang(textEn: string, lang: AppLang): Promise<string> {
  if (lang === 'en') return textEn;
  try {
    return await translateTo(textEn, lang);
  } catch (err) {
    // Never show text in the wrong language: fall back to the English original.
    console.warn('[concierge] reply translation failed', err instanceof Error ? err.message : err);
    return textEn;
  }
}

/** Deterministic path — always works even if the agent loop breaks. */
async function runDirectTools(input: {
  utterance: string;
  lang: AppLang;
  lat: number;
  lon: number;
  mode: ConciergeResult['mode'];
}): Promise<ConciergeResult> {
  const { utterance, lang, lat, lon, mode } = input;
  const title = utterance.slice(0, 80) || 'Neighbour help';
  const description = padDescription(utterance);
  const category = guessCategory(utterance);

  // Independent tools run concurrently; triage needs the hazard so it follows resilience.
  const quotePromise = quoteMicroPrice({
    title,
    description,
    category,
    duration_minutes: 45,
    lat,
    lon,
  })
    .then((q) => q.labor_lkr as number | undefined)
    .catch((err) => {
      console.warn('[concierge] price_quote soft-fail', err);
      return undefined;
    });
  const [safety, resilience, quoteAll] = await Promise.all([
    checkTaskSafety({ title, description }),
    getResilienceStatus({ lat, lon }),
    quotePromise,
  ]);
  const triage = await triageTaskPriority({
    title,
    description,
    category,
    hazard: resilience.hazard,
  });
  const quoteLkr: number | undefined = safety.allowed ? quoteAll : undefined;

  const replyEn = !safety.allowed
    ? `I cannot post that — ${safety.reasoning || 'it doesn’t meet community safety guidelines'}.`
    : [
        `I can help with that.`,
        quoteLkr != null ? `Fair helper pay about LKR ${quoteLkr}.` : '',
        resilience.hazard !== 'calm'
          ? `Weather note: ${resilience.hazard} — priority ${triage.priority}.`
          : '',
        `Shall I prepare the request?`,
      ]
        .filter(Boolean)
        .join(' ');

  return {
    pillar: 'voice_concierge',
    mode,
    lang,
    reply_lang: lang,
    reply: await replyInLang(replyEn, lang),
    draft: safety.allowed
      ? {
          title,
          description: utterance,
          category,
          quote_lkr: quoteLkr,
        }
      : undefined,
    safety: {
      allowed: safety.allowed,
      action: safety.action,
      reasoning: safety.reasoning,
    },
    resilience: { hazard: resilience.hazard, priority: triage.priority },
  };
}

export async function runConcierge(input: {
  utterance: string;
  lang?: AppLang;
  lat?: number;
  lon?: number;
}): Promise<ConciergeResult> {
  const lang: AppLang =
    input.lang === 'si' || input.lang === 'ta' || input.lang === 'en'
      ? input.lang
      : 'en';
  const lat = input.lat ?? 6.9271;
  const lon = input.lon ?? 79.8612;
  const utterance = input.utterance.trim().slice(0, 2000);

  if (!utterance) {
    return {
      pillar: 'voice_concierge',
      mode: 'mock',
      lang,
      reply_lang: lang,
      reply: await replyInLang('Please say what help you need.', lang),
    };
  }

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return runDirectTools({ utterance, lang, lat, lon, mode: 'mock' });
  }

  // Speculative execution: the three independent tools are started NOW, in parallel with the
  // model's first turn (which only decides to call them). The handler then returns the already-
  // running promise, hiding ~3 s of model latency. Same utterance-derived inputs as the direct path.
  const specTitle = utterance.slice(0, 80) || 'Neighbour help';
  const specDesc = padDescription(utterance);
  const specCategory = guessCategory(utterance);
  const spec: Record<string, Promise<unknown>> = {
    safety_check: checkTaskSafety({ title: specTitle, description: specDesc }),
    resilience_status: getResilienceStatus({ lat, lon }),
    price_quote: quoteMicroPrice({
      title: specTitle,
      description: specDesc,
      category: specCategory,
      duration_minutes: 45,
      lat,
      lon,
    }),
  };
  for (const p of Object.values(spec)) p.catch(() => undefined); // surfaced via the handler

  const handler = async (name: string, args: Record<string, unknown>) => {
    try {
      if (name in spec) return await spec[name];
      if (name === 'safety_check') {
        return await checkTaskSafety({
          title: String(args.title ?? 'Voice request'),
          description: padDescription(
            String(args.description ?? utterance),
          ),
        });
      }
      if (name === 'price_quote') {
        return await quoteMicroPrice({
          title: String(args.title ?? 'Neighbour help'),
          description: padDescription(
            String(args.description ?? utterance),
          ),
          category: String(args.category ?? guessCategory(utterance)),
          duration_minutes: Number(args.duration_minutes ?? 45),
          lat,
          lon,
        });
      }
      if (name === 'resilience_status') {
        return await getResilienceStatus({
          lat: Number(args.lat ?? lat),
          lon: Number(args.lon ?? lon),
        });
      }
      if (name === 'triage_priority') {
        return await triageTaskPriority({
          title: String(args.title ?? 'Neighbour help'),
          description: String(args.description ?? utterance),
          category: String(args.category ?? ''),
          hazard: (String(args.hazard ?? 'calm') as
            | 'calm'
            | 'watch'
            | 'alert'
            | 'emergency'),
        });
      }
      return { error: `unknown tool ${name}` };
    } catch (err) {
      console.warn(`[concierge] tool ${name} failed`, err);
      return {
        error: err instanceof Error ? err.message : 'tool failed',
      };
    }
  };

  try {
    const agentRun = generateWithTools({
      systemPrompt: `You are Zivo Concierge — a patient voice agent for elderly and disabled users in Sri Lanka.
Speak simply. Be FAST: in your FIRST step call safety_check, resilience_status and price_quote TOGETHER (all three in the same step; they are independent).
Then, only if the hazard is not "calm", call triage_priority with that hazard. Otherwise skip it.
Do not call any tool twice. If safety_check says the request is not allowed, do not offer a price.

Then reply with ONLY JSON:
{"reply":"short confirmation in English","title":"...","description":"...","category":"...","quote_lkr":number|null,"allowed":true|false}`,
      userPrompt: `User language preference: ${lang}
Location: (${lat},${lon})
Utterance: ${JSON.stringify(utterance)}`,
      tools: tools(),
      handler,
      maxTurns: 8,
      finalPrompt:
        'Using the tool results above, reply with ONLY JSON: {"reply":"short confirmation in English","title":"...","description":"...","category":"...","quote_lkr":number|null,"allowed":true|false}',
    });
    // Hedge: the agent loop is the "smart" path (Gemini decides which tools to call). If it has not
    // answered after HEDGE ms (Vertex 429 back-off, slow tool), start the deterministic parallel
    // tool path as well and take whichever finishes first — nobody waits minutes.
    const HEDGE_MS = Number(process.env.CONCIERGE_HEDGE_MS ?? 10000);
    type Settled =
      | { kind: 'agent'; v: Awaited<typeof agentRun> }
      | { kind: 'agent_err'; err: unknown }
      | { kind: 'direct'; r: ConciergeResult }
      | { kind: 'hedge' };
    const agentSettled: Promise<Settled> = agentRun.then(
      (v) => ({ kind: 'agent', v }),
      (err) => ({ kind: 'agent_err', err }),
    );
    let timer: NodeJS.Timeout | undefined;
    let first = await Promise.race<Settled>([
      agentSettled,
      new Promise<Settled>((resolve) => {
        timer = setTimeout(() => resolve({ kind: 'hedge' }), HEDGE_MS);
      }),
    ]);
    if (timer) clearTimeout(timer);
    if (first.kind === 'hedge') {
      console.warn(`[concierge] agent loop slower than ${HEDGE_MS}ms — hedging with direct tools`);
      const direct = runDirectTools({ utterance, lang, lat, lon, mode: 'fallback' }).then(
        (r): Settled => ({ kind: 'direct', r }),
      );
      first = await Promise.race<Settled>([agentSettled, direct]);
      if (first.kind === 'agent_err') first = await direct;
    }
    if (first.kind === 'direct') return first.r;
    if (first.kind === 'agent_err') throw first.err;
    if (first.kind !== 'agent') throw new Error('unexpected concierge state');
    const { text, toolTrace } = first.v;

    const cleaned = text.replace(/^```json\s*/i, '').replace(/```$/i, '').trim();
    const brace = cleaned.match(/\{[\s\S]*\}/);
    let parsed: {
      reply?: string;
      title?: string;
      description?: string;
      category?: string;
      quote_lkr?: number | null;
      allowed?: boolean;
    } = {};
    try {
      parsed = JSON.parse(brace?.[0] ?? cleaned) as typeof parsed;
    } catch {
      // Non-JSON output (e.g. leaked tool_code) — never show it to the user.
      if (looksLikeLeak(cleaned)) {
        return runDirectTools({
          utterance,
          lang,
          lat,
          lon,
          mode: 'fallback',
        });
      }
      parsed = { reply: cleaned.slice(0, 400), allowed: true };
    }
    if (looksLikeLeak(parsed.reply ?? '')) {
      return runDirectTools({
        utterance,
        lang,
        lat,
        lon,
        mode: 'fallback',
      });
    }

    const safetyHit = toolTrace.find((t) => t.name === 'safety_check');
    const quoteHit = toolTrace.find((t) => t.name === 'price_quote');
    const resHit = toolTrace.find((t) => t.name === 'resilience_status');
    const triageHit = toolTrace.find((t) => t.name === 'triage_priority');
    const safetyResult = safetyHit?.result as
      | { allowed?: boolean; action?: string; reasoning?: string }
      | undefined;
    const quoteResult = quoteHit?.result as { labor_lkr?: number } | undefined;
    const resResult = resHit?.result as { hazard?: string } | undefined;
    const triageResult = triageHit?.result as { priority?: string } | undefined;

    const replyEn =
      (parsed.reply ?? '').trim() ||
      (quoteResult?.labor_lkr != null
        ? `I can help. Fair helper pay about LKR ${quoteResult.labor_lkr}. Shall I prepare the request?`
        : 'I prepared a draft for your neighbourhood help request.');

    // If the agent returned nothing useful and no tools ran, use direct tools.
    if (!toolTrace.length && !replyEn) {
      return runDirectTools({
        utterance,
        lang,
        lat,
        lon,
        mode: 'fallback',
      });
    }

    return {
      pillar: 'voice_concierge',
      mode: 'gemini',
      lang,
      reply_lang: lang,
      reply: await replyInLang(replyEn, lang),
      draft:
        parsed.allowed === false || safetyResult?.allowed === false
          ? undefined
          : {
              title: parsed.title ?? utterance.slice(0, 80),
              description: parsed.description ?? utterance,
              category: normalizeCategory(parsed.category, utterance),
              quote_lkr:
                parsed.quote_lkr == null
                  ? quoteResult?.labor_lkr
                  : Number(parsed.quote_lkr),
            },
      safety: safetyResult
        ? {
            allowed: Boolean(safetyResult.allowed),
            action: safetyResult.action,
            reasoning: safetyResult.reasoning,
          }
        : undefined,
      resilience: {
        hazard: resResult?.hazard ?? 'unknown',
        priority: triageResult?.priority,
      },
      tool_trace: toolTrace,
    };
  } catch (err) {
    console.error('[runConcierge] agent loop failed — direct tools', err);
    try {
      return await runDirectTools({
        utterance,
        lang,
        lat,
        lon,
        mode: 'fallback',
      });
    } catch (err2) {
      console.error('[runConcierge] fallback failed', err2);
      return {
        pillar: 'voice_concierge',
        mode: 'fallback',
        lang,
        reply_lang: lang,
        reply: await replyInLang(
          'Sorry — I could not finish that request. Please try again.',
          lang,
        ),
      };
    }
  }
}
