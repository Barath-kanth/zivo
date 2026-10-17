import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiJson, generateGeminiRace } from '../gemini.js';

export type AppLang = 'en' | 'si' | 'ta';

export type ChatTranslations = Partial<Record<AppLang, string>>;

export type TranslateResult = {
  pillar: 'xlang_chat';
  mode: 'mock' | 'gemini';
  source_lang: AppLang;
  body_original: string;
  translations: ChatTranslations;
};

const LANG_NAME: Record<AppLang, string> = {
  en: 'English',
  si: 'Sinhala',
  ta: 'Tamil',
};

function mockTranslate(text: string, source: AppLang): TranslateResult {
  // Demo-safe: keep original in source; mirror for others with a clear tag.
  const translations: ChatTranslations = { [source]: text };
  for (const lang of ['en', 'si', 'ta'] as AppLang[]) {
    if (lang === source) continue;
    translations[lang] =
      lang === 'en'
        ? `[${LANG_NAME[source]}→EN] ${text}`
        : `[${LANG_NAME[source]}→${LANG_NAME[lang]}] ${text}`;
  }
  return {
    pillar: 'xlang_chat',
    mode: 'mock',
    source_lang: source,
    body_original: text,
    translations,
  };
}

function detectHeuristic(text: string): AppLang {
  if (/[\u0B80-\u0BFF]/.test(text)) return 'ta';
  if (/[\u0D80-\u0DFF]/.test(text)) return 'si';
  return 'en';
}

const SCRIPT_RE: Partial<Record<AppLang, RegExp>> = { si: /[\u0D80-\u0DFF]/, ta: /[\u0B80-\u0BFF]/ };

/**
 * One-target translation (≈1 s, small output). Throws if the result is not in the requested
 * script, so callers can fall back to the original text instead of showing the wrong language.
 */
export async function translateTo(text: string, target: AppLang): Promise<string> {
  if (target === 'en') return text;
  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    throw new Error('translation unavailable in mock mode');
  }
  const { value: g } = await generateGeminiRace<{ text?: string }>({
    prompt: `Translate this short assistant message into ${LANG_NAME[target]} using the native ${LANG_NAME[target]} script (no romanization, no commentary). Keep numbers and LKR amounts. Use simple, polite wording for an elderly listener.
Message: ${JSON.stringify(text)}
Return ONLY JSON: {"text":"..."}`,
    models: [process.env.GEMINI_VISION_MODEL?.trim() || 'gemini-2.5-flash', process.env.GEMINI_MODEL?.trim() || 'gemini-2.5-flash-lite'],
    thinkingBudget: 0,
    hedgeMs: 3500,
    timeoutMs: 10000,
    maxOutputTokens: 400,
  });
  const out = String(g.text ?? '').trim();
  if (!out || !SCRIPT_RE[target]?.test(out)) throw new Error(`result not in ${LANG_NAME[target]} script`);
  return out;
}

/** Translate a chat message into en/si/ta so each party reads in their language. */
export async function translateChatMessage(input: {
  text: string;
  hintLang?: AppLang;
}): Promise<TranslateResult> {
  const text = input.text.trim().slice(0, 2000);
  // Script wins over UI hint: a Tamil message must stay Tamil even if the sender's app locale is English.
  const scriptLang = detectHeuristic(text);
  const heuristic: AppLang =
    scriptLang !== 'en' ? scriptLang : input.hintLang === 'si' || input.hintLang === 'ta' || input.hintLang === 'en'
      ? input.hintLang
      : 'en';

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return mockTranslate(text, heuristic);
  }

  try {
    const g = await generateGeminiJson<{
      source_lang?: string;
      en?: string;
      si?: string;
      ta?: string;
    }>(`You are Zivo cross-language chat for Sri Lanka neighbourhood care.
Detect the language of the message (en | si | ta) and translate it into ALL three:
English (en), Sinhala (si), Tamil (ta).

Rules:
- Keep meaning, tone, and urgency. Do not add commentary.
- Preserve names, OTPs (4-digit codes), LKR amounts, and place names.
- If already in a language, that field should match the original closely.
- Sinhala and Tamil MUST use native scripts (not romanization).
- Keep tense (future "I will pay" stays future), qualifiers ("only", "at the door"), and who-does-what exactly.
- Pronouns: Tamil அவர் / Sinhala එයා are gender-neutral. If the sentence names the person (mother, father, son, grandmother…)
  use the matching gender ("my mother … wait for her"). Only if no gender is stated anywhere, stay neutral. Never turn a named
  woman into "he" or "they".
- Write currency as the source does (රුපියල් / ரூபாய் / LKR); do not add or drop words like "please".

Message: ${JSON.stringify(text)}

Return ONLY JSON:
{"source_lang":"en"|"si"|"ta","en":"...","si":"...","ta":"..."}`);

    // Never let the model "correct" native-script Tamil/Sinhala into English as the source.
    let source: AppLang =
      scriptLang !== 'en'
        ? scriptLang
        : g.source_lang === 'si' || g.source_lang === 'ta' || g.source_lang === 'en'
          ? g.source_lang
          : heuristic;

    const translations: ChatTranslations = {
      en: (g.en ?? '').trim() || text,
      si: (g.si ?? '').trim() || text,
      ta: (g.ta ?? '').trim() || text,
    };
    // Original text always wins for the source language — the sender must see what they typed.
    translations[source] = text;
    if (scriptLang !== 'en') translations[scriptLang] = text;

    return {
      pillar: 'xlang_chat',
      mode: 'gemini',
      source_lang: source,
      body_original: text,
      translations,
    };
  } catch (err) {
    console.error('[translateChatMessage] failed', err);
    return mockTranslate(text, heuristic);
  }
}

export function pickDisplayBody(
  msg: {
    body: string;
    body_original?: string;
    source_lang?: AppLang;
    translations?: ChatTranslations;
  },
  viewerLang: AppLang,
): { display_body: string; translated: boolean; source_lang?: AppLang } {
  const source = msg.source_lang;
  const translatedBody = msg.translations?.[viewerLang]?.trim();
  if (translatedBody) {
    return {
      display_body: translatedBody,
      translated: Boolean(source && source !== viewerLang),
      source_lang: source,
    };
  }
  return {
    display_body: msg.body,
    translated: false,
    source_lang: source,
  };
}
