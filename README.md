# Zivo (GCP Cup build)

Trusted neighborhood help — Flutter UI + **Google Cloud** backend.

> Supabase / Netlify / TextBee have been removed from this tree.

## Architecture

- UI: Flutter (`lib/`)
- API: Cloud Run (`gcp/api`) — auth, escrow, Gemini pillars A/B/C
- Config: `--dart-define=GCP_API_BASE_URL=...`

See [docs/GCP_DEPLOY.md](docs/GCP_DEPLOY.md), [docs/INFRA.md](docs/INFRA.md), and [docs/ZERO_COST.md](docs/ZERO_COST.md).

**GCP project:** `gcp-ai-builder` · API uses **Firestore** · `USE_MOCK_AI=true` for $0 AI.

### Cloud-hosted (not local)

| Service | URL |
|---------|-----|
| **Web UI** | run `./scripts/deploy-web.sh` then open Cloud Run `zivo-web` URL |
| **API** | https://zivo-api-ihp5vjzpsa-el.a.run.app |

```bash
export GCP_PROJECT_ID=gcp-ai-builder
./scripts/deploy-web.sh   # Flutter → Cloud Run zivo-web
```

## Quick start

```bash
cd gcp/api && npm install && npm run dev
# other terminal
flutter run -d chrome --web-port=7357 \
  --dart-define=GCP_API_BASE_URL=http://localhost:8080
```

## Pillars (Cup differentiators)

| Pillar | Where |
|--------|--------|
| A Vernacular safety | Task create + **every chat message** → `POST /tasks/safety-check` / `POST /tasks/:id/chat` |
| B Receipt multimodal | Active job proof → `POST /tasks/:id/receipt` |
| C Constraint match | Helper accept → `POST /tasks/:id/match` |
| Trust Arbitrator | Chat + timeline + vouch → `POST /tasks/:id/trust-review` (can **hold escrow**) |

Rails (not the headline): Instant Dispatch, street batching, neighbor vouch, in-app chat evidence.
