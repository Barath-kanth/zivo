/**
 * Chat contact / off-platform guard + vernacular abuse / drugs / violence keywords.
 * Neighbourhood jobs stay on Zivo: phones, off-app apps, and hate/drug/violence slang
 * are hard-blocked (text and voice transcripts use the same path).
 *
 * Abuse lexicons (open source): hughsie/badwords, CMU-style EN list, LDNOOBW EN,
 * plus regional Tamil/Sinhala/SL Latin slang — see badwords_lexicon.ts.
 */
import { containsLexiconAbuse } from './badwords_lexicon.js';

export type ChatGuardResult =
  | { ok: true }
  | {
      ok: false;
      reason: string;
      code: 'phone' | 'email' | 'messaging_app' | 'off_platform' | 'abuse';
    };

/** Digits only length after stripping separators — 7+ is a phone-ish token; 9+ is a clear number. */
function digitRuns(text: string): number[] {
  const runs: number[] = [];
  for (const m of text.matchAll(/\d[\d\s\-().]{5,}\d/g)) {
    const digits = m[0].replace(/\D/g, '');
    if (digits.length >= 7) runs.push(digits.length);
  }
  return runs;
}

const EMAIL_RE = /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i;

/** WhatsApp / Telegram / Viber / IMO / Signal in en + common ta/si spellings. */
const APP_RE =
  /\b(whats\s*app|whatsapp|telegram|viber|imo|signal)\b|வாட்ஸ்\s?அப்|வாட்சப்|வெட்ஸ்அப்|වට්ස්\s?ඇප්|වට්ස්අප්|ටෙලිග්‍රෑම්|වයිබර්/i;

/**
 * "Call / text / message me at …" and SL phone cues, including Tamil / Sinhala.
 * Does NOT match a lone Start/End OTP (4–6 digits with no phone framing).
 */
const OFF_PLATFORM_RE =
  /(call|text|sms|message|ping|ring)\s*(me|us)?\s*(at|on)?|my\s*(phone|mobile|number|whatsapp)|phone\s*number|mobile\s*number|contact\s*(me|number)|reach\s*me\s*(at|on)|என்\s*(போன்|மொபைல்|நம்பர்)|போன்\s*நம்பர்|அழை|குடு\s*நம்பர்|මගේ\s*(නම්බර්|දුරකථන|ජංගම)|දුරකථන\s*අංක|කතා\s*කරන්න|නම්බර්\s*දෙන්න/i;

/** Sri Lanka mobile: +94 7X… or 07X… (with optional spaces/dashes). */
const SL_MOBILE_RE =
  /(?:\+?94[\s\-]?|0)7[\s\-]?\d{2}[\s\-]?\d{3}[\s\-]?\d{3}\b/;

/**
 * Abuse / drugs / violence — English + Tamil + Sinhala + common Latin transliterations
 * (voice STT often returns "Kolapanna pore" instead of Tamil script).
 */
const ABUSE_RE =
  /\b(fuck(?:ing|er|ed)?|f\s*u\s*c\s*k|shit|bitch|asshole|a\s*s\s*s\s*h\s*o\s*l\s*e|cunt|slut|whore|dickhead|motherfucker|mf+|bullshit|bastard|nigg(?:a|er)|porn|nude|nudes|sex\s*tape|blow\s*job|hand\s*job)\b|\b(kill\s*(you|him|her|them|myself)?|murder|rape|stab|shoot\s*you)\b|\b(kudu|ganja|heroin|cocaine|weed|meth|mdma|ecstasy|thool(?:\s*packet)?|tool\s*packet|charas|hashish)\b|\b(kolai|kolaipanna|kolapanna|kolaipannu|kolaiporen|kolapanna\s*pore|kolapannapore)\b|கொலை|கொல்ல|கொலைப்ப|கொலை\s*பண்ண|குடு|போதை|துள்|துள்\s*பாக்கெட்|போர்ன்|செக்ஸ்|மரணம்|கொலை\s*செய்|මරන්න|මැරෙන්න|කුඩු|ගංජා|තූල්|පෝන්|නග්න/i;

function compactLatin(text: string): string {
  return text
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9\u0b80-\u0bff\u0d80-\u0dff]+/g, '');
}

/** Extra transliteration catches after stripping spaces/punctuation. */
const ABUSE_COMPACT =
  /(fuck|motherfuck|asshole|kudu|thoolpacket|toolpacket|kolai|kolaipanna|kolapanna|kolapannapore|ganja|heroin|cocaine)/i;

export function guardChatMessage(raw: string): ChatGuardResult {
  const text = raw.trim();
  if (!text) return { ok: true };

  if (EMAIL_RE.test(text)) {
    return {
      ok: false,
      code: 'email',
      reason:
        'Email addresses are not allowed in chat. Keep coordination on Zivo so escrow and safety stay in place.',
    };
  }

  if (APP_RE.test(text)) {
    return {
      ok: false,
      code: 'messaging_app',
      reason:
        'WhatsApp / Telegram / other apps are not allowed here. Use this chat so both of you stay protected.',
    };
  }

  if (SL_MOBILE_RE.test(text)) {
    return {
      ok: false,
      code: 'phone',
      reason:
        'Phone numbers are not allowed in chat. Share updates here — Start/End codes stay in the app.',
    };
  }

  const runs = digitRuns(text);
  const longPhone = runs.some((n) => n >= 9);
  const midPhone = runs.some((n) => n >= 7) && OFF_PLATFORM_RE.test(text);
  if (longPhone || midPhone) {
    return {
      ok: false,
      code: 'phone',
      reason:
        'Phone numbers are not allowed in chat. Keep the conversation on Zivo.',
    };
  }

  if (
    /\b(call me|text me|whatsapp me|sms me|message me outside|off[\s-]?app)\b|என்னை\s*(கால்|கால்)\s*பன்னு|கால்\s*பண்ணு|குடு\s*நம்பர்|කතා\s*කරන්න\s*මට|නම්බර්\s*දෙන්න/i.test(
      text,
    )
  ) {
    return {
      ok: false,
      code: 'off_platform',
      reason:
        'Please keep coordination inside Zivo chat — do not move the job to a phone call or another app.',
    };
  }

  if (
    ABUSE_RE.test(text) ||
    ABUSE_COMPACT.test(compactLatin(text)) ||
    containsLexiconAbuse(text)
  ) {
    return {
      ok: false,
      code: 'abuse',
      reason:
        'That message has language we can’t allow (abuse, violence, or drugs). Keep coordination respectful and on-platform.',
    };
  }

  // Secret / “no questions” handoff euphemisms — same floor as task safety lexicon.
  if (
    /no questions( asked)?|don'?t ask (what('?s| is) (inside|in it)|anything|questions?)|without asking (anything|questions?)|don'?t (look|open|check) (inside|it)|keep it (secret|discreet)|discreet (delivery|package|parcel)|((parcel|package|envelope|packet).{0,60}(without asking|don'?t ask|do not ask|no questions)|(without asking|don'?t ask|do not ask|no questions).{0,60}(parcel|package|envelope|packet))|கேட்காமல்|අහන්නැතුව/i.test(
      text,
    )
  ) {
    return {
      ok: false,
      code: 'abuse',
      reason:
        'Secret / “no questions” parcel talk is not allowed in chat. Keep the job ordinary and on-platform.',
    };
  }

  return { ok: true };
}
