# Zivo — GCP Cup deploy

## Stack

- **Flutter web UI** → Firebase Hosting  
- **API** (`gcp/api`) → Cloud Run  
- **AI** → Vertex AI Gemini (`USE_MOCK_AI=false` + `GCP_PROJECT_ID`)  
- **No Supabase / Netlify / TextBee**

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

## Cloud Run

```bash
cd gcp/api
gcloud run deploy zivo-api \
  --source . \
  --region asia-south1 \
  --allow-unauthenticated \
  --set-env-vars=USE_MOCK_AI=false,GCP_PROJECT_ID=YOUR_PROJECT,GCP_LOCATION=asia-south1
```

## Firebase Hosting

```bash
flutter build web --dart-define=GCP_API_BASE_URL=https://YOUR-RUN-URL
firebase init hosting   # public: build/web
firebase deploy --only hosting
```

## Cup demo path

1. Post Sinhala/mixed grocery task → **Pillar A** safety  
2. Helper feed → **Pillar C** match ranking  
3. Upload receipt proof → **Pillar B** reconcile  
4. End OTP → deterministic escrow release (10% fee, no cash for goods)
