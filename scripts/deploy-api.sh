#!/usr/bin/env bash
# Deploy gcp/api to Cloud Run (min instances = 0). Keep USE_MOCK_AI=true.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATH="$HOME/google-cloud-sdk/bin:/opt/homebrew/bin:$PATH"

PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
REGION="${GCP_REGION:-asia-south1}"
SERVICE="${CLOUD_RUN_SERVICE:-zivo-api}"
BUCKET="${GCS_BUCKET:-${PROJECT_ID}-zivo-uploads}"

gcloud config set project "$PROJECT_ID"

echo "==> Deploy $SERVICE from source (Cloud Build)"
gcloud run deploy "$SERVICE" \
  --quiet \
  --source="$ROOT/gcp/api" \
  --region="$REGION" \
  --platform=managed \
  --allow-unauthenticated \
  --port=8080 \
  --memory=512Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=3 \
  --set-env-vars="USE_MOCK_AI=true,USE_MEMORY_STORE=false,GCP_PROJECT_ID=${PROJECT_ID},GCP_LOCATION=${REGION},GCS_BUCKET=${BUCKET},NODE_ENV=production,EXPOSE_OTP=true" \
  --project="$PROJECT_ID"

URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)')"
echo ""
echo "Cloud Run URL: $URL"
echo "Health:        $URL/health"
echo "Flutter:       --dart-define=GCP_API_BASE_URL=$URL"
