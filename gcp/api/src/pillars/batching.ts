import {
  BATCH_DISCOUNT,
  BATCH_RADIUS_KM,
  BATCH_WINDOW_SEC,
  CURRENCY,
  useMockAi,
  gcpProjectId,
} from '../config.js';
import { generateGeminiJson } from '../gemini.js';
import {
  acceptTask,
  appendBatchMember,
  createTask,
  ensureDemoStreetBatch,
  listOpenBatchesNearby,
  listHelperBatchRoute,
  openBatchWindow,
  patchTask,
  type BatchWindow,
  type TaskRow,
} from '../store.js';
import { quoteMicroPrice, type Urgency } from './pricing.js';

export type BatchOffer = BatchWindow & {
  distance_km: number;
  seconds_left: number;
  discount_pct: number;
  sample_labor_lkr?: number;
  demo?: boolean;
};

/** After Instant Dispatch — open a short same-street piggyback window. */
export async function openStreetBatch(input: {
  anchorTask: TaskRow;
  helperId: string;
  helperName: string;
}): Promise<BatchWindow> {
  return openBatchWindow({
    anchor_task_id: input.anchorTask.id,
    helper_id: input.helperId,
    helper_name: input.helperName,
    lat: input.anchorTask.lat,
    lon: input.anchorTask.lon,
    street_label: input.anchorTask.location_label ?? 'Your street',
    window_sec: BATCH_WINDOW_SEC,
    max_members: 4,
  });
}

/** Neighbors see open street batches within ~150 m. */
export async function listStreetBatches(
  lat: number,
  lon: number,
): Promise<{ pillar: 'batching'; radius_km: number; offers: BatchOffer[] }> {
  let nearby = await listOpenBatchesNearby(lat, lon, BATCH_RADIUS_KM);
  // Cup demo: always keep at least one joinable window near the caller.
  if (nearby.length === 0) {
    await ensureDemoStreetBatch(lat, lon);
    nearby = await listOpenBatchesNearby(lat, lon, BATCH_RADIUS_KM);
  }
  const offers: BatchOffer[] = [];
  for (const b of nearby) {
    const sample = await quoteMicroPrice({
      title: 'Street batch micro',
      description:
        'Piggyback micro-task on the same street while helper is already nearby.',
      lat: b.lat,
      lon: b.lon,
      duration_minutes: 10,
      urgency: 'soon',
    });
    const discounted = Math.round((sample.labor_lkr * (1 - BATCH_DISCOUNT)) / 10) * 10;
    offers.push({
      ...b,
      discount_pct: Math.round(BATCH_DISCOUNT * 100),
      sample_labor_lkr: discounted,
      demo: b.id.startsWith('batch_demo'),
    });
  }
  return { pillar: 'batching', radius_km: BATCH_RADIUS_KM, offers };
}

export type JoinBatchInput = {
  clientId: string;
  batchId: string;
  title: string;
  description?: string;
  category?: string;
  lat: number;
  lon: number;
  duration_minutes?: number;
  urgency?: Urgency;
};

export type JoinBatchResult = {
  pillar: 'batching';
  mode: 'formula' | 'formula+gemini';
  discount_pct: number;
  labor_lkr: number;
  solo_labor_lkr: number;
  explanation: string;
  batch: BatchWindow;
  task: TaskRow;
};

/** Neighbor piggybacks onto an on-street helper for a discounted micro-price. */
export async function joinStreetBatch(input: JoinBatchInput): Promise<JoinBatchResult> {
  const listed = await listOpenBatchesNearby(input.lat, input.lon, BATCH_RADIUS_KM);
  const offer = listed.find((b) => b.id === input.batchId);
  if (!offer) {
    throw new Error('No open street batch near you (or window expired)');
  }
  if (offer.helper_id === input.clientId) {
    throw new Error('Cannot join your own dispatch batch as client');
  }

  const minutes = Math.min(20, Math.max(5, input.duration_minutes ?? 10));
  const solo = await quoteMicroPrice({
    title: input.title,
    description:
      input.description ??
      'Street batch piggyback micro-task on the helper route.',
    category: input.category,
    lat: input.lat,
    lon: input.lon,
    duration_minutes: minutes,
    urgency: input.urgency ?? 'soon',
  });
  const labor = Math.round((solo.labor_lkr * (1 - BATCH_DISCOUNT)) / 10) * 10;
  const hours = Math.max(0.15, minutes / 60);
  const hourly = Math.round(labor / hours);

  let explanation =
    `Street batch: LKR ${labor} (${Math.round(BATCH_DISCOUNT * 100)}% off solo LKR ${solo.labor_lkr})` +
    ` · helper ${offer.helper_name} already on ${offer.street_label}` +
    ` · ${offer.seconds_left}s left to join.`;
  let mode: JoinBatchResult['mode'] = 'formula';

  if (!useMockAi && gcpProjectId && gcpProjectId !== 'your-gcp-project-id') {
    try {
      const g = await generateGeminiJson<{ explanation: string }>(
        `Explain Zivo street batching in ONE short sentence for a Sri Lanka neighbor.
Helper ${offer.helper_name} is already on the block. Piggyback price LKR ${labor} (${Math.round(BATCH_DISCOUNT * 100)}% off).
Task: ${JSON.stringify(input.title)}
Return ONLY JSON: {"explanation":"..."}`,
      );
      if (g.explanation?.trim()) {
        explanation = g.explanation.trim();
        mode = 'formula+gemini';
      }
    } catch {
      /* keep formula */
    }
  }

  const task = await createTask({
    client_id: input.clientId,
    title: input.title,
    description:
      (input.description ?? '') +
      `\n\n[Street Batch · piggyback · LKR ${labor} · ${Math.round(BATCH_DISCOUNT * 100)}% off]` +
      `\n${explanation}`,
    category: input.category ?? 'errandRun',
    estimated_hours: hours,
    hourly_rate: hourly,
    goods_budget: 0,
    lat: input.lat,
    lon: input.lon,
    location_label: offer.street_label,
  });

  const matched = await acceptTask(task.id, offer.helper_id);
  await patchTask(matched.id, {
    batch_id: offer.id,
    batch_anchor: false,
    batch_discount_pct: Math.round(BATCH_DISCOUNT * 100),
  });
  const batch = await appendBatchMember(offer.id, matched.id);
  const finalTask = await patchTask(matched.id, {
    batch_id: batch.id,
  });

  return {
    pillar: 'batching',
    mode,
    discount_pct: Math.round(BATCH_DISCOUNT * 100),
    labor_lkr: labor,
    solo_labor_lkr: solo.labor_lkr,
    explanation,
    batch,
    task: finalTask,
  };
}

export async function helperStreetRoute(helperId: string) {
  const route = await listHelperBatchRoute(helperId);
  return {
    pillar: 'batching' as const,
    ...route,
    note: 'Complete stops on the same street in sequence — earnings stack, travel stays zero.',
  };
}
