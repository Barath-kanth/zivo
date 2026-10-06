# Free-trial infra (Zivo repo)

Use **this repo** (`survey/Zivo` → https://github.com/Barath-kanth/zivo), not `zivo-cup`.

## Stack (this phase)

| Create | Skip |
|--------|------|
| Firestore | **Cloud SQL** (burns credits) |
| Cloud Storage | **Vertex / Gemini** (AI phase next) |
| Cloud Run (`zivo-api`, min=0) | Extra unused APIs |
| Artifact Registry | |

Project: `gcp-ai-builder` · Region: `asia-south1`

```bash
export PATH="$HOME/google-cloud-sdk/bin:$PATH"
export GCP_PROJECT_ID=gcp-ai-builder
export GCP_REGION=asia-south1
cd /Users/barath-r/survey/Zivo
./scripts/bootstrap-infra.sh
./scripts/deploy-api.sh
```
