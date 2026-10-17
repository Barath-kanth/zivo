import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiMultimodalJson, generateGeminiRace } from '../gemini.js';
import { coerceTasks, mockPlan, type PlanTaskDraft } from './task_plan.js';

export type VoiceSuggestResult = {
  pillar: 'voice';
  mode: 'mock' | 'gemini';
  transcript: string;
  title: string;
  category: string;
  description: string;
  confidence: number;
  explanation: string;
  /** Detected or requested language code (any BCP-47-ish / short code). */
  lang: string;
};

type GeminiVoiceJson = {
  transcript?: string;
  title?: string;
  category?: string;
  description?: string;
  confidence?: number;
};

const ALLOWED = new Set([
  'queueStanding',
  'laundry',
  'groceryRun',
  'homeCleaning',
  'homeCooking',
  'movingHelp',
  'tutoring',
  'techHelp',
  'petCare',
  'tailoring',
  'driver',
  'errandRun',
  'gardening',
  'documentWork',
  'hospitalCompanion',
  'babysitting',
  'elderCare',
  'eventHelp',
  'photography',
  'homeRepair',
  'phoneCheckIn',
  'readingAloud',
  'remoteTutoring',
  'sightedAssist',
  'other',
]);

function mockVoice(lang: string): VoiceSuggestResult {
  if (lang === 'ta') {
    return {
      pillar: 'voice',
      mode: 'mock',
      lang,
      transcript: 'வீட்டை சுத்தம் செய்ய உதவி வேண்டும்',
      title: 'Home cleaning help',
      category: 'homeCleaning',
      description:
        'Need help cleaning the living room and kitchen this evening. About 1 hour. Bring basic supplies if possible.',
      confidence: 0.72,
      explanation:
        'Drafted from spoken Tamil. Speak your task helps people who prefer voice over typing — including many with disabilities.',
    };
  }
  if (lang === 'si') {
    return {
      pillar: 'voice',
      mode: 'mock',
      lang,
      transcript: 'කඩේට යන්න උදව් ඕනේ',
      title: 'Quick grocery run',
      category: 'groceryRun',
      description:
        'Need a helper to buy milk, bread and eggs from the shop downstairs. Use escrow for goods — no cash handoff.',
      confidence: 0.72,
      explanation:
        'Drafted from spoken Sinhala. Voice posting improves access when typing is hard.',
    };
  }
  return {
    pillar: 'voice',
    mode: 'mock',
    lang,
    transcript: 'I need help fixing a leaking tap in the kitchen',
    title: 'Fix leaking kitchen tap',
    category: 'homeRepair',
    description:
      'Kitchen tap is dripping. Need a helper with basic plumbing tools for about 45 minutes. Photo proof after the fix.',
    confidence: 0.75,
    explanation:
      'Drafted from spoken English. Designed so people with disabilities can post help without typing a form.',
  };
}

function coerce(
  g: GeminiVoiceJson,
  lang: string,
  mode: 'mock' | 'gemini',
): VoiceSuggestResult {
  const category =
    g.category && ALLOWED.has(g.category) ? g.category : 'errandRun';
  const title =
    (g.title ?? 'Quick help nearby').trim().slice(0, 80) || 'Quick help nearby';
  const description =
    (g.description ?? '').trim().slice(0, 800) ||
    'Need a nearby helper for a short task. Details to confirm in chat.';
  const confidence =
    typeof g.confidence === 'number'
      ? Math.min(1, Math.max(0, g.confidence))
      : 0.7;
  return {
    pillar: 'voice',
    mode,
    lang,
    transcript: (g.transcript ?? '').trim().slice(0, 500),
    title,
    category,
    description,
    confidence,
    explanation:
      'Spoken request turned into a draft task. Helps people who cannot easily type — including many with disabilities.',
  };
}

