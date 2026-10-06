import {
  useMockAi,
  gcpProjectId,
  WALK_RADIUS_KM,
  CURRENCY,
  INFLATION_INDEX,
  TRAVEL_LKR_PER_KM,
  MIN_DESCRIPTION_CHARS,
} from '../config.js';
import { generateGeminiJson } from '../gemini.js';
import { haversineKm, listLiveHelpersNearby, listOpenTasks } from '../store.js';

export type Urgency = 'normal' | 'soon' | 'urgent';
export type Difficulty = 'easy' | 'moderate' | 'hard' | 'expert';
export type PhysicalEffort = 'none' | 'light' | 'medium' | 'heavy';

export type PriceQuoteInput = {
  title?: string;
  /** Required — Gemini prices from the written situation. */
  description: string;
  category?: string;
  /** Client / pickup pin. */
  lat: number;
  lon: number;
  /** Optional destination (errand end). Travel distance priced for the helper. */
  dest_lat?: number;
  dest_lon?: number;
  /** Explicit travel km override (if client knows route length). */
  travel_km?: number;
  duration_minutes?: number;
  urgency?: Urgency;
  /** Skill / cognitive difficulty (mandatory on regular task create). */
  difficulty?: Difficulty;
  /** Physical weight / lifting effort. */
  physical_effort?: PhysicalEffort;
  /** ISO deadline — complete before this instant (mandatory on regular create). */
  deadline_at?: string;
  /**
   * Dynamic answers from context-generated questionnaire
   * (word_count, room_count, travel_km, etc.).
   */
  context_fields?: Record<string, string | number | boolean | null | undefined>;
  /**
   * Optional client generosity ABOVE fair floor only.
   * Never lowers helper pay — customer cannot undercut.
   */
  client_boost_lkr?: number;
};

/** Structured facts Gemini pulls from free-text (RAG over the description). */
export type DescriptionRag = {
  duration_minutes_hint?: number;
  difficulty_hint?: Difficulty;
  physical_effort_hint?: PhysicalEffort;
  travel_km_hint?: number;
  delivery?: boolean;
  delivery_notes?: string;
  deadline_hint_iso?: string;
  urgency_hint?: Urgency;
  weight_kg_hint?: number;
  requires_vehicle?: boolean;
  indoor?: boolean;
  queue_expected?: boolean;
  skills_needed?: string[];
  extracted_summary?: string;
};

export type PriceQuote = {
  pillar: 'pricing';
  mode: 'formula' | 'formula+gemini';
  currency: string;
  /** Gemini (or formula) fair floor — helper-protected. */
  non_negotiable: true;
  client_may_undercut: false;
  client_may_boost: true;
  duration_minutes: number;
  duration_hours: number;
  /** Fair market labor Gemini/formula set (helper floor). */
  gemini_labor_lkr: number;
  /** Optional tip/boost from client (≥ 0). */
  client_boost_lkr: number;
  /** Final charge = gemini_labor + boost (never below gemini). */
  labor_lkr: number;
  floor_lkr: number;
  ceiling_lkr: number;
  travel_km: number;
  inflation_index: number;
  walk_radius_km: number;
  live_helpers: number;
  nearest_helper_km?: number;
  place_zone?: string;
  dest_zone?: string;
  task_effort?: string;
  difficulty?: Difficulty;
  physical_effort?: PhysicalEffort;
  deadline_at?: string;
  hours_until_deadline?: number;
  delivery?: boolean;
  clock_hour: number;
  explanation: string;
  policy: string;
};

function hourSurge(h: number): number {
  if (h >= 6 && h < 9) return 1.25;
  if (h >= 17 && h < 20) return 1.15;
  if (h >= 22 || h < 6) return 1.35;
  return 1.0;
}

function urgencyMult(u: Urgency): number {
  if (u === 'urgent') return 1.4;
  if (u === 'soon') return 1.15;
  return 1.0;
}

function difficultyLkr(d?: Difficulty): number {
  switch (d) {
    case 'easy':
      return 0;
    case 'moderate':
      return 80;
    case 'hard':
      return 180;
    case 'expert':
      return 320;
    default:
      return 40; // unknown → soft uplift until client declares
  }
}

function physicalLkr(p?: PhysicalEffort): number {
  switch (p) {
    case 'none':
      return 0;
    case 'light':
      return 40;
    case 'medium':
      return 120;
    case 'heavy':
      return 250;
    default:
      return 20;
  }
}

