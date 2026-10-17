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

# GCP Maps Platform browser key (create in Console as "Zivo Maps Web").
# Required: export GOOGLE_MAPS_API_KEY=...
MAPS_KEY="${GOOGLE_MAPS_API_KEY:-}"
if [[ -z "$MAPS_KEY" ]]; then
  echo "WARNING: GOOGLE_MAPS_API_KEY unset — map tiles will fail until you set it." >&2
  MAPS_KEY="MISSING_GOOGLE_MAPS_API_KEY"
fi

echo "==> Flutter build web → $API_URL"
cd "$ROOT"

# Inject Maps key into the Flutter web template before build (restored after).
INDEX_HTML="$ROOT/web/index.html"
INDEX_BAK="$ROOT/web/index.html.maps.bak"
cp "$INDEX_HTML" "$INDEX_BAK"
# macOS/BSD sed needs '' after -i; GNU sed does not — use a portable rewrite.
python3 - <<PY
from pathlib import Path
p = Path("$INDEX_HTML")
text = p.read_text()
text = text.replace("__GOOGLE_MAPS_API_KEY__", """$MAPS_KEY""")
p.write_text(text)
PY

cleanup_index() {
  if [[ -f "$INDEX_BAK" ]]; then
    mv "$INDEX_BAK" "$INDEX_HTML"
  fi
}
trap cleanup_index EXIT

flutter pub get
flutter build web --release \
  --dart-define=GCP_API_BASE_URL="$API_URL" \
  --dart-define=FORCE_FREE_OTP=true \
  --dart-define=ENABLE_DEMO_MODE=false \
  --dart-define=GOOGLE_MAPS_API_KEY="$MAPS_KEY"

cleanup_index
trap - EXIT

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
