import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiMultimodalJson } from '../gemini.js';

export type VoiceSuggestResult = {
  pillar: 'voice';
  mode: 'mock' | 'gemini';
  transcript: string;
  title: string;
  category: string;
  description: string;
  confidence: number;
  explanation: string;
  lang: 'en' | 'ta' | 'si';
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
  'other',
]);

function mockVoice(lang: 'en' | 'ta' | 'si'): VoiceSuggestResult {
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
  lang: 'en' | 'ta' | 'si',
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
  lang?: 'en' | 'ta' | 'si';
}): Promise<VoiceSuggestResult> {
  const lang = input.lang === 'ta' || input.lang === 'si' ? input.lang : 'en';

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return mockVoice(lang);
  }

  if (!input.audioBytes?.length) {
    throw new Error('audio file required for live voice draft');
  }

  const mime =
    input.mimeType && input.mimeType.startsWith('audio/')
      ? input.mimeType
      : 'audio/webm';

  const langName =
    lang === 'ta' ? 'Tamil' : lang === 'si' ? 'Sinhala' : 'English';

  const prompt = `You are Zivo task drafting for Sri Lanka neighborhood help.
Listen to the audio (spoken ${langName}). Transcribe, then draft a short task post.
Return ONLY JSON:
{"transcript":"...","title":"...","category":"one of queueStanding|laundry|groceryRun|homeCleaning|homeCooking|movingHelp|tutoring|techHelp|petCare|tailoring|driver|errandRun|gardening|documentWork|hospitalCompanion|babysitting|elderCare|eventHelp|photography|homeRepair|other","description":"2-4 sentences English the client can post","confidence":0.0-1.0}
Rules: no illegal work; no asking helper for cash; keep description practical.`;

  const g = await generateGeminiMultimodalJson<GeminiVoiceJson>({
    prompt,
    imageBytes: input.audioBytes,
    mimeType: mime,
    model:
      process.env.VOICE_SUGGEST_MODEL?.trim() ||
      process.env.GEMINI_VISION_MODEL?.trim() ||
      'gemini-2.5-flash',
  });
  return coerce(g, lang, 'gemini');
}
