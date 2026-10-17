# Scalability, cost and sustainability

**Honesty note.** Latency numbers are measured on the deployed service (single requests). **Cost figures are estimates** from public list prices as I know them and typical token counts — *not* billing data. Check Cloud Billing → Reports and the current Vertex AI pricing page before quoting them. A \$100 budget alert (`Zivo Cup cap 100 USD`, thresholds 25/50/80/100 %) is set on the billing account; it alerts, it does not stop spending.

## 1. Architecture choices that scale

| Concern | Choice | Why it scales |
|---|---|---|
| Compute | Cloud Run (`zivo-api`, `zivo-web`), `min-instances=0`, `max-instances=3` | Scales to zero (no idle cost); the max is a spending guard, raise it for a pilot. |
| State | Firestore, Cloud Storage | Managed, horizontally scalable; the API is stateless. |
| AI | Vertex AI Gemini 2.5 Flash / Flash-Lite via the Google Gen AI SDK (`@google/genai`), chosen per task | Flash-Lite for cheap text; Flash where accuracy matters (safety, audio, vision). Models are env-var swappable. |
| Events | Pub/Sub → BigQuery (`zivo_impact`) | Decoupled analytics; location rounded to ~1 km grid; no user/task id on fairness events. |
| Languages | `app_strings.dart` + a language name in prompts | Adding a language is a strings file plus a prompt line. |
| Quota | **Multi-region Vertex routing** (`us-central1, us-east4, us-east1, europe-west1`; round-robin, 20 s cool-down on 429, same request retried at once in the next region) | Quota is per model *per region*, so capacity is the sum of regions. A single 429 no longer stalls a user. Data-residency needs can pin one region with `VERTEX_LOCATIONS`. |
| Reliability | Model race (hedge + hard ceiling), retries, deterministic fallbacks | Vertex 429s degrade to slower-but-safe, never to unsafe. |

## 2. Latency (measured, Oct 2026)

| Path | Result |
|---|---|
| Voice → full plan (one call, Tamil) | ≈ 3.7–4.7 s (was ≈ 7.9 s median with two calls) |
| Zivo Eyes (list check) | ≈ 2.5 s |
| Doorstep Talk (Tamil → English) | ≈ 1.8 s |
| Adapted brief (Sinhala) | ≈ 1.3–1.5 s |
| Safety check | ≈ 1–3.5 s |
| Concierge (function-calling agent, ~9 Gemini calls) | was 13–53 s; now ≈ 10–12 s (speculative parallel tools, hedged fallback at 10 s, multi-region failover) |
| Variation | Single calls range 1.5–4.5 s depending on which Vertex region answers and quota state |

## 3. Cost per request (estimates)

Assumed list prices (per 1 M tokens): Gemini 2.5 Flash ≈ \$0.30 text/image input, ≈ \$1.00 audio input, ≈ \$2.50 output; Flash-Lite ≈ \$0.10 input, ≈ \$0.40 output. Thinking is switched off on hot paths.

| Call | Rough tokens (in / out) | Estimated cost |
|---|---|---|
| Voice → plan (10 s audio) | ~1,100 / ~500 | ≈ \$0.002 |
| Zivo Eyes (1 photo) | ~1,500 / ~200 | ≈ \$0.001 |
| Doorstep Talk (5 s audio) | ~700 / ~120 | ≈ \$0.0007 |
| Safety check | ~700 / ~100 | ≈ \$0.0004 |
| Concierge turn (3 tools + reply + translation) | ~4,000 / ~800 | ≈ \$0.002–0.004 |

**Budget maths.** Even at a pessimistic \$0.01 per AI action, a \$100 budget covers ~10,000 actions — far more than a demo and a small pilot. Cloud Run's request/CPU free tier and `min-instances=0` keep hosting near zero at this volume. A busy neighbour using ~20 AI actions a month costs on the order of \$0.05–0.20.

## 4. Sustainability (can it live beyond the Cup?)

* **Revenue is built in:** a 10 % fee on completed jobs funds the AI cost. At LKR 1,200 median labour, 10 % ≈ LKR 120 ≈ a few hundred AI calls.
* **Cost controls:** caching of price quotes, cheap model for text, thinking off, `max-instances` cap, budget alerts.
* **Expansion:** new Sri Lankan districts need no code; new languages need strings + prompt line; other countries need local price floors and a safety lexicon.
* **Partners:** NGOs / disability associations can sponsor jobs and co-design the ability profile and phrase cards.

## 5. Known limits to scale

1. **Vertex per-minute quota** (429s). Request a quota increase before a pilot; until then one AI action at a time in the demo.
2. **SDK:** migrated from the deprecated `@google-cloud/vertexai` to the Google Gen AI SDK (`@google/genai`, Vertex mode) in `gcp/api/src/gemini.ts`; verified live (inclusion 10/10).
3. **Ability data is health-adjacent** personal data: minimal storage, opt-in, no analytics identifiers — needs a legal/privacy review before launch.
4. **KYC is a prototype:** the server validates NIC format; a real ID-verification provider is the swap-in.
5. **No real-user validation yet** (prototype stage by design).
