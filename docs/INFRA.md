# Free-trial infra (Zivo repo)

Use **this repo** (`survey/Zivo` → https://github.com/Barath-kanth/zivo), not `zivo-cup`.

## Stack (Cup demo)

| Create | Notes |
|--------|------|
| Firestore | Users, tasks, chat, `impact_events` mirror |
| Cloud Storage | Receipt / proof uploads |
| Cloud Run (`zivo-api`, `zivo-web`, min=0) | API + Flutter web |
| Vertex AI Gemini | Safety, xlang, concierge, triage |
| Pub/Sub `zivo-events` | Impact stream (see [IMPACT_BIGQUERY.md](IMPACT_BIGQUERY.md)) |
| Speech-to-Text / Text-to-Speech | STT: ta-IN + si-LK · TTS: ta-IN + en-IN (si bridged) |
| BigQuery `zivo_impact` | Optional Looker Studio sink |

**Skip on free trial:** Cloud SQL, Earth Engine (use Open-Meteo for flood precip instead).

Project: `gcp-ai-builder` · Region: `asia-south1`

```bash
export PATH="$HOME/google-cloud-sdk/bin:$PATH"
export GCP_PROJECT_ID=gcp-ai-builder
export GCP_REGION=asia-south1
cd /Users/barath-r/survey/Zivo
./scripts/bootstrap-infra.sh
gcloud pubsub topics create zivo-events --project="$GCP_PROJECT_ID" || true
./scripts/deploy-api.sh
./scripts/deploy-web.sh
```
