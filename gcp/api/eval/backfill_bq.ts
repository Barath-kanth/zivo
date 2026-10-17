/**
 * One-off: republish existing Firestore impact_events to Pub/Sub so the new
 * BigQuery sink has history (Pub/Sub publishing from Cloud Run was failing with
 * PERMISSION_DENIED until the runtime service account got roles/pubsub.publisher).
 *   GCP_PROJECT_ID=gcp-ai-builder npx tsx eval/backfill_bq.ts
 * Run it ONCE — BigQuery has no de-dup on `id`.
 */
import { PubSub } from '@google-cloud/pubsub';
import { listImpactEvents } from '../src/events.js';

const topic = new PubSub({ projectId: 'gcp-ai-builder' }).topic('zivo-events');
const events = (await listImpactEvents(2000)).reverse();
let n = 0;
for (const e of events) {
  await topic.publishMessage({ json: e, attributes: { type: e.type, task_id: e.task_id ?? '', backfill: '1' } });
  n++;
}
console.log(`republished ${n} events`);