/** Speak your task — audio → same draft shape as photo suggest. */
export async function suggestFromVoice(input: {
  audioBytes?: Buffer;
  mimeType?: string;
  /** Preferred / app locale hint — model still auto-detects any spoken language. */
  lang?: string;
}): Promise<VoiceSuggestResult> {
  const langHint = (input.lang ?? 'auto').trim() || 'auto';

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    const mockLang =
      langHint === 'ta' || langHint === 'si' ? langHint : 'en';
    return mockVoice(mockLang);
  }

  if (!input.audioBytes?.length) {
    throw new Error('audio file required for live voice draft');
  }

  const mime =
    input.mimeType && input.mimeType.startsWith('audio/')
      ? input.mimeType
      : 'audio/webm';

  const prompt = `You are Zivo task drafting for Sri Lanka neighbourhood help.
Listen to the audio in ANY language (Tamil, Sinhala, English, Hindi, Arabic, Chinese, French, Spanish, or mixed).
Auto-detect the spoken language. Transcribe faithfully in the speaker's language, then draft a short task post.
Return ONLY JSON:
{"transcript":"...","detected_lang":"short code e.g. en|ta|si|hi|ar|zh|fr|es","title":"...","category":"one of queueStanding|laundry|groceryRun|homeCleaning|homeCooking|movingHelp|tutoring|techHelp|petCare|tailoring|driver|errandRun|gardening|documentWork|hospitalCompanion|babysitting|elderCare|eventHelp|photography|homeRepair|phoneCheckIn|readingAloud|remoteTutoring|sightedAssist|other","description":"2-4 sentences the client can post (prefer the speaker's language; English OK if mixed)","confidence":0.0-1.0}
App locale hint (optional): ${langHint}.
Rules: no illegal work; no asking helper for cash; keep description practical.`;

  const g = await generateGeminiMultimodalJson<
    GeminiVoiceJson & { detected_lang?: string }
  >({
    prompt,
    imageBytes: input.audioBytes,
    mimeType: mime,
    model:
      process.env.VOICE_SUGGEST_MODEL?.trim() ||
      process.env.GEMINI_VISION_MODEL?.trim() ||
      'gemini-2.5-flash',
  });
  const detected =
    (g.detected_lang ?? langHint).toString().trim().slice(0, 12) || 'auto';
  return coerce(g, detected, 'gemini');
}

export type VoicePlanResult = VoiceSuggestResult & {
  bundle_title: string;
  plan_explanation: string;
  tasks: PlanTaskDraft[];
  /** Which model answered and how long the whole call took. */
  model?: string;
  latency_ms?: number;
};

/**
 * Speak → understand → split, in ONE Gemini call (was two sequential calls: ~6-8 s healthy,
 * minutes under quota stalls). Thinking is off, and two models race so a throttled bucket cannot
 * stall the user.
 */
export async function voiceToPlan(input: {
  audioBytes?: Buffer;
  mimeType?: string;
  lang?: string;
}): Promise<VoicePlanResult> {
  const langHint = (input.lang ?? 'auto').trim() || 'auto';
  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    const draft = mockVoice(langHint === 'ta' || langHint === 'si' ? langHint : 'en');
    const plan = mockPlan(`${draft.transcript}. ${draft.description}`, draft.category);
    return { ...draft, bundle_title: plan.bundle_title, plan_explanation: plan.explanation, tasks: plan.tasks };
  }
  if (!input.audioBytes?.length) throw new Error('audio file required for live voice plan');
  const mime = input.mimeType?.startsWith('audio/') ? input.mimeType : 'audio/webm';

  const prompt = `You are Zivo's voice task agent for Sri Lanka neighbourhood help.
Listen to the audio (Tamil, Sinhala, English, or mixed; auto-detect). In ONE pass:
1) transcribe faithfully in the speaker's language, 2) draft the main task, 3) split the need into 2-4 short bookable helper tasks (one task is fine if it is truly a single job).
Return ONLY JSON:
{"transcript":"...","detected_lang":"en|ta|si|...","title":"...","category":"${[...ALLOWED].join('|')}","description":"2-3 sentences, speaker's language","confidence":0.0-1.0,
"bundle_title":"...","explanation":"1 short sentence","tasks":[{"title":"...","category":"same list","description":"2-3 sentences","estimated_hours":1,"goods_budget":0}]}
Rules: no illegal work; never ask a helper to handle cash (goods_budget is paid from escrow); goods_budget only for shopping; keep it practical and brief.
App locale hint: ${langHint}.`;

  const primary =
    process.env.VOICE_SUGGEST_MODEL?.trim() || process.env.GEMINI_VISION_MODEL?.trim() || 'gemini-2.5-flash';
  const fallback = process.env.GEMINI_MODEL?.trim() || 'gemini-2.5-flash-lite';
  const { value: g, model, ms } = await generateGeminiRace<
    GeminiVoiceJson & {
      detected_lang?: string;
      bundle_title?: string;
      explanation?: string;
      tasks?: unknown[];
    }
  >({
    prompt,
    media: input.audioBytes,
    mimeType: mime,
    models: primary === fallback ? [primary] : [primary, fallback],
    thinkingBudget: 0,
    hedgeMs: 5000,
    timeoutMs: 22000,
  });

  const detected = (g.detected_lang ?? langHint).toString().trim().slice(0, 12) || 'auto';
  const base = coerce(g, detected, 'gemini');
  let tasks = coerceTasks(Array.isArray(g.tasks) ? g.tasks : []);
  if (!tasks.length) {
    tasks = [
      {
        title: base.title,
        category: base.category,
        description: base.description.length >= 20 ? base.description : `${base.description} Details to confirm in chat.`,
        estimated_hours: 1,
        goods_budget: 0,
      },
    ];
  }
  return {
    ...base,
    bundle_title: (g.bundle_title ?? base.title).trim().slice(0, 80),
    plan_explanation: (g.explanation ?? '').trim().slice(0, 240),
    tasks,
    model,
    latency_ms: ms,
  };
}
