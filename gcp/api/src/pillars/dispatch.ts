import { useMockAi, gcpProjectId, WALK_RADIUS_KM } from '../config.js';
import { generateGeminiJson } from '../gemini.js';
import {
  acceptTask,
  createTask,
  getUser,
  listLiveHelpersNearby,
  requiresNeighborVouch,
  type LiveHelper,
  type TaskRow,
  type BatchWindow,
} from '../store.js';
import {
  quoteMicroPrice,
  resolveClientPay,
  type PriceQuote,
  type Urgency,
} from './pricing.js';
import { openStreetBatch } from './batching.js';
import { assertInsideHomeAllowed } from './vouch.js';

export type DispatchInput = {
  clientId: string;
  title: string;
  /** Mandatory — Gemini prices from the full situation. */
  description: string;
  category?: string;
  lat: number;
  lon: number;
  dest_lat?: number;
  dest_lon?: number;
  travel_km?: number;
  /** Minutes — micro default 15. */
  duration_minutes?: number;
  urgency?: Urgency;
  /** Optional tip ABOVE Gemini floor only (never undercut). */
  client_boost_lkr?: number;
  /** @deprecated Use client_boost_lkr; undercuts rejected. */
  labor_lkr?: number;
};

export type DispatchResult = {
  pillar: 'dispatch';
  mode: 'mock' | 'gemini';
  walk_radius_km: number;
  candidates: LiveHelper[];
  selected_helper_id?: string;
  selected_helper_name?: string;
  explanation: string;
  pricing?: PriceQuote;
  task?: TaskRow;
  /** Pillar 3 — neighbors can piggyback while this window is open. */
  batch?: BatchWindow;
};

type GeminiPick = {
  selected_helper_id: string;
  explanation: string;
};

async function pickWithAi(
  input: DispatchInput,
  candidates: LiveHelper[],
): Promise<{ id: string; explanation: string; mode: 'mock' | 'gemini' }> {
  if (!candidates.length) {
    return {
      id: '',
      explanation: 'No helpers Available within walk radius.',
      mode: 'mock',
    };
  }

  const nearest = candidates[0];
  if (useMockAi || !gcpProjectId || candidates.length === 1) {
    return {
      id: nearest.id,
      explanation: `Instant dispatch: selected nearest Available helper ${nearest.full_name} (${nearest.distance_km.toFixed(2)} km).`,
      mode: useMockAi ? 'mock' : 'gemini',
    };
  }

  try {
    const g = await generateGeminiJson<GeminiPick>(`You are Zivo Instant Dispatch.
Pick ONE helper for a walkable micro-task. Prefer closest; break ties with higher rating.
Client need: ${JSON.stringify(input.title)}
Description: ${JSON.stringify(input.description ?? '')}
Candidates (JSON): ${JSON.stringify(candidates)}
Return ONLY JSON: {"selected_helper_id":"...","explanation":"one sentence"}`);
    const hit = candidates.find((c) => c.id === g.selected_helper_id) ?? nearest;
    return {
      id: hit.id,
      explanation: g.explanation || `Selected ${hit.full_name}`,
      mode: 'gemini',
    };
  } catch {
    return {
      id: nearest.id,
      explanation: `AI unavailable — dispatched nearest ${nearest.full_name} (${nearest.distance_km.toFixed(2)} km).`,
      mode: 'mock',
    };
  }
}

/** Pillar 1 — Instant Dispatch: one-tap match within walk radius (AI-assisted). */
export async function instantDispatch(input: DispatchInput): Promise<DispatchResult> {
  let candidates = await listLiveHelpersNearby(
    input.lat,
    input.lon,
    WALK_RADIUS_KM,
  );
  // Pillar 4 — inside-home categories only match Neighbor-Vouched helpers.
  if (requiresNeighborVouch(input.category)) {
    const filtered: LiveHelper[] = [];
    for (const c of candidates) {
      const u = await getUser(c.id);
      if (u?.neighbor_vouched) filtered.push(c);
    }
    candidates = filtered;
  }
  const pick = await pickWithAi(input, candidates);

  const pricing = await quoteMicroPrice({
    title: input.title,
    description: input.description,
    category: input.category,
    lat: input.lat,
    lon: input.lon,
    dest_lat: input.dest_lat,
    dest_lon: input.dest_lon,
    travel_km: input.travel_km,
    duration_minutes: input.duration_minutes ?? 15,
    urgency: input.urgency ?? 'urgent',
    client_boost_lkr: input.client_boost_lkr,
  });

  // Helper protection: reject undercuts; allow boost only.
  const paid = resolveClientPay({
    geminiLabor: pricing.gemini_labor_lkr,
    clientBoostLkr: input.client_boost_lkr ?? pricing.client_boost_lkr,
    clientOfferLkr: input.labor_lkr,
  });
  pricing.labor_lkr = paid.labor_lkr;
  pricing.client_boost_lkr = paid.client_boost_lkr;

  if (!pick.id) {
    return {
      pillar: 'dispatch',
      mode: pick.mode,
      walk_radius_km: WALK_RADIUS_KM,
      candidates,
      explanation: pick.explanation,
      pricing,
    };
  }

  const minutes = pricing.duration_minutes;
  const labor = paid.labor_lkr;
  const hours = Math.max(0.25, minutes / 60);
  const hourly = Math.round(labor / hours);

  const selected = candidates.find((c) => c.id === pick.id);
  const helperProfile = await getUser(pick.id);
  if (helperProfile) {
    assertInsideHomeAllowed(input.category, helperProfile);
  }
  const task = await createTask({
    client_id: input.clientId,
    title: input.title,
    description:
      input.description +
      `\n\n[Instant Dispatch · ${minutes} min · fair floor LKR ${paid.gemini_labor_lkr}` +
      (paid.client_boost_lkr > 0 ? ` + tip LKR ${paid.client_boost_lkr}` : '') +
      ` = LKR ${labor} · travel ${pricing.travel_km} km]` +
      `\nPricing: ${pricing.explanation}`,
    category: input.category ?? 'errandRun',
    estimated_hours: hours,
    hourly_rate: hourly,
    goods_budget: 0,
    lat: input.lat,
    lon: input.lon,
    location_label: 'Instant dispatch pin',
  });

  const matched = await acceptTask(task.id, pick.id);

  let batch: BatchWindow | undefined;
  try {
    batch = await openStreetBatch({
      anchorTask: matched,
      helperId: pick.id,
      helperName: selected?.full_name ?? 'Helper',
    });
  } catch {
    /* dispatch still succeeds without batch window */
  }

  return {
    pillar: 'dispatch',
    mode: pick.mode,
    walk_radius_km: WALK_RADIUS_KM,
    candidates,
    selected_helper_id: pick.id,
    selected_helper_name: selected?.full_name,
    explanation: `${pick.explanation} Price LKR ${labor} (non-negotiable).` +
      (batch
        ? ` Street batch open ${Math.round((new Date(batch.expires_at).getTime() - Date.now()) / 1000)}s for neighbors.`
        : ''),
    pricing,
    task: matched,
    batch,
  };
}
