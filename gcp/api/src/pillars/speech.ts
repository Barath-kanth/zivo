/**
 * Cloud Speech-to-Text + Text-to-Speech for Tamil / Sinhala / English.
 *
 * Availability (verified against Google docs):
 * - STT (Chirp / Chirp 2, asia-southeast1): ta-IN ✅, si-LK ✅, en-IN ✅
 * - TTS: ta-IN ✅ (Standard/Wavenet/Chirp3), en-IN ✅
 * - TTS si-LK ❌ — not in Cloud TTS voice catalog.
 *   For Sinhala we synthesize via Gemini→English (or Tamil) then Cloud TTS,
 *   and return `spoken_lang` so the client can show the bridge.
 */
import { GoogleAuth } from 'google-auth-library';
import { useMockAi, gcpProjectId } from '../config.js';
import { translateChatMessage, type AppLang } from './translate.js';

const STT_LOCATION = process.env.SPEECH_LOCATION?.trim() || 'asia-southeast1';
const TTS_VOICE_TA =
  process.env.TTS_VOICE_TA?.trim() || 'ta-IN-Wavenet-A';
const TTS_VOICE_EN =
  process.env.TTS_VOICE_EN?.trim() || 'en-IN-Wavenet-A';

let auth: GoogleAuth | null = null;

function getAuth(): GoogleAuth {
  if (!auth) {
    auth = new GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/cloud-platform'],
    });
  }
  return auth;
}

async function accessToken(): Promise<string> {
  const client = await getAuth().getClient();
  const token = await client.getAccessToken();
  if (!token.token) throw new Error('No GCP access token for Speech APIs');
  return token.token;
}

export type TtsResult = {
  pillar: 'cloud_tts';
  mode: 'mock' | 'cloud';
  requested_lang: AppLang;
  spoken_lang: AppLang;
  /** BCP-47 voice used (or mock). */
  voice: string;
  /** base64 MP3 */
  audio_base64: string;
  mime_type: 'audio/mpeg';
  note?: string;
};

export type SttResult = {
  pillar: 'cloud_stt';
  mode: 'mock' | 'cloud';
  lang: AppLang;
  transcript: string;
  language_code: string;
};

function bcp47(lang: AppLang): string {
  if (lang === 'ta') return 'ta-IN';
  if (lang === 'si') return 'si-LK';
  return 'en-IN';
}

/** Tiny silent-ish MP3 placeholder for mock mode (valid short frame). */
const MOCK_MP3_B64 =
  '//uQxAAAAAAAAAAAAAAAAAAAAAAAWGluZwAAAA8AAAACAAACcQCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA//////////////////////////////////////////////////////////////////8AAAA5TEFNRTMuMTAwAa8AAAAAAAAAABUgJAUHQQAB9gAAAnEARaSiAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//uQxAaAAADSAAAAAAAAAAAAA0PMYmVFQVRJbGVzIFdpdGggTG92ZQ==';

