/**
 * SIMULATED neighbour pilot — 8 invented personas, NOT real people.
 *
 *   cd gcp/api
 *   GCP_PROJECT_ID=gcp-ai-builder npx tsx eval/simulated_pilot.ts
 *
 * What is real here:   live Cloud Run API, live Gemini, live Open-Meteo weather,
 *                      the real Pub/Sub → BigQuery pipeline.
 * What is simulated:   the people, and the batch-join / cross-language-chat / blocked-message
 *                      events (those need two logged-in accounts + escrow, so they are
 *                      emitted through the same publishImpactEvent() the routes use).
 * Every event carries payload.simulated = true (API calls via the x-zivo-simulated header),
 * so real and simulated data are separable in Firestore, BigQuery and /impact/summary?source=.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { publishImpactEvent, simulationContext } from '../src/events.js';

const API = (process.argv[2] ?? 'https://zivo-api-ihp5vjzpsa-el.a.run.app').replace(/\/$/, '');
const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'docs', 'pilot');
mkdirSync(OUT, { recursive: true });

type Lang = 'en' | 'si' | 'ta';
type Persona = {
  name: string; age: number; lang: Lang; area: string; lat: number; lon: number;
  needs: string; utterance: string; category: string; minutes: number;
};

const P: Persona[] = [
  { name: 'Kamala', age: 74, lang: 'ta', area: 'Wellawatte, Colombo', lat: 6.874, lon: 79.861, category: 'groceryRun', minutes: 25,
    needs: 'lives alone, climbing stairs is hard',
    utterance: 'எனக்கு மருந்துக்கடையிலிருந்து மருந்து வாங்கி வர உதவி வேண்டும், மாடிப்படி ஏற முடியாது.' },
  { name: 'Nimal', age: 68, lang: 'si', area: 'Peradeniya, Kandy', lat: 7.257, lon: 80.597, category: 'hospitalCompanion', minutes: 120,
    needs: 'clinic visit, poor eyesight',
    utterance: 'හෙට උදේ ඇස් රෝහලට යන්න මට සහය වෙන කෙනෙක් ඕනේ.' },
  { name: 'Fathima', age: 41, lang: 'en', area: 'Maradana, Colombo', lat: 6.929, lon: 79.866, category: 'elderCare', minutes: 180,
    needs: 'works shifts, mother at home',
    utterance: 'I need someone to sit with my mother for three hours this afternoon while I am at work.' },
  { name: 'Ruwan', age: 33, lang: 'si', area: 'Galle Fort', lat: 6.027, lon: 80.217, category: 'movingHelp', minutes: 60,
    needs: 'new flat, heavy furniture',
    utterance: 'අලුත් ගෙදරට රෙදි සෝදන යන්ත්‍රයක් උඩට ගෙනියන්න උදව්වක් ඕනේ.' },
  { name: 'Priya', age: 29, lang: 'ta', area: 'Nallur, Jaffna', lat: 9.675, lon: 80.029, category: 'tutoring', minutes: 60,
    needs: 'son needs maths help',
    utterance: 'என் மகனுக்கு கணிதம் சொல்லிக் கொடுக்க ஒரு ஆசிரியர் வேண்டும்.' },
  { name: 'Dilani', age: 52, lang: 'si', area: 'Narahenpita, Colombo', lat: 6.893, lon: 79.878, category: 'queueStanding', minutes: 90,
    needs: 'cannot stand long',
    utterance: 'හෙට උදේ රාජ්‍ය කාර්යාලයේ පෝලිමේ මා වෙනුවෙන් ඉන්න කෙනෙක් ඕනේ.' },
  { name: 'Arun', age: 36, lang: 'en', area: 'Negombo', lat: 7.209, lon: 79.838, category: 'groceryRun', minutes: 30,
    needs: 'wheelchair user',
    utterance: 'Please buy rice, dhal and milk from the shop nearby and bring it to my door, I use a wheelchair.' },
  { name: 'Seetha', age: 61, lang: 'ta', area: 'Batticaloa', lat: 7.731, lon: 81.692, category: 'hospitalCompanion', minutes: 120,
    needs: 'dialysis appointments',
    utterance: 'வாரம் இருமுறை மருத்துவமனைக்கு என்னை அழைத்துச் செல்ல ஒருவர் வேண்டும்.' },
];

const H = { 'content-type': 'application/json', 'x-zivo-simulated': '1' };
const post = async (path: string, body: unknown) => {
  const r = await fetch(`${API}${path}`, { method: 'POST', headers: H, body: JSON.stringify(body) });
  return { status: r.status, json: (await r.json()) as Record<string, any> };
};
const get = async (path: string) => {
  const r = await fetch(`${API}${path}`, { headers: { 'x-zivo-simulated': '1' } });
  return { status: r.status, json: (await r.json()) as Record<string, any> };
};

const started = new Date().toISOString();
const log: any[] = [];

// ── Real API calls on behalf of each simulated persona (sequential: stay under Vertex quota) ──
for (const p of P) {
  const c = await post('/agent/concierge', { utterance: p.utterance, lang: p.lang, lat: p.lat, lon: p.lon });
  const w = await get(`/resilience/status?lat=${p.lat}&lon=${p.lon}`);
  const q = await post('/tasks/price-quote', {
    title: p.needs, description: `${p.needs}. ${p.utterance}`, category: p.category,
    lat: p.lat, lon: p.lon, duration_minutes: Math.min(p.minutes, 180), urgency: 'soon',
  });
  log.push({
    persona: p.name, age: p.age, lang: p.lang, area: p.area, needs: p.needs,
    concierge: {
      status: c.status, mode: c.json.mode, reply_lang: c.json.reply_lang,
      reply: String(c.json.reply ?? c.json.error ?? '').slice(0, 220),
      draft_category: c.json.draft?.category, safety_allowed: c.json.safety?.allowed,
    },
    weather: { status: w.status, mode: w.json.mode, hazard: w.json.hazard, precip_mm_24h: w.json.precip_mm_next_24h },
    quote: { status: q.status, labor_lkr: q.json.labor_lkr, total_lkr: q.json.total_lkr ?? q.json.client_pays_lkr },
  });
  console.log(p.name, c.status, c.json.mode, w.json.hazard, q.json.labor_lkr);
}

// ── Simulated events that need two logged-in accounts + escrow (labelled simulated) ──
const synthetic: any[] = [];
await simulationContext.run({ simulated: true }, async () => {
  // Street-batch joins: neighbours on the same block piggyback on one helper trip.
  // Colombo pairs (Wellawatte x2, Maradana x2, Narahenpita x1) -> 5 joins.
  const joins: [Persona, string][] = [
    [P[0], 'batch_wellawatte_1'], [P[0], 'batch_wellawatte_1'],
    [P[2], 'batch_maradana_1'], [P[2], 'batch_maradana_1'],
    [P[5], 'batch_narahenpita_1'],
  ];
  for (const [p, batch] of joins) {
    const e = await publishImpactEvent({
      type: 'batch_join', userId: `sim_${p.name.toLowerCase()}`,
      payload: { batch_id: batch, trips_saved_estimate: 1, category: p.category,
        lat: Number(p.lat.toFixed(2)), lon: Number(p.lon.toFixed(2)), persona: p.name },
    });
    synthetic.push(e);
  }
  // Cross-language chat: Tamil-speaking neighbour <-> Sinhala-speaking helper etc.
  const chats: [Lang, string][] = [['ta', 'Kamala'], ['si', 'helper_ruwan_street'], ['ta', 'Seetha'],
    ['si', 'Nimal'], ['en', 'Arun'], ['ta', 'helper_jaffna'], ['si', 'Dilani'], ['en', 'Fathima']];
  for (const [src, who] of chats) {
    synthetic.push(await publishImpactEvent({
      type: 'xlang_chat', userId: `sim_${who.toLowerCase()}`,
      payload: { source_lang: src, mode: 'simulated' },
    }));
  }
  // One attempted cash-mule post (the policy we claim to catch), blocked.
  synthetic.push(await publishImpactEvent({
    type: 'safety_block', userId: 'sim_bad_actor',
    payload: { surface: 'task_create', action: 'block', lang: 'si' },
  }));
});

const ended = new Date().toISOString();
await new Promise((r) => setTimeout(r, 4000)); // let Firestore settle
const sim = (await get('/impact/summary?source=simulated')).json;
const all = (await get('/impact/summary?source=all')).json;

const result = {
  label: 'SIMULATED RUN — personas are invented; no real neighbours took part.',
  started, ended, api: API, personas: log, synthetic_event_count: synthetic.length,
  impact_summary_simulated_only: sim, impact_summary_all: all,
};
writeFileSync(join(OUT, 'pilot_results.json'), JSON.stringify(result, null, 2));
console.log('\nsimulated-only summary:', JSON.stringify(sim, null, 1));
