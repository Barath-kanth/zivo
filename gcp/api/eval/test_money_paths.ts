/**
 * Money-path regression test (in-memory store, no cloud calls).
 *   USE_MEMORY_STORE=true USE_MOCK_AI=true npx tsx eval/test_money_paths.ts
 * Checks that escrow is conserved on: cancel-before-start, cancel-after-start, dispute freeze.
 */
import assert from 'node:assert/strict';
import {
  signUpEmail, topUp, createTask, acceptTask, startTask, cancelClientTask,
  openTaskDispute, getUser,
} from '../src/store.js';

const total = async (id: string) => {
  const u = (await getUser(id))!;
  return { wallet: u.wallet_balance, escrow: u.escrow_balance, sum: u.wallet_balance + u.escrow_balance };
};
const mk = async (name: string) =>
  (await signUpEmail({ email: `${name}${Date.now()}@t.io`, password: 'secret12', full_name: name }));
const task = (client_id: string) => createTask({
  client_id, title: 'Groceries', description: 'Buy rice and milk and bring to flat 4.',
  category: 'groceryRun', estimated_hours: 1, hourly_rate: 1000, goods_budget: 500,
  lat: 6.9, lon: 79.86, deadline_at: new Date(Date.now() + 3600e3).toISOString(),
});

// 1) cancel before start → full refund
{
  const c = await mk('c1'); await topUp(c.id, 5000);
  const start = (await total(c.id)).wallet;
  const t = await task(c.id);
  assert.equal((await total(c.id)).escrow, 1500, 'escrow held');
  await cancelClientTask({ taskId: t.id, userId: c.id, reason: 'plans changed' });
  const a = await total(c.id);
  assert.equal(a.escrow, 0); assert.equal(a.wallet, start);
  console.log('PASS cancel before start → full refund', a);
}
// 2) cancel after Start OTP → 30% call-out (less 10% fee) to helper, rest to client
{
  const c = await mk('c2'); const h = await mk('h2'); await topUp(c.id, 5000);
  const start = (await total(c.id)).wallet; const hStart = (await total(h.id)).wallet;
  const t = await task(c.id);
  await acceptTask(t.id, h.id);
  await startTask(t.id, (await (await import('../src/store.js')).getTask(t.id))!.start_otp!);
  await cancelClientTask({ taskId: t.id, userId: c.id, reason: 'helper started but I must stop' });
  const a = await total(c.id), hh = await total(h.id);
  assert.equal(a.escrow, 0);
  assert.equal(a.wallet, start - 300);          // client loses exactly the 30% call-out of 1000 labour
  assert.equal(hh.wallet, hStart + 300 * 0.9);          // helper gets 270 after the 10% platform fee
  console.log('PASS cancel after start → client', a, 'helper', hh);
}
// 3) dispute freezes: escrow stays held, cancel is refused
{
  const c = await mk('c3'); const h = await mk('h3'); await topUp(c.id, 5000);
  const t = await task(c.id);
  await acceptTask(t.id, h.id);
  await openTaskDispute({ taskId: t.id, userId: h.id, reason: 'client is asking for cash handoff' });
  assert.equal((await total(c.id)).escrow, 1500, 'escrow remains frozen');
  await assert.rejects(() => cancelClientTask({ taskId: t.id, userId: c.id, reason: 'try to escape' }), /dispute/);
  console.log('PASS dispute freezes escrow and blocks cancel');
}
console.log('all money-path checks passed');
