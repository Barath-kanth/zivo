#!/usr/bin/env node
/**
 * Where does "speak → split into tasks" spend its time? Times each live call, sequentially.
 *   node scripts/latency-voice.mjs [API_URL] [runs]
 */
const API = (process.argv[2] || 'https://zivo-api-ihp5vjzpsa-el.a.run.app').replace(/\/$/, '');
const RUNS = Number(process.argv[3] ?? 3);
const J = { 'content-type': 'application/json' };
const post = (p, b, h = {}) => fetch(API + p, { method: 'POST', headers: { ...J, ...h }, body: JSON.stringify(b) });
const ms = async (fn) => { const t = Date.now(); const r = await fn(); return [Date.now() - t, r]; };

const phone = '+94770009998';
const a = await (await post('/auth/otp/request', { phone })).json();
const v = await (await post('/auth/otp/verify', { phone, token: a.issuedCode })).json();
const auth = { authorization: `Bearer ${v.accessToken}` };

const tts = await (await post('/a11y/tts', { text: 'என் அம்மாவை மருத்துவமனைக்கு அழைத்துச் செல்ல ஒருவர் வேண்டும். பிறகு மருந்தும் வாங்கி வர வேண்டும்.', lang: 'ta' }, auth)).json();
const mp3 = Buffer.from(tts.audio_base64, 'base64');

const rows = [];
for (let i = 0; i < RUNS; i++) {
  const row = {};
  const form = () => { const f = new FormData(); f.append('audio', new Blob([mp3], { type: 'audio/mpeg' }), 'clip.mp3'); f.append('lang', 'auto'); return f; };
  let transcript = '';
  [row.suggest, ] = await ms(async () => {
    const r = await fetch(API + '/tasks/suggest-from-voice', { method: 'POST', headers: auth, body: form() });
    const j = await r.json(); transcript = j.transcript ?? ''; return j;
  });
  [row.plan] = await ms(async () => (await post('/tasks/plan', { problem: transcript || 'hospital trip with mother and pick up medicine', lang: 'auto' }, auth)).json());
  [row.voicePlan] = await ms(async () => {
    const r = await fetch(API + '/tasks/voice-plan', { method: 'POST', headers: auth, body: form() });
    const j = await r.json().catch(() => ({ error: `HTTP ${r.status}` }));
    row.vpMode = j.mode ?? j.error; row.vpTasks = j.tasks?.length ?? 0; return j;
  });
  rows.push(row);
  console.log(`run ${i + 1}: suggest ${row.suggest} ms + plan ${row.plan} ms = ${row.suggest + row.plan} ms | voice-plan ${row.voicePlan} ms (${row.vpMode}, ${row.vpTasks} tasks)`);
}
const med = (k) => rows.map((r) => r[k]).sort((x, y) => x - y)[Math.floor(rows.length / 2)];
console.log(`median: suggest+plan ${med('suggest') + med('plan')} ms · voice-plan ${med('voicePlan')} ms`);
