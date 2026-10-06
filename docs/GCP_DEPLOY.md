# Zivo — GCP Cup deploy

## Stack

- **Flutter web UI** → Firebase Hosting  
- **API** (`gcp/api`) → Cloud Run  
- **AI** → Vertex AI Gemini (`USE_MOCK_AI=false` + `GCP_PROJECT_ID`)  
- **No Supabase / Netlify / TextBee**  
- **CI/CD** → [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) (push to `main`)

## Local

```bash
# Terminal 1 — API
cd gcp/api && npm install && npm run dev

# Terminal 2 — Flutter
flutter pub get
flutter run -d chrome --web-port=7357 \
  --dart-define=GCP_API_BASE_URL=http://localhost:8080
```

Phone OTP: API returns `issuedCode` (shown in app). Seed users are KYC-verified with LKR 10k wallet after OTP.

## One-time GCP setup (CI)

1. Create GCP project + enable **Cloud Run**, **Cloud Build**, **Artifact Registry**.
2. Create a service account, e.g. `github-deploy@PROJECT.iam.gserviceaccount.com`, with roles:
   - Cloud Run Admin  
   - Service Account User  
   - Storage Admin (or Artifact Registry Writer + Cloud Build Editor for `--source` deploys)
3. Create a JSON key → GitHub secret **`GCP_SA_KEY`** (entire JSON).
4. GitHub secret **`GCP_PROJECT_ID`** = your project id.
5. Push to `main` → Actions runs **Deploy API → Cloud Run**.

Optional Hosting:

```bash
npm i -g firebase-tools
firebase login:ci          # copy token → secret FIREBASE_TOKEN
# set FIREBASE_PROJECT_ID secret + edit .firebaserc
```

After first API deploy, copy the Cloud Run URL into secret **`GCP_API_BASE_URL`** so Flutter builds hit production.

## Free-trial infra (one-time)

Project: **`gcp-ai-builder`** · Region: **`asia-south1`**  
Creates Firestore + GCS + Artifact Registry. **No Cloud SQL. No Vertex yet.**

```bash
export PATH="$HOME/google-cloud-sdk/bin:$PATH"
export GCP_PROJECT_ID=gcp-ai-builder
export GCP_REGION=asia-south1
./scripts/bootstrap-infra.sh
./scripts/deploy-api.sh
```

Live API (after deploy): set Flutter  
`--dart-define=GCP_API_BASE_URL=https://zivo-api-….run.app`

## Manual Cloud Run (without CI)

```bash
export GCP_PROJECT_ID=gcp-ai-builder
./scripts/deploy-api.sh
# or:
cd gcp/api
gcloud run deploy zivo-api \
  --source . \
  --region asia-south1 \
  --allow-unauthenticated \
  --set-env-vars=USE_MOCK_AI=true,GCP_PROJECT_ID=gcp-ai-builder,GCP_LOCATION=asia-south1,GCS_BUCKET=gcp-ai-builder-zivo-uploads
```

## Manual Firebase Hosting

```bash
flutter build web --dart-define=GCP_API_BASE_URL=https://YOUR-RUN-URL
firebase deploy --only hosting
```

## Cup demo path

1. Post Sinhala/mixed grocery task → **Pillar A** safety  
2. Helper feed → **Pillar C** match ranking  
3. Upload receipt proof → **Pillar B** reconcile  
4. End OTP → deterministic escrow release (10% fee, no cash for goods)