function deadlinePremiumLkr(deadlineAt?: string): {
  hours_until?: number;
  deadline_lkr: number;
} {
  if (!deadlineAt) return { deadline_lkr: 0 };
  const ms = new Date(deadlineAt).getTime() - Date.now();
  if (!Number.isFinite(ms)) return { deadline_lkr: 0 };
  const hours = ms / 3_600_000;
  if (hours < 0) return { hours_until: hours, deadline_lkr: 280 }; // already late / ASAP
  if (hours < 2) return { hours_until: hours, deadline_lkr: 200 };
  if (hours < 6) return { hours_until: hours, deadline_lkr: 120 };
  if (hours < 24) return { hours_until: hours, deadline_lkr: 60 };
  if (hours < 72) return { hours_until: hours, deadline_lkr: 25 };
  return { hours_until: hours, deadline_lkr: 0 };
}

async function extractDescriptionRag(input: {
  title?: string;
  description: string;
  category?: string;
  deadline_at?: string;
}): Promise<DescriptionRag | undefined> {
  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    // Lightweight offline extract for Cup demos without Vertex.
    const text = `${input.title ?? ''} ${input.description}`.toLowerCase();
    return {
      delivery: /deliver|delivery|drop.?off|courier|parcel|package/.test(text),
      queue_expected: /queue|line|wait/.test(text),
      requires_vehicle: /vehicle|bike|car|van|tuk/.test(text),
      weight_kg_hint: /kg|heavy|sofa|fridge/.test(text) ? 25 : undefined,
      physical_effort_hint: /heavy|sofa|fridge|stairs/.test(text)
        ? 'heavy'
        : /carry|lift|box/.test(text)
          ? 'medium'
          : undefined,
      difficulty_hint: /research|thesis|quantum|expert|complex/.test(text)
        ? 'expert'
        : /form|document|photocopy/.test(text)
          ? 'moderate'
          : undefined,
      travel_km_hint: /km|across|far|town/.test(text) ? 2 : undefined,
      extracted_summary: 'mock keyword extract',
    };
  }
  try {
    return await generateGeminiJson<DescriptionRag>(
      `You extract structured pricing facts from a Sri Lanka micro-task description (RAG over the text).
Do NOT invent a price. Pull every signal that affects labor cost.

Title: ${JSON.stringify(input.title ?? '')}
Category: ${JSON.stringify(input.category ?? '')}
Description: ${JSON.stringify(input.description)}
Client deadline ISO (if any): ${JSON.stringify(input.deadline_at ?? null)}

Return ONLY JSON with any of these keys (omit unknowns):
{
  "duration_minutes_hint": number,
  "difficulty_hint": "easy"|"moderate"|"hard"|"expert",
  "physical_effort_hint": "none"|"light"|"medium"|"heavy",
  "travel_km_hint": number,
  "delivery": boolean,
  "delivery_notes": string,
  "deadline_hint_iso": string,
  "urgency_hint": "normal"|"soon"|"urgent",
  "weight_kg_hint": number,
  "requires_vehicle": boolean,
  "indoor": boolean,
  "queue_expected": boolean,
  "skills_needed": string[],
  "extracted_summary": "one short sentence of facts used for pricing"
}`,
    );
  } catch {
    return undefined;
  }
}

function categoryEffort(cat?: string): number {
  switch (cat) {
    case 'movingHelp':
    case 'homeCleaning':
    case 'homeRepair':
      return 1.25;
    case 'babysitting':
    case 'elderCare':
    case 'hospitalCompanion':
      return 1.2;
    case 'queueStanding':
      return 1.1;
    case 'groceryRun':
    case 'errandRun':
    case 'petCare':
      return 1.0;
    case 'tutoring':
    case 'techHelp':
      return 1.15;
    default:
      return 1.05;
  }
}

function placeZone(lat: number, lon: number): { zone: string; place_lkr: number } {
  if (lat >= 6.91 && lat <= 6.935 && lon >= 79.84 && lon <= 79.855) {
    return { zone: 'Fort / Pettah', place_lkr: 80 };
  }
  if (lat >= 6.9 && lat <= 6.92 && lon >= 79.85 && lon <= 79.87) {
    return { zone: 'Slave Island / Kollupitiya', place_lkr: 70 };
  }
  if (lat >= 6.9 && lat <= 6.93 && lon >= 79.86 && lon <= 79.88) {
    return { zone: 'Bambalapitiya / Wellawatte', place_lkr: 55 };
  }
  if (lat >= 6.93 && lat <= 6.96 && lon >= 79.85 && lon <= 79.88) {
    return { zone: 'Cinnamon Gardens / Borella', place_lkr: 65 };
  }
  if (lat >= 6.84 && lat <= 6.9 && lon >= 79.86 && lon <= 79.9) {
    return { zone: 'Dehiwala / Mount Lavinia', place_lkr: 40 };
  }
  const hash =
    Math.abs(Math.round(lat * 10000) * 17 + Math.round(lon * 10000) * 31) % 50;
  return { zone: 'Neighborhood pin', place_lkr: 20 + hash };
}

