#!/usr/bin/env node
/**
 * Demo-path smoke test against the LIVE deployment. Run it 5 minutes before you present.
 *
 *   node scripts/smoke-demo.mjs [API_URL] [WEB_URL]
 *
 * Exits non-zero if any step fails, so you find out before the judges do.
 * Uses a dedicated smoke-test phone number; it never creates tasks or moves money.
 */
const API = (process.argv[2] ?? 'https://zivo-api-ihp5vjzpsa-el.a.run.app').replace(/\/$/, '');
const WEB = (process.argv[3] ?? 'https://zivo-web-ihp5vjzpsa-el.a.run.app').replace(/\/$/, '');
const J = { 'content-type': 'application/json' };
const rows = [];
let token = '';

async function step(name, fn) {
  const t0 = Date.now();
  try {
    const note = await fn();
    rows.push({ name, ok: true, ms: Date.now() - t0, note: note ?? '' });
  } catch (e) {
    rows.push({ name, ok: false, ms: Date.now() - t0, note: String(e?.message ?? e).slice(0, 140) });
  }
}
const must = (cond, msg) => { if (!cond) throw new Error(msg); };
const post = (p, b, h = {}) => fetch(API + p, { method: 'POST', headers: { ...J, ...h }, body: JSON.stringify(b) });

await step('web app serves (zivo-web)', async () => {
  const r = await fetch(WEB);
  must(r.ok, `HTTP ${r.status}`);
  const html = await r.text();
  must(/flutter/i.test(html), 'no Flutter bootstrap found');
});

await step('api health + live Gemini (not mock)', async () => {
  const j = await (await fetch(API + '/health')).json();
  must(j.ok, 'not ok');
  must(j.mockAi === false, 'USE_MOCK_AI is true');
  must(j.db === 'firestore', `db=${j.db} (memory store would lose data between instances)`);
  return `db=${j.db} model=${j.geminiModel}`;
});

await step('sign in with OTP (smoke account)', async () => {
  const phone = '+94770009998';
  const a = await (await post('/auth/otp/request', { phone })).json();
  must(a.issuedCode, 'OTP not exposed (EXPOSE_OTP=false?)');
  const v = await (await post('/auth/otp/verify', { phone, token: a.issuedCode })).json();
  must(v.accessToken, v.error ?? 'no token');
  token = v.accessToken;
});

const safety = (title, description) => post('/tasks/safety-check', { title, description }).then((r) => r.json());
await step('safety: allows ordinary English chore', async () => {
  const j = await safety('Medicine pickup', 'Please pick up my mother’s medicine from the pharmacy and bring it upstairs.');
  must(j.action !== 'block', `action=${j.action}`);
});
await step('safety: blocks Tamil drug request', async () => {
  const j = await safety('கஞ்சா', 'கஞ்சா வாங்கி வர ஒருவர் வேண்டும்.');
  must(j.action === 'block', `action=${j.action}`);
});
await step('safety: blocks Sinhala "don’t ask what’s inside" euphemism', async () => {
  const j = await safety('පාර්සලය', 'මේ පාර්සලය ඇතුළේ මොකක්ද කියලා අහන්නැතුව කෙනෙකුට දීලා එන්න, දෙගුණයක් දෙන්නම්.');
  must(j.action === 'block', `action=${j.action} degraded=${j.degraded}`);
});

await step('concierge agent answers in Tamil (no tool-code leak)', async () => {
  const j = await (await post('/agent/concierge', { utterance: 'எனக்கு மருந்துக்கடையிலிருந்து மருந்து வாங்கி வர உதவி வேண்டும்', lang: 'ta' })).json();
  must(j.reply && j.reply.length > 5, j.error ?? 'empty reply');
  must(!/default_api|tool_code|```|\{"/.test(j.reply), 'reply leaks internals');
  return `mode=${j.mode} category=${j.draft?.category}`;
});

let mp3 = null;
await step('Cloud Text-to-Speech (ta-IN)', async () => {
  const j = await (await post('/a11y/tts', { text: 'என் அம்மாவை மருத்துவமனைக்கு அழைத்துச் செல்ல ஒருவர் வேண்டும்.', lang: 'ta' }, { authorization: `Bearer ${token}` })).json();
  must(j.audio_base64, j.error ?? 'no audio');
  must(j.mode === 'cloud', `mode=${j.mode}`);
  mp3 = Buffer.from(j.audio_base64, 'base64');
  return `${j.voice} ${mp3.length}B`;
});

await step('voice → task draft (audio in, category out)', async () => {
  must(mp3, 'no audio from previous step');
  const form = new FormData();
  form.append('audio', new Blob([mp3], { type: 'audio/mpeg' }), 'clip.mp3');
  form.append('lang', 'auto');
  const r = await fetch(API + '/tasks/suggest-from-voice', { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: form });
  const j = await r.json();
  must(r.ok, j.error ?? `HTTP ${r.status}`);
  must(['hospitalCompanion', 'elderCare'].includes(j.category), `category=${j.category}`);
  return `${j.category} · “${String(j.transcript).slice(0, 30)}…”`;
});

await step('resilience status (Open-Meteo)', async () => {
  const j = await (await fetch(API + '/resilience/status?lat=6.9271&lon=79.8612')).json();
  must(j.hazard, 'no hazard');
  return `${j.hazard} · ${j.precip_mm_next_24h} mm · mode=${j.mode}`;
});

await step('fair-price quote (wage floor)', async () => {
  const j = await (await post('/tasks/price-quote', {
    title: 'Groceries', description: 'Buy rice and milk from the shop nearby and bring them home.',
    category: 'groceryRun', lat: 6.9271, lon: 79.8612, duration_minutes: 30,
  })).json();
  must(j.labor_lkr > 0, j.error ?? 'no labor floor');
  return `labor LKR ${j.labor_lkr}`;
});

await step('impact summary (Pub/Sub → Firestore)', async () => {
  const j = await (await fetch(API + '/impact/summary?source=all')).json();
  must(typeof j.events === 'number', 'no events field');
  return `${j.events} events, topic=${j.pubsub_topic}`;
});

const w = Math.max(...rows.map((r) => r.name.length));
console.log('');
for (const r of rows) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name.padEnd(w)}  ${String(r.ms).padStart(6)} ms  ${r.note}`);
const failed = rows.filter((r) => !r.ok).length;
console.log(`\n${rows.length - failed}/${rows.length} passed`);
process.exit(failed ? 1 : 0);
