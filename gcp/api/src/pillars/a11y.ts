import { useMockAi, gcpProjectId } from '../config.js';
import {
  generateGeminiJson,
  generateGeminiMultimodalJson,
} from '../gemini.js';

export type DescribeResult = {
  pillar: 'a11y_describe';
  mode: 'mock' | 'gemini';
  summary: string;
  focus_actions: string[];
  language: string;
};

export type SimplifyResult = {
  pillar: 'a11y_simplify';
  mode: 'mock' | 'gemini';
  plain: string;
  bullets: string[];
};

export type TranscribeResult = {
  pillar: 'a11y_transcribe';
  mode: 'mock' | 'gemini';
  transcript: string;
  lang: 'en' | 'ta' | 'si';
};

/** Blind / low-vision: describe a screenshot or camera scene. */
export async function describeScene(input: {
  imageBytes?: Buffer;
  mimeType?: string;
  hint?: string;
  lang?: string;
}): Promise<DescribeResult> {
  const lang = input.lang === 'ta' || input.lang === 'si' ? input.lang : 'en';

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return {
      pillar: 'a11y_describe',
      mode: 'mock',
      language: lang,
      summary:
        input.hint?.trim() ||
        'You are on the Zivo home screen. Nearby help cards are Instant Dispatch, Street Batch, and Neighbor-Vouched. Bottom dock has Home, Post, Wallet, Account, and Helper mode.',
      focus_actions: [
        'Post a task with Speak or Show it',
        'Open Active Requests to send Start OTP',
        'Turn on Accessibility Mode in Account for larger text and read-aloud',
      ],
    };
  }

  const prompt = `You help blind and low-vision users use the Zivo neighborhood-help app.
Describe the current screen or scene in clear spoken English (2-4 short sentences).
Then list up to 4 focus actions the user can take next.
Return ONLY JSON: {"summary":"...","focus_actions":["..."]}
Context hint: ${JSON.stringify(input.hint ?? 'Zivo app UI')}`;

  let g: { summary?: string; focus_actions?: string[] };
  if (input.imageBytes?.length) {
    g = await generateGeminiMultimodalJson({
      prompt,
      imageBytes: input.imageBytes,
      mimeType: input.mimeType,
      model:
        process.env.A11Y_DESCRIBE_MODEL?.trim() ||
        process.env.GEMINI_VISION_MODEL?.trim() ||
        'gemini-2.5-flash',
    });
  } else {
    g = await generateGeminiJson(prompt);
  }

  return {
    pillar: 'a11y_describe',
    mode: 'gemini',
    language: lang,
    summary:
      (g.summary ?? '').trim() ||
      'Screen content could not be summarized clearly.',
    focus_actions: (g.focus_actions ?? [])
      .map((s) => String(s).trim())
      .filter(Boolean)
      .slice(0, 4),
  };
}

/** Cognitive accessibility: plain language + bullets. */
export async function simplifyText(input: {
  text: string;
  lang?: string;
}): Promise<SimplifyResult> {
  const text = input.text.trim();
  if (text.length < 8) {
    throw new Error('Text too short to simplify');
  }

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    const sentences = text
      .split(/[.!?]+/)
      .map((s) => s.trim())
      .filter(Boolean);
    return {
      pillar: 'a11y_simplify',
      mode: 'mock',
      plain: sentences.slice(0, 2).join('. ') || text.slice(0, 200),
      bullets: sentences.slice(0, 4).map((s) => s.slice(0, 120)),
    };
  }

  const g = await generateGeminiJson<{ plain?: string; bullets?: string[] }>(
    `Rewrite for cognitive accessibility (plain language, short sentences).
Keep Sri Lanka neighborhood-help context. No jargon. No brand fluff.
Return ONLY JSON: {"plain":"2-4 short sentences","bullets":["...","..."]}
Text: ${JSON.stringify(text.slice(0, 2000))}`,
  );

  return {
    pillar: 'a11y_simplify',
    mode: 'gemini',
    plain: (g.plain ?? text).trim().slice(0, 800),
    bullets: (g.bullets ?? [])
      .map((s) => String(s).trim())
      .filter(Boolean)
      .slice(0, 6),
  };
}

/** Deaf / HoH: audio → caption text for chat. */
export async function transcribeVoice(input: {
  audioBytes?: Buffer;
  mimeType?: string;
  lang?: 'en' | 'ta' | 'si';
}): Promise<TranscribeResult> {
  const lang = input.lang === 'ta' || input.lang === 'si' ? input.lang : 'en';

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return {
      pillar: 'a11y_transcribe',
      mode: 'mock',
      lang,
      transcript:
        lang === 'ta'
          ? 'நான் வீட்டின் முன் இருக்கிறேன்'
          : lang === 'si'
            ? 'මම දොර ළඟ ඉන්නේ'
            : 'I am at the door and ready to start',
    };
  }

  if (!input.audioBytes?.length) {
    throw new Error('audio required for live caption');
  }

  const mime =
    input.mimeType?.startsWith('audio/') ? input.mimeType : 'audio/webm';
  const langName =
    lang === 'ta' ? 'Tamil' : lang === 'si' ? 'Sinhala' : 'English';

  const g = await generateGeminiMultimodalJson<{ transcript?: string }>({
    prompt: `Transcribe this ${langName} speech for a deaf/hard-of-hearing chat caption.
Return ONLY JSON: {"transcript":"..."}
Keep it short and accurate. If unclear, best-effort.`,
    imageBytes: input.audioBytes,
    mimeType: mime,
    model:
      process.env.VOICE_SUGGEST_MODEL?.trim() ||
      process.env.GEMINI_VISION_MODEL?.trim() ||
      'gemini-2.5-flash',
  });

  return {
    pillar: 'a11y_transcribe',
    mode: 'gemini',
    lang,
    transcript: (g.transcript ?? '').trim().slice(0, 500),
  };
}
