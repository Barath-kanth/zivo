# Zero-cost run (Free Trial / Always Free)

## What stays free / credit-safe

| Service | Setting | Cost note |
|---------|---------|-----------|
| **Firestore Native** | Free tier on | No Cloud SQL |
| **Cloud Run** `zivo-api` | `min-instances=0` | Pay only when handling requests |
| **GCS** uploads bucket | Idle OK | Near-zero without uploads |
| **Vertex / Gemini** | `USE_MOCK_AI=true` | **$0 AI** until you enable Vertex |
| **SMS** | OTP returned in API (`EXPOSE_OTP=true`) | No TextBee / Twilio |

Do **not** create Cloud SQL. Do **not** click paid upgrades you don’t need. Set a **$50 budget alert** if you upgraded billing.

## Live endpoints

| | URL |
|--|-----|
| **Web UI (Cloud Run)** | https://zivo-web-ihp5vjzpsa-el.a.run.app |
| **API (Cloud Run)** | https://zivo-api-ihp5vjzpsa-el.a.run.app |
| API health | https://zivo-api-ihp5vjzpsa-el.a.run.app/health → `"db":"firestore","mockAi":true` |

Redeploy UI after code changes:

```bash
export GCP_PROJECT_ID=gcp-ai-builder
./scripts/deploy-web.sh
```

## Run Flutter against production DB (local Chrome only)

```bash
chmod +x scripts/run-web.sh
./scripts/run-web.sh
```

## Data model (Firestore)

Collections: `users`, `tasks`, `sessions`, `otps`, `ledger`, `meta`  
Client SDK access denied via `firestore.rules` (Admin SDK from Cloud Run only).
