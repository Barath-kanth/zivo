#!/usr/bin/env bash
# Build Flutter web + deploy to Cloud Run (public URL).
# API stays on zivo-api; this deploys the UI as zivo-web.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATH="$HOME/google-cloud-sdk/bin:/opt/homebrew/bin:$PATH"

PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
REGION="${GCP_REGION:-asia-south1}"
SERVICE="${CLOUD_RUN_WEB_SERVICE:-zivo-web}"
API_URL="${GCP_API_BASE_URL:-https://zivo-api-ihp5vjzpsa-el.a.run.app}"
API_URL="${API_URL%/}"

gcloud config set project "$PROJECT_ID"

echo "==> Flutter build web → $API_URL"
cd "$ROOT"
flutter pub get
flutter build web --release \
  --dart-define=GCP_API_BASE_URL="$API_URL" \
  --dart-define=FORCE_FREE_OTP=true \
  --dart-define=ENABLE_DEMO_MODE=false

# Stage into web-host context
rm -rf "$ROOT/web-host/build"
mkdir -p "$ROOT/web-host/build"
cp -R "$ROOT/build/web" "$ROOT/web-host/build/web"

echo "==> Deploy Cloud Run $SERVICE"
gcloud run deploy "$SERVICE" \
  --quiet \
  --source="$ROOT/web-host" \
  --region="$REGION" \
  --platform=managed \
  --allow-unauthenticated \
  --port=8080 \
  --memory=256Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=3 \
  --project="$PROJECT_ID"

URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)')"
echo ""
echo "Web UI (Cloud Run): $URL"
echo "API:                $API_URL"
echo "Open the Web UI URL in a browser — fully cloud-hosted."
