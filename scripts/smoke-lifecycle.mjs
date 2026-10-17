#!/usr/bin/env node
/**
 * Full job lifecycle against the LIVE API with two throw-away accounts:
 * post (escrow) → accept → cross-language chat → Start OTP → proof → End OTP → payout,
 * plus cancel-before-start (full refund) and a blocked chat message.
 *
 *   node scripts/smoke-lifecycle.mjs [API_URL]
 *
 * Creates `smoke.*@zivo.test` users and a few tasks in the live Firestore. Safe to rerun.
 */
const API = (process.argv[2] ?? 'https://zivo-api-ihp5vjzpsa-el.a.run.app').replace(/\/$/, '');
const rows = [];
const must = (c, m) => { if (!c) throw new Error(m); };
async function step(name, fn) {
  const t0 = Date.now();
  try { const note = (await fn()) ?? ''; rows.push({ name, ok: true, ms: Date.now() - t0, note }); }
  catch (e) { rows.push({ name, ok: false, ms: Date.now() - t0, note: String(e?.message ?? e).slice(0, 160) }); }
}
const call = async (method, path, token, body) => {
  const r = await fetch(API + path, {
    method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await r.json().catch(() => ({}));
  return { status: r.status, j };
};

const stamp = Date.now();
const signup = async (who) => {
  const r = await call('POST', '/auth/signup', null, { email: `smoke.${who}.${stamp}@zivo.test`, password: 'smoke-pass-1', full_name: `Smoke ${who}` });
  must(r.j.accessToken, r.j.error ?? 'signup failed');
  return { token: r.j.accessToken, id: r.j.user.id };
};
const me = async (u) => (await call('GET', '/me', u.token)).j.user;

let client, helper, task, startOtp, endOtp, before;
const newTask = (title) => call('POST', '/tasks', client.token, {
  title, description: 'Please buy rice and milk from the shop nearby and bring it to flat 4 this evening.',
  category: 'groceryRun', estimated_hours: 1, goods_budget: 500, lat: 6.9271, lon: 79.8612,
  deadline_at: new Date(Date.now() + 4 * 3600e3).toISOString(), urgency: 'normal',
});

await step('create client + helper accounts', async () => {
  client = await signup('client'); helper = await signup('helper');
  before = await me(client);
  return `client wallet LKR ${before.wallet_balance}`;
});

await step('post task → escrow held', async () => {
  const r = await newTask('Groceries for flat 4');
  must(r.status < 300 && r.j.task, r.j.error ?? `HTTP ${r.status}`);
  task = r.j.task;
  startOtp = task.start_otp; endOtp = task.end_otp ?? task.confirm_code;
  const u = await me(client);
  must(u.escrow_balance > 0, 'escrow not held');
  return `escrow LKR ${u.escrow_balance} · total ${task.total_amount}`;
});

await step('helper accepts', async () => {
  const r = await call('POST', `/tasks/${task.id}/accept`, helper.token);
  must(r.j.task?.status === 'matched', r.j.error ?? `status=${r.j.task?.status}`);
});

await step('chat: Tamil message arrives in Sinhala + English (live Gemini)', async () => {
  const send = await call('POST', `/tasks/${task.id}/chat`, client.token, { body: 'OTP 4821, வாசலில் வந்து மட்டும் சொல்லுங்கள்.', lang: 'ta' });
  must(send.status === 201, send.j.error ?? `HTTP ${send.status}`);
  must(send.j.xlang?.mode === 'gemini', `xlang mode=${send.j.xlang?.mode}`);
  const list = await call('GET', `/tasks/${task.id}/chat?lang=si`, helper.token);
  const m = (list.j.messages ?? []).find((x) => /4821/.test(x.body_original ?? x.body ?? ''));
  must(m, 'message not found in helper view');
  must(/[\u0D80-\u0DFF]/.test(m.display_body ?? ''), `helper did not get Sinhala: ${m.display_body}`);
  return m.display_body;
});

await step('chat: cash-mule message is blocked (422)', async () => {
  const r = await call('POST', `/tasks/${task.id}/chat`, client.token, { body: 'Withdraw cash from my friend’s ATM card, he gave me his PIN, and bring the money to me.', lang: 'en' });
  must(r.status === 422 && r.j.blocked, `status=${r.status}`);
});

await step('OTPs are hidden from helper + anonymous callers, visible to client', async () => {
  const leaks = (t) => ['start_otp', 'end_otp', 'confirm_code'].filter((k) => t && k in t);
  const act = (await call('GET', '/tasks/helper/active', helper.token)).j.tasks?.find((t) => t.id === task.id);
  must(act, 'helper cannot see own active job');
  must(!leaks(act).length, `helper sees ${leaks(act)}`);
  const anon = (await call('GET', `/tasks/${task.id}`, null)).j.task;
  must(!leaks(anon).length, `anonymous sees ${leaks(anon)}`);
  const mine = (await call('GET', '/tasks/mine', client.token)).j.tasks?.find((t) => t.id === task.id);
  must(mine?.start_otp && mine?.end_otp, 'client lost OTP visibility');
});

await step('wrong person cannot start or complete (403)', async () => {
  const a = await call('POST', `/tasks/${task.id}/start`, client.token, { start_otp: '0000' });
  const b = await call('POST', `/tasks/${task.id}/complete`, client.token, { confirm_code: '0000' });
  const c = await call('POST', `/tasks/${task.id}/complete`, null, { confirm_code: '0000' });
  must(a.status === 403 && b.status === 403, `start=${a.status} complete=${b.status}`);
  must(c.status === 400 && /Unauthorized/i.test(c.j.error ?? ''), `anon complete=${c.status}`);
});

await step('helper starts with Start OTP', async () => {
  must(startOtp, 'no start_otp visible on the client task');
  const r = await call('POST', `/tasks/${task.id}/start`, helper.token, { start_otp: startOtp });
  must(r.j.task?.status === 'in_progress', r.j.error ?? 'not in_progress');
});

await step('End OTP is refused before proof, accepted after', async () => {
  const early = await call('POST', `/tasks/${task.id}/complete`, helper.token, { confirm_code: endOtp, receipt_total_lkr: 0 });
  // Either proof is required (expected) or this task type does not need it.
  const needsProof = early.status >= 400 && /proof/i.test(early.j.error ?? '');
  if (needsProof) {
    const form = new FormData();
    const items = task.completion_checklist ?? task.checklist ?? [];
    form.append('checked_items', JSON.stringify(items.map((i) => i.label ?? i.id ?? String(i))));
    form.append('note', 'Delivered to flat 4');
    const pr = await fetch(`${API}/tasks/${task.id}/completion-proof`, { method: 'POST', headers: { authorization: `Bearer ${helper.token}` }, body: form });
    const pj = await pr.json();
    must(pr.ok, `proof: ${pj.error ?? pr.status}`);
  } else {
    must(early.status < 300, early.j.error ?? `HTTP ${early.status}`);
    return 'no proof required for this task';
  }
  const done = await call('POST', `/tasks/${task.id}/complete`, helper.token, { confirm_code: endOtp, receipt_total_lkr: 0 });
  must(done.j.task?.status === 'completed', done.j.error ?? 'not completed');
  return `released · fee LKR ${done.j.ledger?.platformFee}`;
});

await step('escrow released: helper paid, client escrow back to 0', async () => {
  const h = await me(helper), c = await me(client);
  must(c.escrow_balance === 0, `client escrow=${c.escrow_balance}`);
  must(h.helper_earnings > 0, 'helper earned nothing');
  return `helper +LKR ${h.helper_earnings}`;
});

await step('cancel before start → full refund', async () => {
  const w0 = (await me(client)).wallet_balance;
  const r = await newTask('Groceries to cancel');
  must(r.j.task, r.j.error ?? 'create failed');
  const held = (await me(client)).escrow_balance;
  must(held > 0, 'nothing held');
  const c = await call('POST', `/tasks/${r.j.task.id}/cancel`, client.token, { reason: 'plans changed, smoke test' });
  must(c.j.task?.status === 'cancelled', c.j.error ?? 'not cancelled');
  const after = await me(client);
  must(after.escrow_balance === 0, `escrow stuck: ${after.escrow_balance}`);
  must(Math.abs(after.wallet_balance - w0) < 0.01, `wallet ${after.wallet_balance} vs ${w0}`);
  return `wallet back to LKR ${after.wallet_balance}`;
});

const w = Math.max(...rows.map((r) => r.name.length));
console.log('');
for (const r of rows) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name.padEnd(w)}  ${String(r.ms).padStart(6)} ms  ${r.note}`);
const failed = rows.filter((r) => !r.ok).length;
console.log(`\n${rows.length - failed}/${rows.length} passed`);
process.exit(failed ? 1 : 0);
