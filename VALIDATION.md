# Validation — 14 October 2026

Everything below was actually run; commands are copy-pasteable. Nothing here is "expected to pass".

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **0 errors**, 8 warnings, 189 infos (style: `const`, deprecations) |
| Widget tests | `flutter test` | **15 / 15 pass** (role screens, video UI, service search, presentation at 200 % text, ability picker) |
| API type check | `cd gcp/api && npx tsc --noEmit` | clean |
| Money paths (in-memory) | `USE_MEMORY_STORE=true USE_MOCK_AI=true GCP_PROJECT_ID= npx tsx eval/test_money_paths.ts` | cancel-before-start full refund · cancel-after-start call-out split · dispute freezes escrow and blocks cancel — all pass, wallet + escrow sums conserved |
| Live demo path | `node scripts/smoke-demo.mjs` | **12 / 12** against Cloud Run: web, health (Gemini not mock, Firestore), OTP login, safety allow/block (en/ta/si), Tamil concierge, Cloud TTS (`ta-IN` WaveNet), voice→task, Open-Meteo, price floor, impact summary |
| Live lifecycle | `node scripts/smoke-lifecycle.mjs` | post → escrow → accept → Tamil→Sinhala chat → cash-mule message blocked (422) → OTPs hidden from helper/anonymous → non-helper 403 → Start OTP → proof → End OTP → payout → cancel refund |
| Live chat guard | `node scripts/smoke-chat.mjs` + `npx tsx eval/test_chat_guard.ts` | **8/8** live · **12/12** unit: Tamil keeps original · `lang=hi` no longer 400 · phone/WhatsApp/email hard-blocked 422 · short OTP still allowed |
| Live inclusion | `node scripts/smoke-inclusion.mjs` | **10 / 10**: KYC can't be self-approved (valid NIC required, junk ignored) · concierge answers in ≈ 10.8 s with 4 tool calls · abilities sanitised · ability-fit · access note visible to client only · client told in chat · decline reopens task with escrow kept and blocks re-accept · Sinhala adapted brief (1.5 s) · Zivo Eyes list check (~2 s) · Doorstep Talk ta→en (~1.7 s) |
| Voice latency | `node scripts/latency-voice.mjs` | two-call ≈7.9 s median (14.6 s worst) → one call ≈3.7 s; Tamil voice-plan ≈4 s |
| Model evaluation | `npx tsx eval/run_eval.ts` | see [docs/EVALUATION.md](docs/EVALUATION.md) |
| BigQuery pipeline | Pub/Sub `zivo-events` → `zivo_impact.events_raw` → views | rows verified (≈280 events incl. simulated pilot) |

## Defects found by this validation and fixed

00. The API used the deprecated `@google-cloud/vertexai` SDK → migrated to `@google/genai` (Vertex mode); function-calling, vision, audio and JSON paths re-verified live.

0. **Gemini quota is per model per region; us-central1 flash-lite returned 429 after a single call** → calls now spread over 4 Vertex regions with 20 s cool-down failover (`VERTEX_LOCATIONS`), concierge tools run in parallel/speculatively, and concierge replies are translated with a script-checked single-language call (a Tamil request had once been answered in Sinhala, and a failed translation could surface a `[English→Tamil]` mock tag).

1. Safety pillar **failed open** to a mock "looks fine" when Vertex returned 429 → retry/backoff, model fallback, lexicon floor, fail-to-`review`, `degraded` flag.
2. Cloud TTS / STT APIs were **not enabled** on the project; read-aloud silently fell back → enabled; smoke test fails if TTS is not `cloud`.
3. Cancelling a job left money **stranded in escrow** → refund logic with ledger entries + tests.
4. **Start/End OTPs were readable by helpers and anonymous callers** (`/tasks/helper/active`, `/tasks/:id`, `/tasks/open`, `/me/watching`) and `/tasks/:id/complete` had no auth → OTPs now stripped from every response unless the caller is the booking client; start/complete require the assigned helper; 5 wrong codes → 10-minute lockout.
5. Family share-link token had 4 digits of entropy → 122 random bits.
6. Translation prompt turned "my mother" into "him/they" in Sinhala → pronoun rule; re-run clean.
7. Tests failed for missing `LocaleCubit` / `WalletBloc` providers and animation `pumpAndSettle` timeouts → fixed.
8. Pub/Sub → BigQuery with a typed table failed (`invalid_argument`) → raw table + typed view.
9. Voice understanding + splitting could take **minutes**: two sequential thinking-enabled Gemini calls, no client timeout, SDK back-off stacking on Vertex 429 → one call, `thinkingBudget:0`, model race with 22 s ceiling, 40–50 s client timeout, staged progress UI.

## Not verified / known limits

* **Inclusion features are not user-tested** with blind, deaf or mobility-impaired people; Eyes/Doorstep are Gemini outputs, not clinically validated. New Sinhala/Tamil strings were written by us and need native review. See [docs/INCLUSIVE_WORK.md](docs/INCLUSIVE_WORK.md).
* **Concierge is ≈ 10–12 s** (was 13–53 s): it chains ~9 Gemini calls (agent turns, 4 tools, translation). Speculative parallel tools, a hedged deterministic fallback (starts at 10 s) and multi-region failover bound it, but it is not instant; voice→plan (≈ 4 s) is the fast path.
* **KYC is prototype auto-approval:** the server now refuses client-chosen status and requires a well-formed NIC, but there is no real identity check.

* **Looker Studio report not built** (browser-only step; the BigQuery views are). Do not call it "live in Looker".
* No physical-device rehearsal was possible from this environment; the responsive widget tests and the live API smoke tests are what was run. Do one pass on a real phone before recording.
* Sinhala voice-to-task unmeasured; evaluation audio is synthetic; translations are LLM-judged (see EVALUATION.md).
* Vertex 429s under concurrent load; demo one request at a time (see README).
* Goods reimbursement: the app finishes jobs with `receipt_total_lkr: 0`, so unused goods budget is refunded to the client rather than paid out to a helper who fronted it. Wire the receipt total into the End-OTP step before a real pilot.
* Payments/top-up are the existing demo wallet; no real money moves.
