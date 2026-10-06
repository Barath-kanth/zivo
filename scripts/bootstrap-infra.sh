#!/usr/bin/env bash
# Free-trial-safe infra for Zivo (Firestore + GCS + Artifact Registry).
# No Cloud SQL. No Vertex until AI phase.
#
#   export GCP_PROJECT_ID=gcp-ai-builder
#   export GCP_REGION=asia-south1
#   ./scripts/bootstrap-infra.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATH="$HOME/google-cloud-sdk/bin:/opt/homebrew/bin:$PATH"
command -v gcloud >/dev/null || { echo "gcloud not found"; exit 1; }

PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
REGION="${GCP_REGION:-asia-south1}"
BUCKET="${GCS_BUCKET:-${PROJECT_ID}-zivo-uploads}"

echo "==> Project: $PROJECT_ID  region: $REGION"
gcloud config set project "$PROJECT_ID"
gcloud auth application-default set-quota-project "$PROJECT_ID" 2>/dev/null || true

echo "==> Enable APIs (Run, Firestore, Storage, Artifact Registry, Cloud Build) — no Vertex yet"
gcloud services enable \
  run.googleapis.com \
  firestore.googleapis.com \
  storage.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  iam.googleapis.com \
  --project="$PROJECT_ID"

echo "==> Firestore Native"
if gcloud firestore databases describe --database='(default)' --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "    already exists"
else
  gcloud firestore databases create \
    --location="$REGION" \
    --type=firestore-native \
    --project="$PROJECT_ID" \
  || gcloud firestore databases create \
    --location=nam5 \
    --type=firestore-native \
    --project="$PROJECT_ID"
fi

echo "==> Cloud Storage gs://$BUCKET"
if gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "    already exists"
else
  gcloud storage buckets create "gs://$BUCKET" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access
fi

echo "==> Artifact Registry zivo"
if gcloud artifacts repositories describe zivo \
  --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "    already exists"
else
  gcloud artifacts repositories create zivo \
    --repository-format=docker \
    --location="$REGION" \
    --description="Zivo Cup images" \
    --project="$PROJECT_ID"
fi

ENV_FILE="$ROOT/gcp/api/.env"
if [[ -f "$ENV_FILE" ]]; then
  perl -i -pe "s/^GCP_PROJECT_ID=.*/GCP_PROJECT_ID=$PROJECT_ID/" "$ENV_FILE"
  perl -i -pe "s/^GCP_LOCATION=.*/GCP_LOCATION=$REGION/" "$ENV_FILE"
  perl -i -pe 's/^USE_MOCK_AI=.*/USE_MOCK_AI=true/' "$ENV_FILE"
  grep -q '^GCS_BUCKET=' "$ENV_FILE" && perl -i -pe "s/^GCS_BUCKET=.*/GCS_BUCKET=$BUCKET/" "$ENV_FILE" \
    || echo "GCS_BUCKET=$BUCKET" >> "$ENV_FILE"
fi

# Firebase project id hint (same GCP project is typical)
if [[ -f "$ROOT/.firebaserc" ]]; then
  perl -i -pe "s/YOUR_FIREBASE_PROJECT_ID/$PROJECT_ID/" "$ROOT/.firebaserc"
fi

cat <<EOF

Infra ready (Free Trial path — no Cloud SQL, no Vertex).
  Project:   $PROJECT_ID
  Firestore: (default)
  Bucket:    gs://$BUCKET
  Registry:  $REGION-docker.pkg.dev/$PROJECT_ID/zivo

Next:
  ./scripts/deploy-api.sh
EOF
