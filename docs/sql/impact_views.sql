-- Views used by the Looker Studio report. Run:
--   bq --project_id=gcp-ai-builder --location=asia-south1 query --use_legacy_sql=false < docs/sql/impact_views.sql
--
-- Pub/Sub's BigQuery subscription writes raw messages to zivo_impact.events_raw
-- (columns: subscription_name, message_id, publish_time, data JSON, attributes JSON).
-- A nested JSON object cannot be mapped onto typed columns by the subscription
-- (that failed with invalid_argument), so the typed `events` table is a VIEW over it.

CREATE OR REPLACE VIEW `gcp-ai-builder.zivo_impact.events` AS
SELECT
  JSON_VALUE(data, '$.id') AS id,
  JSON_VALUE(data, '$.type') AS type,
  COALESCE(SAFE.TIMESTAMP(JSON_VALUE(data, '$.at')), publish_time) AS `at`,
  JSON_VALUE(data, '$.user_id') AS user_id,
  JSON_VALUE(data, '$.task_id') AS task_id,
  JSON_QUERY(data, '$.payload') AS payload
FROM `gcp-ai-builder.zivo_impact.events_raw`;

-- 1) Map layer: every event that carries a ~1 km grid coordinate.
CREATE OR REPLACE VIEW `gcp-ai-builder.zivo_impact.map_points` AS
SELECT
  `at`,
  type,
  SAFE_CAST(JSON_VALUE(payload, '$.lat') AS FLOAT64) AS lat,
  SAFE_CAST(JSON_VALUE(payload, '$.lon') AS FLOAT64) AS lon,
  ST_GEOGPOINT(
    SAFE_CAST(JSON_VALUE(payload, '$.lon') AS FLOAT64),
    SAFE_CAST(JSON_VALUE(payload, '$.lat') AS FLOAT64)
  ) AS geo,
  CONCAT(JSON_VALUE(payload, '$.lat'), ',', JSON_VALUE(payload, '$.lon')) AS lat_lon,
  JSON_VALUE(payload, '$.hazard') AS hazard,
  SAFE_CAST(JSON_VALUE(payload, '$.precip_mm_next_24h') AS FLOAT64) AS precip_mm_24h,
  JSON_VALUE(payload, '$.category') AS category,
  JSON_VALUE(payload, '$.simulated') = 'true' AS simulated
FROM `gcp-ai-builder.zivo_impact.events`
WHERE JSON_VALUE(payload, '$.lat') IS NOT NULL;

-- 2) Daily impact roll-up (same assumptions as GET /impact/summary).
CREATE OR REPLACE VIEW `gcp-ai-builder.zivo_impact.impact_daily` AS
SELECT
  DATE(`at`, 'Asia/Colombo') AS day,
  COUNTIF(type = 'batch_join') AS batch_joins,
  COUNTIF(type = 'batch_join') AS trips_saved_est,          -- 1 join ≈ 1 avoided solo trip
  ROUND(COUNTIF(type = 'batch_join') * 2.5 * 0.12, 2) AS co2e_kg_est, -- 2.5 km × 0.12 kg/km
  COUNTIF(type = 'safety_block') AS safety_blocks,
  COUNTIF(type = 'xlang_chat') AS xlang_messages,
  COUNTIF(type = 'resilience_alert') AS resilience_alerts,
  COUNTIF(type = 'wage_floor_protect') AS wage_floor_protections,
  COUNTIF(JSON_VALUE(payload, '$.simulated') = 'true') AS simulated_events
FROM `gcp-ai-builder.zivo_impact.events`
GROUP BY day;

-- 3) Fairness monitor for ability-aware hiring (no user/task ids are ever stored on these events).
--    decline_rate_disclosed vs decline_rate_other: if disclosed helpers are declined much more often,
--    the "client can choose someone else" consent step is acting as discrimination and must be redesigned.
CREATE OR REPLACE VIEW `gcp-ai-builder.zivo_impact.access_fairness` AS
SELECT
  DATE(`at`) AS day,
  COUNTIF(type = 'access_match') AS disclosed_matches,
  COUNTIF(type = 'access_decline') AS disclosed_declines,
  COUNTIF(type = 'other_decline') AS other_declines,
  SAFE_DIVIDE(COUNTIF(type = 'access_decline'), COUNTIF(type = 'access_match')) AS decline_rate_disclosed
FROM `gcp-ai-builder.zivo_impact.events`
WHERE type IN ('access_match', 'access_decline', 'other_decline')
GROUP BY day;
