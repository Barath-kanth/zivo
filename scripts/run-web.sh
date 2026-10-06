#!/usr/bin/env bash
# Run Flutter web against the live zero-cost Cloud Run API.
set -euo pipefail
API_URL="${GCP_API_BASE_URL:-https://zivo-api-ihp5vjzpsa-el.a.run.app}"
cd "$(dirname "$0")/.."
flutter pub get
flutter run -d chrome --web-port=7357 \
  --dart-define=GCP_API_BASE_URL="$API_URL" \
  --dart-define=FORCE_FREE_OTP=true \
  --dart-define=ENABLE_DEMO_MODE=false
