# Community impact layer (Pub/Sub → BigQuery → Looker)

Zivo streams neighbourhood-care events to Pub/Sub topic `zivo-events` and mirrors them in Firestore `impact_events` for free-tier demos.

Live demo endpoint: `GET /impact/summary`

## Create topic (once)

```bash
export GCP_PROJECT_ID=gcp-ai-builder
gcloud pubsub topics create zivo-events --project="$GCP_PROJECT_ID" || true
```

## BigQuery dataset, raw table, subscription, views

A BigQuery subscription cannot map a nested JSON `payload` onto typed columns (the first attempt with `--use-table-schema` failed with `invalid_argument`),
so Pub/Sub writes each message **as-is** to `events_raw` (`data JSON` + metadata) and the typed `events` is a **view**. This is what is deployed:

```bash
bq --location=asia-south1 mk -d --description "Zivo neighbourhood impact" zivo_impact
bq mk --table zivo_impact.events_raw \
  subscription_name:STRING,message_id:STRING,publish_time:TIMESTAMP,data:JSON,attributes:JSON
# let the Pub/Sub service agent write (project number 355844955972)
bq query --use_legacy_sql=false \
  "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA \`gcp-ai-builder.zivo_impact\` TO 'serviceAccount:service-355844955972@gcp-sa-pubsub.iam.gserviceaccount.com'"
gcloud pubsub subscriptions create zivo-events-bq --topic=zivo-events \
  --bigquery-table="${GCP_PROJECT_ID}:zivo_impact.events_raw" --write-metadata --project="$GCP_PROJECT_ID"
bq --location=asia-south1 query --use_legacy_sql=false < docs/sql/impact_views.sql   # events, map_points, impact_daily
```

Note `at` is a reserved word in BigQuery SQL and must be back-ticked. Events emitted before the subscription existed were loaded once with `gcp/api/eval/backfill_bq.ts`.
The Cloud Run service account also needs `roles/pubsub.publisher` on the topic.

## Looker Studio — community needs map

Data layer is built (`map_points`, `impact_daily`); the Looker report is a browser step under your own Google account — see
[ARCHITECTURE.md → Looker Studio](ARCHITECTURE.md#looker-studio-community-needs-map--honest-status) for the 5 steps. Use the `simulated` filter so real and simulated rows are never blended.

## BigQuery ML — demand forecast (recipe only, **not run**)

```sql
CREATE OR REPLACE MODEL `zivo_impact.demand_forecast`
OPTIONS(
  model_type='ARIMA_PLUS',
  time_series_timestamp_col='hour',
  time_series_data_col='tasks'
) AS
SELECT
  TIMESTAMP_TRUNC(TIMESTAMP(at), HOUR) AS hour,
  COUNTIF(type = 'batch_join' OR type = 'xlang_chat') AS tasks
FROM `zivo_impact.events`
GROUP BY hour;  -- needs weeks of real data to be meaningful
```

## Stated impact assumptions (shown in API)

| Metric | Assumption |
|--------|------------|
| Trips saved | 1 street-batch join ≈ 1 avoided solo helper trip |
| Distance | ≈ 2.5 km per avoided Colombo neighbourhood hop |
| CO₂e | ≈ 0.12 kg / km (small petrol motorcycle) |
| Wage floor | Count of fair-price quotes **issued** (not only attempted undercuts) |

These assumptions are returned in `GET /impact/summary` → `assumptions[]` so judges can audit the numbers.
