#!/usr/bin/env node
/**
 * Live chat review: Tamil send + translation, phone/WhatsApp hard-block, lang coercion.
 *   node scripts/smoke-chat.mjs [API_URL]
 */
const API = (process.argv[2] || 'https://zivo-api-ihp5vjzpsa-el.a.run.app').replace(/\/$/, '');
const rows = [];
const must = (c, m) => { if (!c) throw new Error(m); };
async function step(name, fn) {
  const t0 = Date.now();
  try { const note = (await fn()) ?? ''; rows.push({ name, ok: true, ms: Date.now() - t0, note }); }
  catch (e) { rows.push({ name, ok: false, ms: Date.now() - t0, note: String(e?.message ?? e).slice(0, 200) }); }
}
const call = async (method, path, token, body) => {
  const r = await fetch(API + path, {
    method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: r.status, j: await r.json().catch(() => ({})) };
};
const stamp = Date.now();
const signup = async (who) => {
  const r = await call('POST', '/auth/signup', null, { email: `smoke.chat.${who}.${stamp}@zivo.test`, password: 'smoke-pass-1', full_name: `Chat ${who}` });
  must(r.j.accessToken, r.j.error ?? 'signup failed');
  return { token: r.j.accessToken, id: r.j.user.id };
};

let client, helper, taskId;

await step('setup: matched job so chat is open', async () => {
  client = await signup('client');
  helper = await signup('helper');
  await call('POST', '/wallet/topup', client.token, { amount_lkr: 8000 });
  const created = await call('POST', '/tasks', client.token, {
    title: 'Grocery help',
    description: 'Please buy rice and milk and bring to flat 4 this evening for testing chat.',
    category: 'groceryRun', estimated_hours: 1, goods_budget: 500, lat: 6.9271, lon: 79.8612,
    deadline_at: new Date(Date.now() + 4 * 3600e3).toISOString(), urgency: 'normal',
  });
  must(created.j.task, created.j.error ?? 'create');
  taskId = created.j.task.id;
  const acc = await call('POST', `/tasks/${taskId}/accept`, helper.token);
  must(acc.j.task?.status === 'matched', acc.j.error ?? `status=${acc.j.task?.status}`);
  return acc.j.task.status;
});

await step('Tamil message sends and keeps Tamil as original (not English)', async () => {
  const tamil = 'நான் வீட்டுக்கு வந்துட்டேன். பைகளை கதவுக்கு முன்னாடி வையுங்கள்.';
  const r = await call('POST', `/tasks/${taskId}/chat`, helper.token, { body: tamil, lang: 'ta' });
  must(r.status === 201, r.j.error ?? `status ${r.status}`);
  must(r.j.message?.body_original === tamil || r.j.message?.body === tamil, `original lost: ${JSON.stringify(r.j.message).slice(0, 180)}`);
  must(r.j.xlang?.source_lang === 'ta', `source_lang=${r.j.xlang?.source_lang}`);
  // English viewer should get a translation (may equal original if model fails — then still not "forced English overwrite of body_original")
  const list = await call('GET', `/tasks/${taskId}/chat?lang=en`, client.token);
  const last = (list.j.messages ?? []).at(-1);
  must(last, 'no messages');
  must(/[\u0B80-\u0BFF]/.test(last.body_original || last.body || ''), 'original script missing for EN viewer');
  return `source=${r.j.xlang.source_lang} · display_en=${String(last.display_body).slice(0, 40)}`;
});

await step('UI lang "hi" must not reject the send (coerce to en)', async () => {
  const r = await call('POST', `/tasks/${taskId}/chat`, client.token, { body: 'Please put the bags in the kitchen.', lang: 'hi' });
  must(r.status === 201, r.j.error ?? `status ${r.status} — Zod used to 400 on hi`);
});

await step('Phone number is hard-blocked (422), not redacted-and-sent', async () => {
  const r = await call('POST', `/tasks/${taskId}/chat`, client.token, { body: 'Call me on 0771234567 when you arrive', lang: 'en' });
  must(r.status === 422 && r.j.blocked === true, `expected 422 blocked, got ${r.status} ${JSON.stringify(r.j).slice(0, 120)}`);
  must(r.j.blocked_reason === 'phone' || /phone/i.test(r.j.error ?? ''), `reason=${r.j.blocked_reason}`);
});

await step('WhatsApp ask is hard-blocked', async () => {
  const r = await call('POST', `/tasks/${taskId}/chat`, helper.token, { body: 'WhatsApp me when you are outside', lang: 'en' });
  must(r.status === 422 && r.j.blocked === true, `got ${r.status}`);
});

await step('Tamil WhatsApp ask is hard-blocked', async () => {
  const r = await call('POST', `/tasks/${taskId}/chat`, helper.token, { body: 'வாட்ஸ்அப்ல மெசேஜ் பண்ணு', lang: 'ta' });
  must(r.status === 422 && r.j.blocked === true, `got ${r.status}`);
});

await step('Email is hard-blocked', async () => {
  const r = await call('POST', `/tasks/${taskId}/chat`, client.token, { body: 'Mail me at neighbour@gmail.com', lang: 'en' });
  must(r.status === 422 && r.j.blocked === true, `got ${r.status}`);
});

await step('Short Start OTP is still allowed', async () => {
  const r = await call('POST', `/tasks/${taskId}/chat`, client.token, { body: 'Start code is 4821', lang: 'en' });
  must(r.status === 201, r.j.error ?? `status ${r.status}`);
});

const w = Math.max(...rows.map((r) => r.name.length));
console.log('');
for (const r of rows) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name.padEnd(w)}  ${String(r.ms).padStart(6)} ms  ${r.note}`);
const failed = rows.filter((r) => !r.ok).length;
console.log(`\n${rows.length - failed}/${rows.length} passed`);
process.exit(failed ? 1 : 0);
