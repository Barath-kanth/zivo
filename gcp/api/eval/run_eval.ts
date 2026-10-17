/**
 * Zivo evaluation slice runner.
 *
 *   cd gcp/api
 *   GCP_PROJECT_ID=gcp-ai-builder VERTEX_LOCATION=us-central1 USE_MOCK_AI=false \
 *     npx tsx eval/run_eval.ts [https://zivo-api-….run.app]
 *
 * What is measured (and against what):
 *   1. Safety block precision / recall  → LIVE Cloud Run  POST /tasks/safety-check
 *      (+ the old keyword filter as a baseline, run in-process).
 *   2. Translation checks               → the SAME translateChatMessage() code that
 *      /tasks/:id/chat uses, run in-process against live Vertex AI Gemini.
 *   3. Voice → task accuracy            → LIVE  /a11y/tts  → MP3 → LIVE
 *      /tasks/suggest-from-voice.  English + Tamil only (no Sinhala TTS voice exists,
 *      so Sinhala is reported as "not measured", not faked).
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { UTTERANCES, CHAT_MESSAGES, type Lang } from './dataset.js';
import { naiveKeywordFilter, lexiconCheck } from '../src/pillars/safety.js';
import { translateChatMessage } from '../src/pillars/translate.js';
import { generateGeminiMultimodalJson } from '../src/gemini.js';
import { renderChart } from './chart.js';

const API = (process.argv[2] ?? 'https://zivo-api-ihp5vjzpsa-el.a.run.app').replace(/\/$/, '');
const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '..', '..', '..', 'docs', 'eval');
mkdirSync(OUT, { recursive: true });

const LANGS: Lang[] = ['en', 'ta', 'si'];

async function pool<T, R>(items: T[], n: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let i = 0;
  await Promise.all(
    Array.from({ length: n }, async () => {
      while (i < items.length) {
        const k = i++;
        out[k] = await fn(items[k]);
      }
    }),
  );
  return out;
}

async function login(): Promise<string> {
  const phone = '+94770009999'; // dedicated eval account
  const r = await fetch(`${API}/auth/otp/request`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phone }),
  }).then((x) => x.json() as Promise<{ issuedCode?: string }>);
  if (!r.issuedCode) throw new Error('OTP not exposed by API; cannot log in for voice eval');
  const v = await fetch(`${API}/auth/otp/verify`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phone, token: r.issuedCode }),
  }).then((x) => x.json() as Promise<{ accessToken?: string; error?: string }>);
  if (!v.accessToken) throw new Error(`login failed: ${v.error}`);
  return v.accessToken;
}

const pct = (a: number, b: number) => (b === 0 ? null : a / b);

// ───────────────────────── 1. Safety ─────────────────────────
async function evalSafety() {
  const rows = await pool(UTTERANCES, 2, async (u) => {
    const t0 = Date.now();
    const res = await fetch(`${API}/tasks/safety-check`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ title: u.title, description: u.text }),
    });
    const j = (await res.json()) as { allowed?: boolean; action?: string; reasoning?: string; degraded?: boolean };
    // "review" counts as NOT blocked (the product lets it through to human review).
    const predBlock = j.action === 'block' || j.allowed === false;
    const lex = lexiconCheck(`${u.title} ${u.text}`);
    const naive = naiveKeywordFilter(`${u.title} ${u.text}`);
    return {
      id: u.id, lang: u.lang, label: u.label, note: u.note, heldout: !!u.heldout,
      degraded: j.degraded === true, naiveBlock: !naive.allowed,
      action: j.action ?? 'error', predBlock, keywordBlock: lex.hit,
      correct: predBlock === (u.label === 'block'),
      ms: Date.now() - t0, reasoning: (j.reasoning ?? '').slice(0, 140),
    };
  });

  const stats = (subset: typeof rows, key: 'predBlock' | 'keywordBlock' | 'naiveBlock') => {
    const tp = subset.filter((r) => r[key] && r.label === 'block').length;
    const fp = subset.filter((r) => r[key] && r.label === 'allow').length;
    const fn = subset.filter((r) => !r[key] && r.label === 'block').length;
    const tn = subset.filter((r) => !r[key] && r.label === 'allow').length;
    return { tp, fp, fn, tn, precision: pct(tp, tp + fp), recall: pct(tp, tp + fn) };
  };
  const by: Record<string, ReturnType<typeof stats>> = { all: stats(rows, 'predBlock') };
  const kwBy: Record<string, ReturnType<typeof stats>> = { all: stats(rows, 'keywordBlock') };
  for (const l of LANGS) {
    const sub = rows.filter((r) => r.lang === l);
    by[l] = stats(sub, 'predBlock');
    kwBy[l] = stats(sub, 'keywordBlock');
  }
  const heldout = {
    gemini: stats(rows.filter((r) => r.heldout), 'predBlock'),
    keyword: stats(rows.filter((r) => r.heldout), 'keywordBlock'),
    n: rows.filter((r) => r.heldout).length,
  };
  const dev = {
    gemini: stats(rows.filter((r) => !r.heldout), 'predBlock'),
    keyword: stats(rows.filter((r) => !r.heldout), 'keywordBlock'),
    n: rows.filter((r) => !r.heldout).length,
  };
  const legacyInAppFilter = stats(rows, 'naiveBlock');
  const latencies = rows.map((r) => r.ms).sort((a, b) => a - b);
  const latency = { p50_ms: latencies[Math.floor(latencies.length / 2)], max_ms: latencies[latencies.length - 1] };
  return { rows, gemini: by, keyword: kwBy, heldout, dev, legacyInAppFilter, latency, degraded_count: rows.filter((r) => r.degraded).length };
}

// ───────────────────────── 2. Translation ─────────────────────────
const SCRIPT: Record<Lang, RegExp> = {
  en: /[A-Za-z]/, ta: /[\u0B80-\u0BFF]/, si: /[\u0D80-\u0DFF]/,
};
const normDigits = (s: string) =>
  s.replace(/[\u0BE6-\u0BEF]/g, (c) => String(c.charCodeAt(0) - 0x0be6))
   .replace(/[\u0DE6-\u0DEF]/g, (c) => String(c.charCodeAt(0) - 0x0de6));

async function evalTranslate() {
  const rows = await pool(CHAT_MESSAGES, 1, async (m) => {
    const r = await translateChatMessage({ text: m.text });
    const checks: Record<string, boolean> = {};
    checks.mode_is_live_gemini = r.mode === 'gemini';
    checks.source_detected = r.source_lang === m.lang;
    checks.all_three_present = (['en', 'si', 'ta'] as Lang[]).every(
      (l) => (r.translations[l] ?? '').trim().length > 0,
    );
    checks.native_script = (['ta', 'si'] as Lang[]).every((l) => SCRIPT[l].test(r.translations[l] ?? ''));
    checks.numbers_kept = (['en', 'si', 'ta'] as Lang[]).every((l) => {
      const t = normDigits(r.translations[l] ?? '');
      return m.mustKeep.every((k) => t.includes(k));
    });

    // LLM-as-judge (different, larger model). Indicative only — it's still a Gemini family model.
    let judge: { ok: boolean; why: string } = { ok: false, why: 'judge failed' };
    try {
      const g = await generateGeminiMultimodalJson<{ en_ok?: boolean; si_ok?: boolean; ta_ok?: boolean; why?: string }>({
        model: 'gemini-2.5-flash',
        prompt: `You are a strict bilingual reviewer (English, Sinhala, Tamil).
Original (${m.lang}): ${JSON.stringify(m.text)}
Candidate translations:
en: ${JSON.stringify(r.translations.en)}
si: ${JSON.stringify(r.translations.si)}
ta: ${JSON.stringify(r.translations.ta)}
For each language answer true only if the candidate preserves the full meaning (no omissions, no additions, no flipped meaning). Natural phrasing is not required.
Return ONLY JSON: {"en_ok":bool,"si_ok":bool,"ta_ok":bool,"why":"<=20 words about any problem"}`,
      });
      judge = { ok: !!(g.en_ok && g.si_ok && g.ta_ok), why: g.why ?? '' };
    } catch (e) {
      judge = { ok: false, why: `judge error: ${e instanceof Error ? e.message.slice(0, 80) : e}` };
    }
    checks.meaning_preserved_llm_judge = judge.ok;
    const pass = Object.values(checks).every(Boolean);
    return { id: m.id, lang: m.lang, original: m.text, translations: r.translations, checks, judge_note: judge.why, pass };
  });
  const by: Record<string, { pass: number; n: number; rate: number | null }> = {};
  for (const k of ['all', ...LANGS]) {
    const sub = k === 'all' ? rows : rows.filter((r) => r.lang === k);
    by[k] = { pass: sub.filter((r) => r.pass).length, n: sub.length, rate: pct(sub.filter((r) => r.pass).length, sub.length) };
  }
  // Per-check roll-up
  const perCheck: Record<string, number> = {};
  for (const name of Object.keys(rows[0].checks)) {
    perCheck[name] = rows.filter((r) => r.checks[name]).length / rows.length;
  }
  return { rows, by, perCheck };
}

// ───────────────────────── 3. Voice → task ─────────────────────────
async function evalVoice(token: string) {
  const items = UTTERANCES.filter((u) => u.label === 'allow' && u.categories && (u.lang === 'en' || u.lang === 'ta'));
  const rows = await pool(items, 1, async (u) => {
    const auth = { authorization: `Bearer ${token}` };
    let rateLimitedFirstTry = false;
    for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const tts = await fetch(`${API}/a11y/tts`, {
        method: 'POST', headers: { ...auth, 'content-type': 'application/json' },
        body: JSON.stringify({ text: u.text, lang: u.lang }),
      }).then((x) => x.json() as Promise<{ audio_base64?: string; voice?: string; spoken_lang?: string; error?: string }>);
      if (!tts.audio_base64) throw new Error(`tts: ${tts.error}`);
      const bytes = Buffer.from(tts.audio_base64, 'base64');
      const form = new FormData();
      form.append('audio', new Blob([bytes], { type: 'audio/mpeg' }), 'clip.mp3');
      form.append('lang', 'auto'); // the app sends "auto" — no language hint
      const v = await fetch(`${API}/tasks/suggest-from-voice`, { method: 'POST', headers: auth, body: form })
        .then((x) => x.json() as Promise<{ transcript?: string; category?: string; title?: string; lang?: string; error?: string }>);
      if (v.error) throw new Error(v.error);
      const catOk = u.categories!.includes(v.category ?? '');
      const scriptOk = SCRIPT[u.lang].test(v.transcript ?? '');
      return {
        id: u.id, lang: u.lang, spoken: u.text, tts_voice: tts.voice, audio_bytes: bytes.length,
        transcript: v.transcript, detected_lang: v.lang, category: v.category, accepted: u.categories,
        title: v.title, category_ok: catOk, transcript_script_ok: scriptOk, error: undefined as string | undefined,
        rate_limited_first_try: rateLimitedFirstTry,
      };
    } catch (e) {
      if (attempt === 0 && /429|RESOURCE_EXHAUSTED/i.test(String(e))) {
        rateLimitedFirstTry = true;
        await new Promise((r) => setTimeout(r, 25000)); // cool-down, then one retry
        continue;
      }
      return {
        id: u.id, lang: u.lang, spoken: u.text, tts_voice: undefined, audio_bytes: 0, transcript: undefined,
        detected_lang: undefined, category: undefined, accepted: u.categories, title: undefined,
        category_ok: false, transcript_script_ok: false, error: e instanceof Error ? e.message : String(e),
        rate_limited_first_try: rateLimitedFirstTry,
      };
    }
    }
    throw new Error('unreachable');
  });
  const by: Record<string, { ok: number; n: number; acc: number | null; script_ok: number }> = {};
  for (const k of ['all', 'en', 'ta']) {
    const sub = k === 'all' ? rows : rows.filter((r) => r.lang === k);
    by[k] = {
      ok: sub.filter((r) => r.category_ok).length, n: sub.length,
      acc: pct(sub.filter((r) => r.category_ok).length, sub.length),
      script_ok: sub.filter((r) => r.transcript_script_ok).length,
    };
  }
  by.si = { ok: 0, n: 0, acc: null, script_ok: 0 };
  const rate_limited_first_try = rows.filter((r) => r.rate_limited_first_try).length;
  const errors = rows.filter((r) => r.error).length;
  return { rows, by, rate_limited_first_try, hard_errors: errors };
}

// ───────────────────────── main ─────────────────────────
const started = new Date().toISOString();
console.log(`API: ${API}`);
// EVAL_STAGES=translation  → rerun only that stage and merge into the existing results.json
const stages = (process.env.EVAL_STAGES ?? 'safety,translation,voice').split(',');
const prev = stages.length < 3 ? JSON.parse(readFileSync(join(OUT, 'results.json'), 'utf8')) : null;
console.log('1/3 safety…');
const safety = stages.includes('safety') ? await evalSafety() : prev.safety;
console.log('2/3 translation…');
const translation = stages.includes('translation') ? await evalTranslate() : prev.translation;
console.log('3/3 voice → task…');
const voice = stages.includes('voice') ? await evalVoice(await login()) : prev.voice;

const result = {
  generated_at: started,
  api: API,
  methodology: {
    n_utterances: UTTERANCES.length,
    per_language: 10,
    authors: 'written by the Zivo team; labels are team policy judgement',
    caveats: [
      'Single run, temperature low but non-zero: results can shift by ±1 item between runs.',
      'Voice clips are synthetic (Google Cloud TTS → Gemini): an upper bound, not real elderly/noisy speech.',
      'Sinhala voice-to-task not measured: no Sinhala TTS voice available to build fixtures.',
      'Translation "meaning preserved" is LLM-judged by a larger Gemini model, not a human; native-speaker review still needed.',
      'Translation ran in-process with the same function the chat route uses (the live route needs an assigned task + two accounts).',
      '30 safety items / 9 chat messages / ~12 voice clips is a smoke test, not a benchmark; intervals are wide.',
      'Safety: the first run (results_before_fix.json) exposed misses; the lexicon + stronger model were added afterwards. 24 items are therefore DEV (tuned-on); 6 items (heldout:true) were written after the fix and are the fairer number.',
      'Keyword baseline = the lexicon layer alone (written by us, includes the explicit terms in the dev set). The old in-app 3-pattern filter is reported separately as legacyInAppFilter.',
    ],
  },
  safety, translation, voice,
};

writeFileSync(join(OUT, 'results.json'), JSON.stringify(result, null, 2));
const svg = renderChart({
  safety: { gemini: safety.gemini, keyword: safety.keyword },
  translation: translation.by,
  voice: voice.by,
});
writeFileSync(join(OUT, 'eval_chart.svg'), svg);

const f = (x: number | null | undefined) => (x == null ? 'n/a' : `${Math.round(x * 100)}%`);
console.log('\n── Safety (live) ──');
for (const k of ['all', ...LANGS]) {
  const g = safety.gemini[k], b = safety.keyword[k];
  console.log(`${k.padEnd(4)} Gemini P=${f(g.precision)} R=${f(g.recall)} (tp${g.tp} fp${g.fp} fn${g.fn} tn${g.tn}) | keyword P=${f(b.precision)} R=${f(b.recall)}`);
}
console.log('heldout  Gemini', safety.heldout.gemini, ' keyword', safety.heldout.keyword);
console.log('dev       Gemini', safety.dev.gemini, ' keyword', safety.dev.keyword);
console.log('legacy in-app filter', safety.legacyInAppFilter, 'latency', safety.latency, 'degraded', safety.degraded_count);
console.log('misses:', safety.rows.filter((r) => !r.correct).map((r) => `${r.id}[${r.label}→${r.action}]`).join(', ') || 'none');
console.log('\n── Translation ──');
for (const k of ['all', ...LANGS]) console.log(k, `${translation.by[k].pass}/${translation.by[k].n}`);
console.log('per-check', translation.perCheck);
console.log('\n── Voice → task ──');
console.log('rate-limited on first try:', voice.rate_limited_first_try, 'hard errors:', voice.hard_errors);
for (const k of ['all', 'en', 'ta']) console.log(k, `${voice.by[k].ok}/${voice.by[k].n}`, `script ok ${voice.by[k].script_ok}`);
console.log('voice misses:', voice.rows.filter((r) => !r.category_ok).map((r) => `${r.id}: ${r.category ?? r.error}`).join(', ') || 'none');
console.log(`\nwrote ${OUT}`);
