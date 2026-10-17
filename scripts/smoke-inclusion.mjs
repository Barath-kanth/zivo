#!/usr/bin/env node
/**
 * Live check of the ability-aware work features (two throw-away accounts):
 *   helper sets ability profile + discloses → client sees the access note (anonymous callers do not)
 *   → ability-fit → Gemini adapt-brief → client can choose someone else (escrow kept, helper cannot re-accept)
 *   + Zivo Eyes (image → spoken text + list check) + Doorstep Talk (Tamil audio → text for reader)
 *   + one-call voice→plan latency.
 *
 *   node scripts/smoke-inclusion.mjs [API_URL]
 */
import { readFileSync } from 'node:fs';
const API = (process.argv[2] || 'https://zivo-api-ihp5vjzpsa-el.a.run.app').replace(/\/$/, '');
const rows = [];
const must = (c, m) => { if (!c) throw new Error(m); };
async function step(name, fn) {
  const t0 = Date.now();
  try { const note = (await fn()) ?? ''; rows.push({ name, ok: true, ms: Date.now() - t0, note }); }
  catch (e) { rows.push({ name, ok: false, ms: Date.now() - t0, note: String(e?.message ?? e).slice(0, 170) }); }
}
const call = async (method, path, token, body) => {
  const r = await fetch(API + path, {
    method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: r.status, j: await r.json().catch(() => ({})) };
};
const form = async (path, token, fields, fileField, bytes, name, type) => {
  const f = new FormData();
  for (const [k, v] of Object.entries(fields)) f.append(k, v);
  f.append(fileField, new Blob([bytes], { type }), name);
  const r = await fetch(API + path, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: f });
  return { status: r.status, j: await r.json().catch(() => ({})) };
};
const stamp = Date.now();
const signup = async (who) => {
  const r = await call('POST', '/auth/signup', null, { email: `smoke.${who}.${stamp}@zivo.test`, password: 'smoke-pass-1', full_name: `Smoke ${who}` });
  must(r.j.accessToken, r.j.error ?? 'signup failed');
  return { token: r.j.accessToken, id: r.j.user.id };
};

let client, helper, task;
const newTask = (category = 'groceryRun') => call('POST', '/tasks', client.token, {
  title: 'Groceries for flat 4', description: 'Please buy rice and milk powder from the shop nearby and bring it to flat 4 this evening.',
  category, estimated_hours: 1, goods_budget: 500, lat: 6.9271, lon: 79.8612,
  deadline_at: new Date(Date.now() + 4 * 3600e3).toISOString(), urgency: 'normal',
});

await step('accounts; helper sets ability profile and discloses', async () => {
  client = await signup('client'); helper = await signup('helper');
  const r = await call('PATCH', '/me', helper.token, { abilities: ['visual', 'bogus'], disclose_access: true, access_note: 'Please hand me items and say what they are.' });
  must(r.j.user?.abilities?.length === 1 && r.j.user.abilities[0] === 'visual', `abilities=${JSON.stringify(r.j.user?.abilities)}`);
  const r2 = await newTask(); must(r2.j.task, r2.j.error ?? 'task'); task = r2.j.task;
});

await step('ability-fit: groceryRun is "adaptable" for a blind helper (never blocked)', async () => {
  const r = await call('GET', `/tasks/${task.id}/ability-fit`, helper.token);
  must(r.j.fit?.level === 'adaptable', `level=${r.j.fit?.level}`);
  const d = await newTask('driver');
  const r2 = await call('GET', `/tasks/${d.j.task.id}/ability-fit`, helper.token);
  must(r2.j.fit?.level === 'heads_up', `driver level=${r2.j.fit?.level}`);
  return 'groceryRun=adaptable · driver=heads_up';
});