type EffortSignal = { label: string; effort_lkr: number };

function taskEffortSignals(
  title?: string,
  description?: string,
  category?: string,
): EffortSignal {
  const text = `${title ?? ''} ${description ?? ''} ${category ?? ''}`.toLowerCase();
  let effort = 0;
  const tags: string[] = [];
  const bump = (n: number, tag: string) => {
    effort += n;
    tags.push(tag);
  };

  if (/queue|line|bakery|sneaker|passport|immigration/.test(text)) bump(90, 'queue');
  if (/heavy|couch|fridge|sofa|carry|lift|stairs|floor/.test(text)) bump(120, 'heavy_lift');
  if (/rain|storm|night|midnight|airport/.test(text)) bump(70, 'hard_conditions');
  if (/clean|mop|kitchen|bathroom|trash|bin/.test(text)) bump(50, 'cleaning');
  if (/plant|water|garden|pet|dog|walk/.test(text)) bump(30, 'light_favor');
  if (/package|parcel|deliver|drop.?off|pickup/.test(text)) bump(35, 'parcel');
  if (/urgent|asap|right now|immediately|emergency/.test(text)) bump(40, 'urgency_words');
  if (/hour|60 min|long wait|two hours|2 hours/.test(text)) bump(80, 'longer');
  if (/km|kilometer|across town|far|travel/.test(text)) bump(45, 'travel_words');

  if (!tags.length) {
    const len = (description ?? '').trim().length;
    effort = Math.min(80, Math.max(15, Math.round(len / 2)));
    tags.push(len >= 40 ? 'detailed_situation' : 'brief_situation');
  }

  return { label: tags.join('+'), effort_lkr: effort };
}

function clampRound(n: number, floor: number, ceiling: number): number {
  return Math.round(Math.min(ceiling, Math.max(floor, n)) / 10) * 10;
}

export function assertDescriptionForPricing(description?: string): string {
  const d = (description ?? '').trim();
  if (d.length < MIN_DESCRIPTION_CHARS) {
    throw new Error(
      `Description is mandatory (min ${MIN_DESCRIPTION_CHARS} chars) so we can price the job fairly`,
    );
  }
  return d;
}

/**
 * Resolve final labor: fair floor is sacred.
 * Client may only boost (≥ floor). Undercuts rejected.
 */
export function resolveClientPay(input: {
  geminiLabor: number;
  clientBoostLkr?: number;
  /** @deprecated Rejected if below fair floor — use boost instead. */
  clientOfferLkr?: number;
}): { labor_lkr: number; client_boost_lkr: number; gemini_labor_lkr: number } {
  const floor = input.geminiLabor;
  if (input.clientOfferLkr != null) {
    if (input.clientOfferLkr + 0.001 < floor) {
      throw new Error(
        `Client cannot undercut the fair price (LKR ${floor}). ` +
          `Helpers are protected — you may only accept or boost above it.`,
      );
    }
    return {
      gemini_labor_lkr: floor,
      client_boost_lkr: Math.round(input.clientOfferLkr - floor),
      labor_lkr: Math.round(input.clientOfferLkr / 10) * 10,
    };
  }
  const boost = Math.max(0, Math.round(input.clientBoostLkr ?? 0));
  return {
    gemini_labor_lkr: floor,
    client_boost_lkr: boost,
    labor_lkr: floor + boost,
  };
}

function numField(
  ctx: Record<string, string | number | boolean | null | undefined> | undefined,
  ...keys: string[]
): number | undefined {
  if (!ctx) return undefined;
  for (const k of keys) {
    const v = ctx[k];
    if (typeof v === 'number' && Number.isFinite(v)) return v;
    if (typeof v === 'string' && v.trim() && Number.isFinite(Number(v))) {
      return Number(v);
    }
  }
  return undefined;
}

