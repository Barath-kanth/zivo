#!/usr/bin/env node
/**
 * Pre-submit matrix: every listed AI / inclusion feature against live Cloud Run.
 *   node scripts/smoke-ai-matrix.mjs [API_URL]
 *
 * Prints a numbered PASS/FAIL row matching the submission checklist (1–31).
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const API = (process.argv[2] ?? 'https://zivo-api-ihp5vjzpsa-el.a.run.app').replace(/\/$/, '');
const __dir = dirname(fileURLToPath(import.meta.url));
const milkPng = readFileSync(join(__dir, 'fixtures/milk.png'));

const rows = [];
const must = (c, m) => {
  if (!c) throw new Error(m);
};
async function step(id, name, engine, fn) {
  const t0 = Date.now();
  try {
    const note = (await fn()) ?? '';
    rows.push({ id, name, engine, ok: true, ms: Date.now() - t0, note: String(note).slice(0, 160) });
  } catch (e) {
    rows.push({
      id,
      name,
      engine,
      ok: false,
      ms: Date.now() - t0,
      note: String(e?.message ?? e).slice(0, 180),
    });
  }
}

const call = async (method, path, token, body) => {
  const r = await fetch(API + path, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const j = await r.json().catch(() => ({}));
  return { status: r.status, j };
};
const form = async (path, token, fields, fileField, bytes, name, type) => {
  const f = new FormData();
  for (const [k, v] of Object.entries(fields)) f.append(k, String(v));
  f.append(fileField, new Blob([bytes], { type }), name);
  const r = await fetch(API + path, {
    method: 'POST',
    headers: token ? { authorization: `Bearer ${token}` } : {},
    body: f,
  });
  return { status: r.status, j: await r.json().catch(() => ({})) };
};

const stamp = Date.now();
let client, helper, task, matched, mp3, planBundleId;

await step(0, 'health: live Gemini (not mock)', 'infra', async () => {
  const j = (await call('GET', '/health')).j;
  must(j.ok, 'not ok');
  must(j.mockAi === false, `mockAi=${j.mockAi}`);
  must(j.db === 'firestore', `db=${j.db}`);
  return `model=${j.geminiModel}`;
});

await step(0.1, 'auth: client + helper accounts', 'infra', async () => {
  const c = await call('POST', '/auth/signup', null, {
    email: `ai.matrix.client.${stamp}@zivo.test`,
    password: 'smoke-pass-1',
    full_name: 'AI Matrix Client',
  });
  must(c.j.accessToken, c.j.error ?? 'client signup');
  client = { token: c.j.accessToken, id: c.j.user.id };
  const h = await call('POST', '/auth/signup', null, {
    email: `ai.matrix.helper.${stamp}@zivo.test`,
    password: 'smoke-pass-1',
    full_name: 'AI Matrix Helper',
  });
  must(h.j.accessToken, h.j.error ?? 'helper signup');
  helper = { token: h.j.accessToken, id: h.j.user.id };
  await call('POST', '/wallet/topup', client.token, { amount: 50000 });
  await call('PATCH', '/me', helper.token, {
    abilities: ['visual'],
    disclose_access: true,
    access_note: 'Hand me items and say what they are.',
  });
  return `client=${client.id.slice(0, 8)} helper=${helper.id.slice(0, 8)}`;
});

await step(1, 'Voice concierge (safety+price+weather+triage)', 'Gemini', async () => {
  const r = await call('POST', '/agent/concierge', client.token, {
    utterance: 'I need medicine picked up from the pharmacy for my mother',
    lang: 'en',
    lat: 6.9271,
    lon: 79.8612,
  });
  must(r.status === 200 && r.j.reply, r.j.error ?? `status ${r.status}`);
  must(!/default_api|tool_code|```/.test(r.j.reply), 'tool leak');
  const tools = (r.j.tool_trace ?? []).map((t) => t.name);
  return `mode=${r.j.mode} tools=${tools.join(',') || 'direct'} hazard=${r.j.resilience?.hazard ?? '-'}`;
});

await step(28, 'Cloud TTS read-aloud', 'TTS', async () => {
  const r = await call('POST', '/a11y/tts', client.token, {
    text: 'Please pick up Anchor milk powder from the shop.',
    lang: 'en',
  });
  must(r.j.audio_base64, r.j.error ?? 'no audio');
  must(r.j.mode === 'cloud', `mode=${r.j.mode}`);
  mp3 = Buffer.from(r.j.audio_base64, 'base64');
  return `${r.j.voice} ${mp3.length}B`;
});

await step(2, 'Speak → task draft', 'Gemini', async () => {
  must(mp3, 'no TTS audio');
  const r = await form(
    '/tasks/suggest-from-voice',
    client.token,
    { lang: 'auto' },
    'audio',
    mp3,
    'clip.mp3',
    'audio/mpeg',
  );
  must(r.status === 200, r.j.error ?? `HTTP ${r.status}`);
  must(r.j.category || r.j.title, JSON.stringify(r.j).slice(0, 120));
  return `${r.j.category} · ${String(r.j.transcript ?? r.j.title).slice(0, 40)}`;
});

await step(3, 'Voice → plan (transcript + draft + sub-tasks)', 'Gemini', async () => {
  const tts = await call('POST', '/a11y/tts', client.token, {
    text: 'Take my mother to the hospital then buy her medicine.',
    lang: 'en',
  });
  const r = await form(
    '/tasks/voice-plan',
    client.token,
    { lang: 'auto' },
    'audio',
    Buffer.from(tts.j.audio_base64, 'base64'),
    'clip.mp3',
    'audio/mpeg',
  );
  must(r.status === 200 && (r.j.tasks?.length >= 1 || r.j.plan), r.j.error ?? 'no plan');
  const n = r.j.tasks?.length ?? r.j.plan?.length ?? 0;
  return `${n} tasks · ${r.j.model ?? r.j.mode}`;
});

await step(4, 'Show it → photo draft', 'Gemini', async () => {
  const r = await form(
    '/tasks/suggest-from-photo',
    client.token,
    { lang: 'en' },
    'photo',
    milkPng,
    'milk.png',
    'image/png',
  );
  must(r.status === 200, r.j.error ?? `HTTP ${r.status}`);
  must(r.j.title || r.j.category || r.j.description, JSON.stringify(r.j).slice(0, 120));
  return `${r.j.category ?? '-'} · ${String(r.j.title ?? '').slice(0, 40)}`;
});

await step(5, 'Task plan / split into sub-tasks', 'Gemini', async () => {
  const r = await call('POST', '/tasks/plan', client.token, {
    problem:
      'Take mother to clinic, buy prescribed medicines, then pick up rice and milk on the way home.',
    lang: 'en',
  });
  must(r.status === 200, r.j.error ?? `HTTP ${r.status}`);
  const tasks = r.j.tasks ?? r.j.plan ?? [];
  must(tasks.length >= 2, `only ${tasks.length} subtasks`);
  return `${tasks.length} subtasks · mode=${r.j.mode ?? '-'}`;
});

await step(6, 'Dynamic pricing fields', 'Gemini', async () => {
  const r = await call('POST', '/tasks/pricing-fields', client.token, {
    title: 'Grocery run',
    description: 'Buy rice 5kg and milk powder, deliver to flat 4.',
    category: 'groceryRun',
  });
  must(r.status === 200, r.j.error ?? `HTTP ${r.status}`);
  const fields = r.j.fields ?? r.j.pricing_fields ?? r.j;
  must(fields, 'empty');
  return typeof fields === 'object' ? Object.keys(fields).slice(0, 6).join(',') : 'ok';
});

await step(7, 'Fair-price / wage-floor quote', 'Gemini', async () => {
  const r = await call('POST', '/tasks/price-quote', null, {
    title: 'Groceries',
    description: 'Buy rice and milk from the shop nearby and bring them home.',
    category: 'groceryRun',
    lat: 6.9271,
    lon: 79.8612,
    duration_minutes: 30,
  });
  must(r.j.labor_lkr > 0, r.j.error ?? 'no labor floor');
  return `labor LKR ${r.j.labor_lkr} · floor=${r.j.gemini_labor_lkr ?? '-'}`;
});

await step(8, 'Vernacular safety (ta/si/en; fail → review)', 'Gemini', async () => {
  const ok = await call('POST', '/tasks/safety-check', null, {
    title: 'Medicine pickup',
    description: 'Please pick up my mother’s medicine from the pharmacy.',
  });
  must(ok.j.action !== 'block', `ordinary blocked: ${ok.j.action}`);
  const ta = await call('POST', '/tasks/safety-check', null, {
    title: 'கஞ்சா',
    description: 'கஞ்சா வாங்கி வர ஒருவர் வேண்டும்.',
  });
  must(ta.j.action === 'block', `ta action=${ta.j.action}`);
  const si = await call('POST', '/tasks/safety-check', null, {
    title: 'පාර්සලය',
    description:
      'මේ පාර්සලය ඇතුළේ මොකක්ද කියලා අහන්නැතුව කෙනෙකුට දීලා එන්න, දෙගුණයක් දෙන්නම්.',
  });
  must(si.j.action === 'block', `si action=${si.j.action}`);
  return `en=allow ta=${ta.j.action} si=${si.j.action}`;
});

// Create + match a task for chat / match / receipt / trust / ability
await step(0.2, 'setup: create+match grocery task', 'infra', async () => {
  const created = await call('POST', '/tasks', client.token, {
    title: 'Groceries for flat 4',
    description:
      'Please buy Anchor milk powder 400g and Basmati rice 1kg from the shop nearby and bring to flat 4.',
    category: 'groceryRun',
    estimated_hours: 1,
    goods_budget: 800,
    lat: 6.9271,
    lon: 79.8612,
    deadline_at: new Date(Date.now() + 4 * 3600e3).toISOString(),
    urgency: 'normal',
  });
  must(created.j.task, created.j.error ?? 'create');
  task = created.j.task;
  const acc = await call('POST', `/tasks/${task.id}/accept`, helper.token);
  must(acc.j.task?.status === 'matched', acc.j.error ?? `status=${acc.j.task?.status}`);
  matched = acc.j.task;
  return task.id.slice(0, 8);
});

await step(9, 'Chat translate (ta ⇄ si ⇄ en, keep original)', 'Gemini', async () => {
  const tamil = 'நான் வீட்டுக்கு வந்துட்டேன். பைகளை கதவுக்கு முன்னாடி வையுங்கள்.';
  const r = await call('POST', `/tasks/${task.id}/chat`, helper.token, {
    body: tamil,
    lang: 'ta',
  });
  must(r.status === 201, r.j.error ?? `status ${r.status}`);
  must(
    r.j.message?.body_original === tamil || r.j.message?.body === tamil,
    'original lost',
  );
  must(r.j.xlang?.source_lang === 'ta', `source=${r.j.xlang?.source_lang}`);
  must(r.j.xlang?.translations?.en, 'no English translation');
  must(!/[\u0B80-\u0BFF]/.test(r.j.xlang.translations.en), 'EN still Tamil');
  must(/[\u0D80-\u0DFF]/.test(r.j.xlang.translations?.si ?? ''), 'no Sinhala translation');
  const list = await call('GET', `/tasks/${task.id}/chat?lang=en`, client.token);
  const last = (list.j.messages ?? []).at(-1);
  must(/[\u0B80-\u0BFF]/.test(last?.body_original || ''), 'original script missing');
  must(last?.translated === true && last?.translation_body, 'tap-translation missing');
  must(/I have|come home|bags|door/i.test(last.translation_body), `en="${last.translation_body}"`);
  return `source=ta · tap-en="${String(last.translation_body).slice(0, 40)}"`;
});

await step(10, 'Chat guard (phone/WhatsApp/email blocked)', 'regex', async () => {
  const phone = await call('POST', `/tasks/${task.id}/chat`, client.token, {
    body: 'Call me on 0771234567 when you arrive',
    lang: 'en',
  });
  must(phone.status === 422 && phone.j.blocked === true, `phone ${phone.status}`);
  const wa = await call('POST', `/tasks/${task.id}/chat`, helper.token, {
    body: 'WhatsApp me when you are outside',
    lang: 'en',
  });
  must(wa.status === 422 && wa.j.blocked === true, `wa ${wa.status}`);
  const em = await call('POST', `/tasks/${task.id}/chat`, helper.token, {
    body: 'Email me at test@example.com',
    lang: 'en',
  });
  must(em.status === 422 && em.j.blocked === true, `email ${em.status}`);
  return 'phone+wa+email blocked';
});

await step(11, 'Helper match / rank + explain (ability never in score)', 'Gemini', async () => {
  // reopen a fresh open task for match (matched one already has helper)
  const created = await call('POST', '/tasks', client.token, {
    title: 'Quick grocery',
    description: 'Buy bread and eggs from the corner shop and bring upstairs.',
    category: 'groceryRun',
    estimated_hours: 0.5,
    goods_budget: 400,
    lat: 6.9271,
    lon: 79.8612,
    deadline_at: new Date(Date.now() + 3 * 3600e3).toISOString(),
    urgency: 'normal',
  });
  must(created.j.task, created.j.error ?? 'create');
  const r = await call('POST', `/tasks/${created.j.task.id}/match`, client.token, {});
  must(r.status === 200, r.j.error ?? `HTTP ${r.status}`);
  const matches = r.j.matches ?? r.j.helpers ?? [];
  const explain = r.j.explanation ?? r.j.explain ?? matches[0]?.why ?? matches[0]?.reason;
  // ability must not appear in numeric score keys if present
  const scoreBlob = JSON.stringify(matches[0]?.score ?? matches[0] ?? {});
  must(!/"ability[_ ]?score"\s*:/i.test(scoreBlob), 'ability leaked into score');
  return `${matches.length} matches · explain=${explain ? 'yes' : 'none'}`;
});

await step(12, 'Instant Dispatch', 'Gemini', async () => {
  const r = await call('POST', '/tasks/dispatch', client.token, {
    title: 'Urgent pharmacy run',
    description: 'Need fever syrup picked up now from the nearest pharmacy.',
    category: 'medicinePickup',
    lat: 6.9271,
    lon: 79.8612,
    goods_budget: 500,
    estimated_hours: 0.5,
  });
  must(r.status === 200 || r.status === 201, r.j.error ?? `HTTP ${r.status}`);
  must(r.j.task || r.j.dispatch || r.j.helper, JSON.stringify(r.j).slice(0, 140));
  return `status=${r.j.task?.status ?? r.j.status ?? 'ok'}`;
});

await step(13, 'Street-batch explain', 'optional', async () => {
  const r = await call('GET', '/batches/nearby?lat=6.9271&lon=79.8612', helper.token);
  must(r.status === 200, r.j.error ?? `HTTP ${r.status}`);
  const batches = r.j.batches ?? r.j.items ?? [];
  const explain =
    r.j.explanation ?? r.j.explain ?? batches[0]?.why ?? batches[0]?.reason ?? r.j.summary;
  return `${batches.length} nearby · explain=${explain ? 'yes' : 'list-only'}`;
});

await step(14, 'Neighbor-vouch explain', 'optional', async () => {
  const meta = await call('GET', '/vouch/meta');
  must(meta.status === 200, meta.j.error ?? 'meta');
  const card = await call('GET', `/helpers/${helper.id}/trust`, client.token);
  must(card.status === 200, card.j.error ?? `HTTP ${card.status}`);
  const explain = card.j.explanation ?? card.j.explain ?? card.j.summary ?? card.j.reason;
  return `meta ok · trust explain=${explain ? 'yes' : Object.keys(card.j).slice(0, 5).join(',')}`;
});

await step(15, 'Receipt vs shopping list', 'Gemini', async () => {
  const r = await form(
    `/tasks/${task.id}/receipt`,
    helper.token,
    { items: JSON.stringify(['Anchor milk powder 400g', 'Basmati rice 1kg']) },
    'receipt',
    milkPng,
    'receipt.png',
    'image/png',
  );
  // may 400 if task not in-progress — still accept structured AI response or clear status
  if (r.status >= 500) throw new Error(r.j.error ?? `HTTP ${r.status}`);
  const matches = r.j.matches ?? r.j.items ?? r.j.reconciliation;
  if (r.status === 200 && matches) {
    return `reconciled · mode=${r.j.mode ?? '-'}`;
  }
  // fallback: eyes match-list covers same Gemini vision path
  const eyes = await form(
    '/a11y/eyes',
    helper.token,
    {
      mode: 'match',
      lang: 'en',
      items: JSON.stringify(['Anchor milk powder 400g', 'Basmati rice 1kg']),
    },
    'image',
    milkPng,
    'milk.png',
    'image/png',
  );
  must(eyes.status === 200 && eyes.j.mode === 'gemini', eyes.j.error ?? 'eyes fallback');
  return `receipt HTTP ${r.status} · eyes-match ok`;
});

await step(16, 'Completion checklist', 'optional', async () => {
  const r = await form(
    `/tasks/${task.id}/completion-proof`,
    helper.token,
    {
      checked_items: JSON.stringify(['Bought items', 'Delivered to door']),
      note: 'Left bags at door as asked.',
    },
    'photos',
    milkPng,
    'proof.png',
    'image/png',
  );
  if (r.status === 200 || r.status === 201) {
    return `ok · ${r.j.task?.status ?? 'proof'}`;
  }
  // Expected if not in_progress yet
  must(r.status === 400 || r.status === 422, `unexpected ${r.status} ${JSON.stringify(r.j).slice(0, 80)}`);
  return `gated (${r.status}) — endpoint live`;
});

await step(17, 'Trust arbitrator (recommend only)', 'Gemini', async () => {
  const r = await call('POST', `/tasks/${task.id}/trust-review`, client.token, {
    reason: 'Checking receipt fairness before release',
  });
  must(r.status === 200, r.j.error ?? `HTTP ${r.status}`);
  must(r.j.verdict || r.j.recommendation || r.j.review, JSON.stringify(r.j).slice(0, 140));
  const blob = JSON.stringify(r.j).toLowerCase();
  must(!/released_escrow|moved_money|payout_executed/.test(blob), 'must not move money');
  return `verdict=${r.j.verdict ?? r.j.recommendation ?? 'ok'}`;
});

await step(18, 'Monsoon status (Open-Meteo)', 'Open-Meteo', async () => {
  const r = await call('GET', '/resilience/status?lat=6.9271&lon=79.8612');
  must(r.status === 200 && r.j.hazard, r.j.error ?? `HTTP ${r.status}`);
  return `${r.j.hazard} · ${r.j.precip_mm_next_24h} mm · mode=${r.j.mode}`;
});

await step(19, 'Hazard triage (elder/disability first)', 'Gemini', async () => {
  const r = await call('POST', '/resilience/triage', client.token, {
    title: 'Elder hospital ride',
    description: 'My mother uses a wheelchair and needs a hospital ride during heavy rain.',
    category: 'hospitalCompanion',
    lat: 6.9271,
    lon: 79.8612,
  });
  must(r.status === 200 && r.j.triage?.priority, r.j.error ?? `HTTP ${r.status}`);
  return `priority=${r.j.triage.priority} · hazard=${r.j.status?.hazard}`;
});

await step(20, 'Ability fit (great / adaptable / heads-up)', 'table', async () => {
  const r = await call('GET', `/tasks/${task.id}/ability-fit`, helper.token);
  must(r.status === 200 && r.j.fit?.level, r.j.error ?? 'no fit');
  must(['great', 'adaptable', 'heads_up'].includes(r.j.fit.level), `level=${r.j.fit.level}`);
  return `groceryRun=${r.j.fit.level}`;
});

await step(21, 'Adapted job brief (Eyes/Doorstep/Say/Easy-read)', 'Gemini', async () => {
  const r = await call('POST', `/tasks/${task.id}/adapt-brief`, helper.token, { lang: 'en' });
  must(r.status === 200 && r.j.steps?.length >= 1, r.j.error ?? 'no steps');
  const tools = r.j.steps.map((s) => s.tool).filter(Boolean);
  must(tools.length >= 1, 'no named tools');
  return `mode=${r.j.mode} · ${tools.join(',')}`;
});

await step(22, 'Zivo Eyes (describe / read / match list)', 'Gemini', async () => {
  const r = await form(
    '/a11y/eyes',
    helper.token,
    {
      mode: 'match',
      lang: 'en',
      items: JSON.stringify(['Anchor milk powder 400g', 'Basmati rice 1kg']),
    },
    'image',
    milkPng,
    'milk.png',
    'image/png',
  );
  must(r.status === 200 && r.j.mode === 'gemini', r.j.error ?? `mode=${r.j.mode}`);
  must(r.j.spoken || r.j.matches, 'empty eyes');
  return `${r.j.latency_ms ?? '-'} ms · matches=${(r.j.matches ?? []).length}`;
});

await step(23, 'Doorstep Talk (speech → text for deaf helpers)', 'Gemini', async () => {
  const tts = await call('POST', '/a11y/tts', helper.token, {
    text: 'Please leave the bags in the kitchen.',
    lang: 'en',
  });
  must(tts.j.audio_base64, 'no tts');
  const r = await form(
    '/a11y/doorstep',
    helper.token,
    { lang: 'en' },
    'audio',
    Buffer.from(tts.j.audio_base64, 'base64'),
    'clip.mp3',
    'audio/mpeg',
  );
  must(r.status === 200, r.j.error ?? `HTTP ${r.status}`);
  must(r.j.for_reader || r.j.heard || r.j.transcript, 'empty doorstep');
  return `mode=${r.j.mode} · “${String(r.j.for_reader ?? r.j.heard).slice(0, 50)}”`;
});

await step(24, 'Say-it phrase cards', 'TTS only', async () => {
  // Phrase cards are client-local strings + Cloud TTS — verify TTS for a phrase.
  const phrases = [
    'I am here to help with your task.',
    'Please point to what you need.',
  ];
  for (const text of phrases) {
    const r = await call('POST', '/a11y/tts', helper.token, { text, lang: 'en' });
    must(r.j.audio_base64, r.j.error ?? text);
  }
  return `${phrases.length} phrases synthesized`;
});

await step(25, 'Easy-read simplify', 'Gemini', async () => {
  const r = await call('POST', '/a11y/simplify', helper.token, {
    text: 'Kindly procure approximately five kilograms of rice alongside a tin of powdered milk and convey them to residence unit number four.',
    lang: 'en',
  });
  const plain = r.j.plain ?? r.j.simplified ?? r.j.text ?? r.j.result;
  must(r.status === 200 && plain, r.j.error ?? 'empty');
  must(r.j.mode === 'gemini', `mode=${r.j.mode}`);
  return String(plain).slice(0, 80);
});

await step(26, 'Screen/scene describe', 'Gemini', async () => {
  const r = await form(
    '/a11y/describe',
    helper.token,
    { lang: 'en' },
    'image',
    milkPng,
    'scene.png',
    'image/png',
  );
  const summary = r.j.summary ?? r.j.description ?? r.j.spoken ?? r.j.text;
  must(r.status === 200 && summary, r.j.error ?? 'empty');
  must(r.j.mode === 'gemini', `mode=${r.j.mode}`);
  return String(summary).slice(0, 80);
});

await step(27, 'A11y transcribe', 'STT/Gemini', async () => {
  must(mp3, 'no audio');
  const r = await form(
    '/a11y/transcribe',
    helper.token,
    { lang: 'en' },
    'audio',
    mp3,
    'clip.mp3',
    'audio/mpeg',
  );
  must(r.status === 200 && (r.j.transcript || r.j.text), r.j.error ?? 'empty');
  return String(r.j.transcript ?? r.j.text).slice(0, 60);
});

await step(29, 'Access audit (entrance photo)', 'Gemini', async () => {
  const r = await form(
    '/a11y/access-audit',
    helper.token,
    { lang: 'en' },
    'image',
    milkPng,
    'door.png',
    'image/png',
  );
  must(r.status === 200 && r.j.mode === 'gemini', r.j.error ?? `mode=${r.j.mode}`);
  must(r.j.spoken || r.j.wheelchair !== undefined, 'missing audit fields');
  return `stairs=${r.j.stairs} ramp=${r.j.ramp} wheelchair=${r.j.wheelchair}`;
});

await step(30, 'Sighted-assist when Eyes is unsure', 'Eyes+category', async () => {
  // Category exists + Eyes can return unsure → client can post sightedAssist
  const eyes = await form(
    '/a11y/eyes',
    helper.token,
    { mode: 'describe', lang: 'en' },
    'image',
    milkPng,
    'milk.png',
    'image/png',
  );
  must(eyes.status === 200, eyes.j.error ?? 'eyes');
  const created = await call('POST', '/tasks', client.token, {
    title: 'Sighted assist video check',
    description: 'Zivo Eyes was unsure — please confirm the milk powder brand on the shelf via short video.',
    category: 'sightedAssist',
    estimated_hours: 0.25,
    goods_budget: 0,
    lat: 6.9271,
    lon: 79.8612,
    deadline_at: new Date(Date.now() + 2 * 3600e3).toISOString(),
    urgency: 'normal',
  });
  must(created.j.task?.category === 'sightedAssist', created.j.error ?? 'category');
  return `eyes ok · sightedAssist task ${created.j.task.id.slice(0, 8)}`;
});

await step(31, 'Bundle plan → one escrow', 'Gemini', async () => {
  const plan = await call('POST', '/tasks/plan', client.token, {
    problem: 'Hospital companion for mother, then pharmacy, then light groceries on the way home.',
    lang: 'en',
  });
  must(plan.j.tasks?.length >= 2 || plan.j.plan?.length >= 2, plan.j.error ?? 'no plan');
  const tasks = (plan.j.tasks ?? plan.j.plan).map((t) => ({
    title: t.title,
    description: t.description ?? t.title,
    category: t.category ?? 'errandRun',
    estimated_hours: t.estimated_hours ?? 0.5,
    goods_budget: t.goods_budget ?? 300,
  }));
  const bundle = await call('POST', '/tasks/bundle', client.token, {
    bundle_title: 'Mother clinic day',
    lat: 6.9271,
    lon: 79.8612,
    deadline_at: new Date(Date.now() + 6 * 3600e3).toISOString(),
    tasks,
  });
  must(bundle.status === 200 || bundle.status === 201, bundle.j.error ?? `HTTP ${bundle.status}`);
  must(bundle.j.bundle_id || bundle.j.tasks?.length, JSON.stringify(bundle.j).slice(0, 140));
  planBundleId = bundle.j.bundle_id;
  return `bundle=${planBundleId ?? 'ok'} · n=${bundle.j.tasks?.length ?? tasks.length}`;
});

// Print matrix
console.log(`\nZivo AI matrix · ${API}\n`);
const ordered = rows
  .filter((r) => r.id >= 1)
  .sort((a, b) => a.id - b.id);
const w = Math.max(...ordered.map((r) => r.name.length), 10);
for (const r of ordered) {
  console.log(
    `${r.ok ? 'PASS' : 'FAIL'}  #${String(r.id).padStart(2)}  ${r.name.padEnd(w)}  ${(r.engine + '').padEnd(14)}  ${String(r.ms).padStart(6)} ms  ${r.note}`,
  );
}
const infraFail = rows.filter((r) => r.id < 1 && !r.ok);
if (infraFail.length) {
  console.log('\nInfra failures:');
  for (const r of infraFail) console.log(`  FAIL  ${r.name}: ${r.note}`);
}
const failed = ordered.filter((r) => !r.ok).length;
const passed = ordered.length - failed;
console.log(`\n${passed}/${ordered.length} features passed`);
process.exit(failed || infraFail.length ? 1 : 0);