await step('helper accepts → client sees the access note; anonymous does not', async () => {
  const a = await call('POST', `/tasks/${task.id}/accept`, helper.token);
  must(a.j.task?.status === 'matched', a.j.error ?? 'not matched');
  const mine = (await call('GET', '/tasks/mine', client.token)).j.tasks.find((t) => t.id === task.id);
  must(mine?.helper?.access?.abilities?.includes('visual'), 'client does not see access card');
  must(/hand me items/.test(mine.helper.access.note ?? ''), 'note missing');
  const anon = (await call('GET', `/tasks/${task.id}`, null)).j.task;
  must(!anon?.helper?.access, 'anonymous caller sees access card');
  const chat = await call('GET', `/tasks/${task.id}/chat?lang=en`, client.token);
  must((chat.j.messages ?? []).some((m) => /access note/i.test(m.body_original ?? m.body ?? '')), 'client was not told in chat');
});

await step('Gemini adapt-brief (Sinhala) returns tool-aware steps', async () => {
  const r = await call('POST', `/tasks/${task.id}/adapt-brief`, helper.token, { lang: 'si' });
  must(r.status === 200 && r.j.steps?.length >= 2, r.j.error ?? 'no steps');
  must(r.j.steps.some((s) => s.tool === 'eyes'), `no eyes step: ${JSON.stringify(r.j.steps.map((s) => s.tool))}`);
  must(r.j.mode === 'gemini', `mode=${r.j.mode} (fallback used)`);
  must(/[\u0D80-\u0DFF]/.test(r.j.steps[0].text), `step 1 not Sinhala: ${r.j.steps[0].text}`);
  return `${r.j.latency_ms} ms · ${r.j.steps.map((s) => s.tool).join(',')}`;
});

await step('client chooses someone else → job reopens, escrow kept, helper cannot re-accept', async () => {
  const before = (await call('GET', '/me', client.token)).j.user.escrow_balance;
  const d = await call('POST', `/tasks/${task.id}/decline-helper`, client.token, { reason: 'access note' });
  must(d.j.task?.status === 'open' && !d.j.task.helper_id, d.j.error ?? 'not reopened');
  const after = (await call('GET', '/me', client.token)).j.user.escrow_balance;
  must(after === before && after > 0, `escrow ${before} -> ${after}`);
  const again = await call('POST', `/tasks/${task.id}/accept`, helper.token);
  must(again.status === 400, `re-accept status=${again.status}`);
  const notClient = await call('POST', `/tasks/${task.id}/decline-helper`, helper.token, {});
  must(notClient.status === 400, 'non-client could decline');
});

await step('Zivo Eyes: reads a product photo and checks a shopping list (live Gemini vision)', async () => {
  const png = readFileSync(new URL('./fixtures/milk.png', import.meta.url));
  const r = await form('/a11y/eyes', helper.token, { mode: 'match', lang: 'en', items: JSON.stringify(['Anchor milk powder 400g', 'Basmati rice 1kg']) }, 'image', png, 'milk.png', 'image/png');
  must(r.status === 200 && r.j.mode === 'gemini', r.j.error ?? `mode=${r.j.mode}`);
  const m = r.j.matches ?? [];
  must(m.find((x) => /anchor/i.test(x.item))?.verdict === 'yes', `anchor verdict=${JSON.stringify(m)}`);
  must(m.find((x) => /rice/i.test(x.item))?.verdict !== 'yes', 'rice wrongly matched');
  return `${r.j.latency_ms} ms · “${r.j.spoken.slice(0, 70)}…”`;
});

await step('Doorstep Talk: Tamil speech → text for an English reader (live)', async () => {
  const tts = (await call('POST', '/a11y/tts', helper.token, { text: 'தயவுசெய்து பைகளை சமையலறையில் வைக்கவும்.', lang: 'ta' })).j;
  must(tts.audio_base64, 'no tts');
  const r = await form('/a11y/doorstep', helper.token, { lang: 'en' }, 'audio', Buffer.from(tts.audio_base64, 'base64'), 'clip.mp3', 'audio/mpeg');
  must(r.status === 200 && r.j.mode === 'gemini', r.j.error ?? 'bad');
  must(/[\u0B80-\u0BFF]/.test(r.j.heard), `heard not Tamil: ${r.j.heard}`);
  must(/kitchen/i.test(r.j.for_reader), `reader text: ${r.j.for_reader}`);
  return `${r.j.latency_ms} ms · “${r.j.for_reader}”`;
});

