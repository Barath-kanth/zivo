# Zivo (GCP Cup build)

Trusted neighborhood help — Flutter UI + **Google Cloud** backend.

> Supabase / Netlify / TextBee have been removed from this tree.

## Architecture

- UI: Flutter (`lib/`)
- API: Cloud Run (`gcp/api`) — auth, escrow, Gemini pillars A/B/C
- Config: `--dart-define=GCP_API_BASE_URL=...`

See [docs/GCP_DEPLOY.md](docs/GCP_DEPLOY.md).

## Quick start

```bash
cd gcp/api && npm install && npm run dev
# other terminal
flutter run -d chrome --web-port=7357 \
  --dart-define=GCP_API_BASE_URL=http://localhost:8080
```

## Pillars

| Pillar | Where |
|--------|--------|
| A Vernacular safety | Task create → `POST /tasks/safety-check` |
| B Receipt multimodal | Active job proof → `POST /tasks/:id/receipt` |
| C Constraint match | Helper accept → `POST /tasks/:id/match` |