function boolField(
  ctx: Record<string, string | number | boolean | null | undefined> | undefined,
  ...keys: string[]
): boolean | undefined {
  if (!ctx) return undefined;
  for (const k of keys) {
    const v = ctx[k];
    if (typeof v === 'boolean') return v;
    if (v === 'true' || v === 'yes') return true;
    if (v === 'false' || v === 'no') return false;
  }
  return undefined;
}

function strField(
  ctx: Record<string, string | number | boolean | null | undefined> | undefined,
  key: string,
): string | undefined {
  const v = ctx?.[key];
  if (typeof v === 'string' && v.trim()) return v.trim();
  return undefined;
}

/** Infer duration minutes from dynamic context when client didn't set hours. */
function minutesFromContext(
  ctx: Record<string, string | number | boolean | null | undefined> | undefined,
  category?: string,
): number | undefined {
  if (!ctx) return undefined;
  const wait = numField(ctx, 'expected_wait_minutes', 'wait_minutes');
  if (wait != null) return Math.min(180, Math.max(5, wait));

  const words = numField(ctx, 'word_count', 'words');
  if (words != null) return Math.min(180, Math.max(30, Math.round(words / 25))); // ~25 wpm writing aid

  const pages = numField(ctx, 'page_count', 'pages');
  if (pages != null) return Math.min(180, Math.max(30, pages * 15));

  const rooms = numField(ctx, 'room_count', 'rooms');
  const sqft = numField(ctx, 'square_feet', 'sq_ft', 'area_sqft');
  if (rooms != null || sqft != null) {
    const fromRooms = (rooms ?? 1) * 35;
    const fromSq = sqft != null ? sqft / 25 : 0;
    return Math.min(180, Math.max(30, Math.round(Math.max(fromRooms, fromSq))));
  }

  const items = numField(ctx, 'item_count');
  const stairs = numField(ctx, 'flights_of_stairs', 'stairs');
  if (items != null || stairs != null) {
    return Math.min(180, Math.max(20, (items ?? 2) * 15 + (stairs ?? 0) * 10));
  }

  if (category === 'documentWork') return 60;
  return undefined;
}

function sanitizeUserCopy(s: string): string {
  return s
    .replace(/\bgemini\b/gi, 'fair pricing')
    .replace(/\bRAG\b/g, 'details')
    .replace(/[\u0000-\u001F]+/g, ' ')
    .trim();
}

