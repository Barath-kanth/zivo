/**
 * Cup impact layer — Pub/Sub (when configured) + Firestore event log.
 * BigQuery sinks can subscribe to the same topic; /impact/summary reads Firestore.
 */
import { AsyncLocalStorage } from 'node:async_hooks';
import { PubSub } from '@google-cloud/pubsub';
import { Firestore } from '@google-cloud/firestore';
import { gcpProjectId } from './config.js';

export type ImpactEvent = {
  id: string;
  type: string;
  at: string;
  user_id?: string;
  task_id?: string;
  payload: Record<string, unknown>;
};

/**
 * Requests sent with `x-zivo-simulated: 1` (the labelled simulated pilot) tag every
 * event they cause with payload.simulated = true, so real and simulated data never mix.
 */
export const simulationContext = new AsyncLocalStorage<{ simulated: boolean }>();

const TOPIC =
  process.env.ZIVO_EVENTS_TOPIC?.trim() || 'zivo-events';

const useMemory =
  (process.env.USE_MEMORY_STORE ?? 'false').toLowerCase() === 'true' ||
  !gcpProjectId ||
  gcpProjectId === 'your-gcp-project-id';

const memEvents: ImpactEvent[] = [];
let db: Firestore | null = null;
let pubsub: PubSub | null = null;
let topicReady: Promise<void> | null = null;

function firestore(): Firestore {
  if (!db) {
    db = new Firestore({
      projectId: gcpProjectId,
      ignoreUndefinedProperties: true,
    });
  }
  return db;
}

function getPubSub(): PubSub | null {
  if (useMemory) return null;
  if (!pubsub) {
    try {
      pubsub = new PubSub({ projectId: gcpProjectId });
    } catch (err) {
      console.warn('[events] Pub/Sub init failed', err);
      return null;
    }
  }
  return pubsub;
}

async function ensureTopic(): Promise<void> {
  const client = getPubSub();
  if (!client) return;
  if (!topicReady) {
    topicReady = (async () => {
      try {
        const [topics] = await client.getTopics();
        const exists = topics.some((t) => t.name.endsWith(`/topics/${TOPIC}`));
        if (!exists) {
          await client.createTopic(TOPIC);
          console.log(`[events] created topic ${TOPIC}`);
        }
      } catch (err) {
        // Topic may already exist or lack IAM — publish will still try.
        console.warn('[events] ensureTopic', err);
      }
    })();
  }
  await topicReady;
}

export async function publishImpactEvent(input: {
  type: string;
  userId?: string;
  taskId?: string;
  payload?: Record<string, unknown>;
}): Promise<ImpactEvent> {
  const event: ImpactEvent = {
    id: `evt_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    type: input.type,
    at: new Date().toISOString(),
    user_id: input.userId,
    task_id: input.taskId,
    payload: {
      ...(input.payload ?? {}),
      ...(simulationContext.getStore()?.simulated ? { simulated: true } : {}),
    },
  };

  if (useMemory) {
    memEvents.push(event);
    if (memEvents.length > 2000) memEvents.shift();
    return event;
  }

  try {
    await firestore().collection('impact_events').doc(event.id).set(event);
  } catch (err) {
    console.warn('[events] firestore write failed', err);
  }

  try {
    await ensureTopic();
    const client = getPubSub();
    if (client) {
      await client.topic(TOPIC).publishMessage({
        json: event,
        attributes: {
          type: event.type,
          task_id: event.task_id ?? '',
        },
      });
    }
  } catch (err) {
    console.warn('[events] pubsub publish failed (Firestore log still kept)', err);
  }

  return event;
}

export async function listImpactEvents(limit = 500): Promise<ImpactEvent[]> {
  if (useMemory) return [...memEvents].slice(-limit);

  const snap = await firestore()
    .collection('impact_events')
    .orderBy('at', 'desc')
    .limit(limit)
    .get();
  return snap.docs.map((d) => d.data() as ImpactEvent);
}

/** Demo-friendly aggregates for Looker / in-app impact card. */
export async function summarizeImpact(
  source: 'all' | 'real' | 'simulated' = 'all',
): Promise<{
  source: 'all' | 'real' | 'simulated';
  simulated_events: number;
  events: number;
  safety_blocks: number;
  xlang_messages: number;
  batches_joined: number;
  trips_saved_estimate: number;
  co2e_kg_estimate: number;
  wage_floor_protections: number;
  resilience_alerts: number;
  assumptions: string[];
  bigquery_dataset: string;
  pubsub_topic: string;
}> {
  const all = await listImpactEvents(800);
  const isSim = (e: ImpactEvent) => e.payload?.simulated === true;
  const simulated_events = all.filter(isSim).length;
  const events =
    source === 'real' ? all.filter((e) => !isSim(e))
    : source === 'simulated' ? all.filter(isSim)
    : all;
  const safety_blocks = events.filter((e) => e.type === 'safety_block').length;
  const xlang_messages = events.filter((e) => e.type === 'xlang_chat').length;
  const batches_joined = events.filter((e) => e.type === 'batch_join').length;
  const wage_floor_protections = events.filter(
    (e) => e.type === 'wage_floor_protect',
  ).length;
  const resilience_alerts = events.filter(
    (e) => e.type === 'resilience_alert',
  ).length;

  // Street batching: each join avoids ~1 extra helper trip (~2.5 km avg urban hop).
  const trips_saved_estimate = batches_joined;
  const kmSaved = trips_saved_estimate * 2.5;
  // ~0.12 kg CO₂e / km for a small petrol motorcycle (stated assumption).
  const co2e_kg_estimate = Number((kmSaved * 0.12).toFixed(2));

  return {
    source,
    simulated_events,
    events: events.length,
    safety_blocks,
    xlang_messages,
    batches_joined,
    trips_saved_estimate,
    co2e_kg_estimate,
    wage_floor_protections,
    resilience_alerts,
    assumptions: [
      'Each street-batch join ≈ 1 avoided solo helper trip',
      'Average avoided trip distance ≈ 2.5 km (Colombo neighbourhood hop)',
      'Emission factor ≈ 0.12 kg CO₂e / km (small petrol motorcycle)',
      'Wage-floor events count Gemini quotes that rejected undercuts',
      'Events stream to Pub/Sub topic zivo-events; mirrored in Firestore impact_events for free-tier demos',
    ],
    bigquery_dataset:
      process.env.ZIVO_BQ_DATASET?.trim() || 'zivo_impact',
    pubsub_topic: TOPIC,
  };
}