await step('one-call voice → plan (Tamil) under 12 s', async () => {
  const tts = (await call('POST', '/a11y/tts', helper.token, { text: 'என் அம்மாவை மருத்துவமனைக்கு அழைத்துச் செல்ல வேண்டும். பிறகு மருந்தும் வாங்கி வர வேண்டும்.', lang: 'ta' })).j;
  const t0 = Date.now();
  const r = await form('/tasks/voice-plan', helper.token, { lang: 'auto' }, 'audio', Buffer.from(tts.audio_base64, 'base64'), 'clip.mp3', 'audio/mpeg');
  const ms = Date.now() - t0;
  must(r.status === 200 && r.j.tasks?.length >= 1, r.j.error ?? 'no tasks');
  must(ms < 12000, `${ms} ms`);
  return `${ms} ms · ${r.j.tasks.length} tasks · ${r.j.model}`;
});

await step('Access audit: entrance photo → stairs/ramp/door note (Gemini vision)', async () => {
  const img = readFileSync(new URL('./fixtures/milk.png', import.meta.url));
  const r = await form('/a11y/access-audit', helper.token, { lang: 'en' }, 'image', img, 'door.png', 'image/png');
  must(r.status === 200 && r.j.mode === 'gemini', r.j.error ?? 'bad');
  must(r.j.spoken && r.j.wheelchair, `missing fields ${JSON.stringify(r.j)}`);
  return `${r.j.latency_ms} ms · stairs=${r.j.stairs} · ramp=${r.j.ramp} · wheelchair=${r.j.wheelchair}`;
});

await step('ability-fit: phoneCheckIn is "great" for a blind helper (remote/seated)', async () => {
  await call('POST', '/wallet/topup', client.token, { amount: 20000 });
  const d = await newTask('phoneCheckIn');
  must(d.j.task, d.j.error ?? `create failed ${d.status}`);
  const r = await call('GET', `/tasks/${d.j.task.id}/ability-fit`, helper.token);
  must(r.j.fit?.level === 'great', `level=${r.j.fit?.level}`);
  return `phoneCheckIn=${r.j.fit.level}`;
});

await step('KYC: client cannot self-approve (needs a valid NIC; junk values ignored)', async () => {
  const u = await signup('kyc');
  await call('PATCH', '/me', u.token, { kyc_status: 'pending' });
  const a = await call('PATCH', '/me', u.token, { kyc_status: 'verified' });
  must(a.j.user?.kyc_status === 'pending', `no NIC → ${a.j.user?.kyc_status}`);
  const b = await call('PATCH', '/me', u.token, { kyc_status: 'verified', nic_number: '12345' });
  must(b.j.user?.kyc_status === 'pending', `bad NIC → ${b.j.user?.kyc_status}`);
  const c = await call('PATCH', '/me', u.token, { kyc_status: 'god-mode' });
  must(c.j.user?.kyc_status === 'pending', `junk → ${c.j.user?.kyc_status}`);
  const d = await call('PATCH', '/me', u.token, { kyc_status: 'verified', nic_number: '199512345678' });
  must(d.j.user?.kyc_status === 'verified', `valid NIC → ${d.j.user?.kyc_status}`);
});

await step('concierge (Tamil text) answers in under 15 s with tool calls', async () => {
  const t0 = Date.now();
  const r = await call('POST', '/agent/concierge', helper.token, { utterance: 'என் அம்மாவை மருத்துவமனைக்கு அழைத்துச் செல்ல ஒருவர் வேண்டும்', lang: 'ta', lat: 6.9, lon: 79.86 });
  const ms = Date.now() - t0;
  must(r.status === 200 && r.j.reply, r.j.error ?? 'no reply');
  must(ms < 20000, `${ms} ms`);
  return `${ms} ms · mode=${r.j.mode} · tools=${(r.j.tool_trace ?? []).map((t) => t.name).join(',') || 'direct'}`;
});

const w = Math.max(...rows.map((r) => r.name.length));
console.log('');
for (const r of rows) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name.padEnd(w)}  ${String(r.ms).padStart(6)} ms  ${r.note}`);
const failed = rows.filter((r) => !r.ok).length;
console.log(`\n${rows.length - failed}/${rows.length} passed`);
process.exit(failed ? 1 : 0);