/** Configured factors + description extract + dynamic context → helper-protected price. */
export async function quoteMicroPrice(input: PriceQuoteInput): Promise<PriceQuote> {
  const description = assertDescriptionForPricing(input.description);
  const clockHour = new Date().getHours();
  const ctx = input.context_fields ?? {};

  // 1) Extract signals from free text (fills gaps).
  const rag = await extractDescriptionRag({
    title: input.title,
    description,
    category: input.category,
    deadline_at: input.deadline_at ?? strField(ctx, 'deadline_at'),
  });

  // 2) Merge: explicit inputs + dynamic questionnaire + extract.
  const inferredMinutes = minutesFromContext(ctx, input.category);
  const minutes = Math.min(
    180,
    Math.max(
      5,
      input.duration_minutes ??
        inferredMinutes ??
        rag?.duration_minutes_hint ??
        15,
    ),
  );
  const hours = minutes / 60;
  const urgency = input.urgency ?? rag?.urgency_hint ?? 'normal';

  // Map dynamic answers → effort axes (not shown to user as enums).
  let difficulty = input.difficulty ?? rag?.difficulty_hint;
  let physical = input.physical_effort ?? rag?.physical_effort_hint;
  const effortSelect = strField(ctx, 'effort_level');
  if (!difficulty && effortSelect) {
    if (/demand/i.test(effortSelect)) difficulty = 'hard';
    else if (/light/i.test(effortSelect)) difficulty = 'easy';
    else difficulty = 'moderate';
  }
  const words = numField(ctx, 'word_count', 'words');
  const pages = numField(ctx, 'page_count', 'pages', 'page');
  if (!difficulty && (words != null || pages != null)) {
    const w = words ?? (pages ?? 0) * 250;
    difficulty = w >= 3000 ? 'expert' : w >= 1500 ? 'hard' : w >= 800 ? 'moderate' : 'easy';
  }
  if (
    boolField(ctx, 'needs_plagiarism_check', 'plagiarism_check') &&
    difficulty !== 'expert'
  ) {
    difficulty = difficulty === 'easy' ? 'moderate' : difficulty === 'moderate' ? 'hard' : difficulty ?? 'hard';
  }
  const heaviest = numField(ctx, 'heaviest_kg', 'package_weight_kg', 'weight_kg');
  if (!physical && heaviest != null) {
    physical = heaviest >= 25 ? 'heavy' : heaviest >= 8 ? 'medium' : 'light';
  }
  const rooms = numField(ctx, 'room_count', 'rooms');
  if (!physical && rooms != null) {
    physical = rooms >= 4 ? 'medium' : 'light';
  }

  const deadlineAt =
    input.deadline_at ??
    strField(ctx, 'deadline_at') ??
    rag?.deadline_hint_iso;
  const delivery =
    rag?.delivery === true ||
    /deliver|delivery|drop.?off|courier|parcel/i.test(description);

  const diffLkr = difficultyLkr(difficulty);
  let physLkr = physicalLkr(physical);
  if (rag?.weight_kg_hint != null && rag.weight_kg_hint >= 15) {
    physLkr = Math.max(physLkr, physicalLkr('heavy'));
  } else if (rag?.weight_kg_hint != null && rag.weight_kg_hint >= 5) {
    physLkr = Math.max(physLkr, physicalLkr('medium'));
  }

  const live = await listLiveHelpersNearby(input.lat, input.lon, WALK_RADIUS_KM);
  const openNearby = await listOpenTasks(input.lat, input.lon);
  const openInWalk = openNearby.filter((t) => (t.distance_km ?? 99) <= WALK_RADIUS_KM);

  const place = placeZone(input.lat, input.lon);
  let destZone: string | undefined;
  let travelKm = Math.max(
    0,
    Number(input.travel_km) ||
      numField(ctx, 'travel_km', 'distance_km') ||
      0,
  );
  if (
    travelKm <= 0 &&
    input.dest_lat != null &&
    input.dest_lon != null &&
    Number.isFinite(input.dest_lat) &&
    Number.isFinite(input.dest_lon)
  ) {
    travelKm = haversineKm(
      { lat: input.lat, lng: input.lon },
      { lat: input.dest_lat, lng: input.dest_lon },
    );
    destZone = placeZone(input.dest_lat, input.dest_lon).zone;
  }
  if (travelKm <= 0 && rag?.travel_km_hint != null) {
    travelKm = Math.max(0, rag.travel_km_hint);
  }
  // Delivery without stated distance → assume short neighborhood hop.
  if (travelKm <= 0 && delivery) travelKm = 1.0;
  travelKm = Math.round(travelKm * 100) / 100;

  const deadline = deadlinePremiumLkr(deadlineAt);
  const needsVehicle =
    boolField(ctx, 'needs_vehicle', 'requires_vehicle') === true ||
    !!rag?.requires_vehicle;
  const deliveryLkr =
    (delivery ? 80 : 0) +
    (needsVehicle ? 60 : 0) +
    (rag?.queue_expected || numField(ctx, 'expected_wait_minutes') != null
      ? 50
      : 0) +
    (rag?.indoor ? 30 : 0) +
    (boolField(ctx, 'needs_plagiarism_check') ? 70 : 0) +
    (numField(ctx, 'stops_count') != null
      ? Math.max(0, (numField(ctx, 'stops_count')! - 1) * 40)
      : 0);

  const effort = taskEffortSignals(input.title, description, input.category);

  const base = 100;
  const time = minutes * 16;
  const hoursLkr = Math.round(hours * 200);
  const nearest = live[0]?.distance_km;
  const proximity = nearest == null ? 50 : Math.round(nearest * 100);
  const travel = Math.round(travelKm * TRAVEL_LKR_PER_KM);
  const scarcity =
    live.length === 0
      ? 100
      : live.length === 1
        ? 60
        : openInWalk.length >= 3
          ? 40
          : live.length >= 4
            ? -20
            : 0;
  const urgencyFlat = urgency === 'urgent' ? 60 : urgency === 'soon' ? 25 : 0;

  const surge =
    hourSurge(clockHour) * urgencyMult(urgency) * categoryEffort(input.category);
  const preInflation =
    (base +
      time +
      hoursLkr +
      proximity +
      travel +
      scarcity +
      urgencyFlat +
      effort.effort_lkr +
      diffLkr +
      physLkr +
      deadline.deadline_lkr +
      deliveryLkr +
      place.place_lkr) *
    surge;
  const inflationLkr = Math.round(preInflation * (INFLATION_INDEX - 1));
  const formulaLabor = Math.round((preInflation + inflationLkr) / 10) * 10;

  const bandFloor = clampRound(formulaLabor * 0.85, 180, 8000);
  const bandCeiling = clampRound(formulaLabor * 1.65, 220, 12000);

  let geminiLabor = formulaLabor;

  let explanation =
    `Fair price LKR ${geminiLabor} based on what this job needs` +
    (travelKm > 0 ? ` and ${travelKm} km travel` : '') +
    (deadlineAt ? ', timing, and local rates' : ' and local rates');
  let mode: PriceQuote['mode'] = rag ? 'formula+gemini' : 'formula';

  if (!useMockAi && gcpProjectId && gcpProjectId !== 'your-gcp-project-id') {
    try {
      const g = await generateGeminiJson<{
        labor_lkr: number;
        effort_label?: string;
        explanation: string;
      }>(
        `You are Zivo's fair micro-task pricing engine for Sri Lanka (LKR).
Protect the helper — clients cannot undercut your number.
Never mention model names, RAG, difficulty scores, physical-effort enums, inflation indexes, or internal factor names in the explanation.

DESCRIPTION (primary):
${JSON.stringify(description)}

FACTS EXTRACTED FROM TEXT:
${JSON.stringify(rag ?? {})}

CLIENT ANSWERS (dynamic questionnaire):
${JSON.stringify(ctx)}

Structured inputs:
- Title: ${JSON.stringify(input.title ?? '')}
- Category: ${JSON.stringify(input.category ?? 'errandRun')}
- Inferred duration: ${minutes} min
- Skill level (internal): ${difficulty ?? 'undeclared'} (+${diffLkr})
- Physical/weight (internal): ${physical ?? 'undeclared'} (+${physLkr}) weight_kg=${rag?.weight_kg_hint ?? 'n/a'}
- Deadline ISO: ${deadlineAt ?? 'none'} (deadline premium LKR ${deadline.deadline_lkr})
- Delivery: ${delivery} (+${deliveryLkr})
- Urgency: ${urgency}
- Travel km: ${travelKm}
- Live helpers: ${live.length}
- Inflation index: ${INFLATION_INDEX}
- Formula baseline: LKR ${formulaLabor}
- Band: ${bandFloor}…${bandCeiling}

Price higher for: tight deadline, delivery hops, heavy items, expert skill, night/queue, scarce helpers, inflation.
Round to 10 LKR. Never below band floor.

Return ONLY JSON:
{"labor_lkr":number,"effort_label":"short_tag","explanation":"one plain-language sentence for the client (no jargon, no scores)"}`,
      );

      const ai = Number(g.labor_lkr);
      if (Number.isFinite(ai)) {
        geminiLabor = clampRound(ai, bandFloor, bandCeiling);
        mode = 'formula+gemini';
      }
      if (g.explanation?.trim()) {
        explanation = sanitizeUserCopy(g.explanation);
      }
      if (g.effort_label?.trim()) {
        effort.label = g.effort_label.trim();
      }
    } catch {
      /* formula still protects helper */
    }
  }

  explanation = sanitizeUserCopy(explanation);

  const paid = resolveClientPay({
    geminiLabor,
    clientBoostLkr: input.client_boost_lkr,
  });

  return {
    pillar: 'pricing',
    mode,
    currency: CURRENCY,
    non_negotiable: true,
    client_may_undercut: false,
    client_may_boost: true,
    duration_minutes: minutes,
    duration_hours: Math.round(hours * 100) / 100,
    gemini_labor_lkr: paid.gemini_labor_lkr,
    client_boost_lkr: paid.client_boost_lkr,
    labor_lkr: paid.labor_lkr,
    floor_lkr: bandFloor,
    ceiling_lkr: bandCeiling,
    travel_km: travelKm,
    inflation_index: INFLATION_INDEX,
    walk_radius_km: WALK_RADIUS_KM,
    live_helpers: live.length,
    nearest_helper_km: nearest,
    place_zone: place.zone,
    dest_zone: destZone,
    task_effort: effort.label,
    deadline_at: deadlineAt,
    hours_until_deadline:
      deadline.hours_until != null
        ? Math.round(deadline.hours_until * 10) / 10
        : undefined,
    delivery,
    clock_hour: clockHour,
    explanation,
    policy:
      'Fair floor from your answers and task details. You may accept or add a tip — never undercut the helper.',
  };
}