export async function synthesizeSpeech(input: {
  text: string;
  lang?: AppLang;
}): Promise<TtsResult> {
  const requested: AppLang =
    input.lang === 'si' || input.lang === 'ta' || input.lang === 'en'
      ? input.lang
      : 'en';
  let speakText = input.text.trim().slice(0, 1200);
  let spoken: AppLang = requested;
  let note: string | undefined;

  // Cloud TTS has no si-LK voice — bridge via translation.
  if (requested === 'si') {
    const x = await translateChatMessage({ text: speakText, hintLang: 'si' });
    speakText = x.translations.en ?? speakText;
    spoken = 'en';
    note =
      'Cloud TTS has no si-LK voice yet; spoke English translation (Gemini bridge). STT still supports si-LK.';
  }

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return {
      pillar: 'cloud_tts',
      mode: 'mock',
      requested_lang: requested,
      spoken_lang: spoken,
      voice: spoken === 'ta' ? TTS_VOICE_TA : TTS_VOICE_EN,
      audio_base64: MOCK_MP3_B64,
      mime_type: 'audio/mpeg',
      note: note ?? 'Mock TTS (set USE_MOCK_AI=false for Cloud TTS)',
    };
  }

  const voiceName = spoken === 'ta' ? TTS_VOICE_TA : TTS_VOICE_EN;
  const languageCode = spoken === 'ta' ? 'ta-IN' : 'en-IN';
  const token = await accessToken();
  const res = await fetch(
    'https://texttospeech.googleapis.com/v1/text:synthesize',
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        input: { text: speakText },
        voice: { languageCode, name: voiceName },
        audioConfig: { audioEncoding: 'MP3', speakingRate: 0.95 },
      }),
    },
  );
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Cloud TTS ${res.status}: ${err.slice(0, 200)}`);
  }
  const data = (await res.json()) as { audioContent?: string };
  if (!data.audioContent) throw new Error('Cloud TTS returned no audio');

  return {
    pillar: 'cloud_tts',
    mode: 'cloud',
    requested_lang: requested,
    spoken_lang: spoken,
    voice: voiceName,
    audio_base64: data.audioContent,
    mime_type: 'audio/mpeg',
    note,
  };
}

/** Cloud Speech-to-Text v2 Chirp — ta-IN and si-LK supported in asia-southeast1. */
export async function recognizeSpeech(input: {
  audioBytes: Buffer;
  mimeType?: string;
  lang?: AppLang;
}): Promise<SttResult> {
  const lang: AppLang =
    input.lang === 'si' || input.lang === 'ta' || input.lang === 'en'
      ? input.lang
      : 'en';
  const languageCode = bcp47(lang);

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return {
      pillar: 'cloud_stt',
      mode: 'mock',
      lang,
      language_code: languageCode,
      transcript:
        lang === 'ta'
          ? 'நான் அடுத்த வீட்டு உதவி வேண்டும்'
          : lang === 'si'
            ? 'මට අසල්වැසියෙකුගේ උදව් අවශ්‍යයි'
            : 'I need help from a neighbour',
    };
  }

  const token = await accessToken();
  const encoding = mimeToEncoding(input.mimeType);
  const recognizer = `projects/${gcpProjectId}/locations/${STT_LOCATION}/recognizers/_`;
  const res = await fetch(
    `https://${STT_LOCATION}-speech.googleapis.com/v2/${recognizer}:recognize`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        config: {
          autoDecodingConfig: {},
          languageCodes: [languageCode],
          model: 'chirp_2',
        },
        content: input.audioBytes.toString('base64'),
      }),
    },
  );

  // Fallback: v1 sync recognize if v2 regional endpoint fails.
  if (!res.ok) {
    const v1 = await fetch(
      'https://speech.googleapis.com/v1/speech:recognize',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          config: {
            encoding,
            sampleRateHertz: encoding === 'WEBM_OPUS' ? 48000 : 16000,
            languageCode,
            enableAutomaticPunctuation: true,
            model: 'latest_short',
          },
          audio: { content: input.audioBytes.toString('base64') },
        }),
      },
    );
    if (!v1.ok) {
      const err = await v1.text();
      throw new Error(`Cloud STT ${v1.status}: ${err.slice(0, 200)}`);
    }
    const data = (await v1.json()) as {
      results?: Array<{ alternatives?: Array<{ transcript?: string }> }>;
    };
    const transcript =
      data.results?.[0]?.alternatives?.[0]?.transcript?.trim() || '';
    return {
      pillar: 'cloud_stt',
      mode: 'cloud',
      lang,
      language_code: languageCode,
      transcript,
    };
  }

  const data = (await res.json()) as {
    results?: Array<{ alternatives?: Array<{ transcript?: string }> }>;
  };
  const transcript =
    data.results?.[0]?.alternatives?.[0]?.transcript?.trim() || '';
  return {
    pillar: 'cloud_stt',
    mode: 'cloud',
    lang,
    language_code: languageCode,
    transcript,
  };
}

function mimeToEncoding(mime?: string): string {
  const m = (mime ?? '').toLowerCase();
  if (m.includes('webm')) return 'WEBM_OPUS';
  if (m.includes('ogg')) return 'OGG_OPUS';
  if (m.includes('wav') || m.includes('wave')) return 'LINEAR16';
  if (m.includes('flac')) return 'FLAC';
  if (m.includes('mp3') || m.includes('mpeg')) return 'MP3';
  return 'WEBM_OPUS';
}

export const speechAvailability = {
  stt: { 'en-IN': true, 'ta-IN': true, 'si-LK': true },
  tts: {
    'en-IN': true,
    'ta-IN': true,
    'si-LK': false,
    note: 'Sinhala TTS bridged via Gemini→English Cloud TTS',
  },
  stt_region: STT_LOCATION,
};
