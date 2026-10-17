# Responsible AI — what Zivo's Gemini can and cannot decide

Every claim below was checked against the code (file references in brackets) and, where possible, against the live API
(`scripts/smoke-lifecycle.mjs`, `gcp/api/eval/test_money_paths.ts`). Gaps are listed at the end — we would rather say them than have a judge find them.

## The slide (one screen)

> **Gemini advises. People and escrow decide.**
>
> | | |
> |---|---|
> | **Consent** | Mic, camera/photos and location are always user-initiated. Nothing is read aloud or recorded automatically. Family live-links are opt-in by the booker. |
> | **No cash handoff** | Money lives in escrow. Goods are paid from a held budget and reimbursed on completion. Posts or chat messages that ask for cash, ATM PINs or "don't ask what's in the parcel" are blocked in Tamil, Sinhala and English. |
> | **Dispute escrow** | A dispute freezes the money. No AI can release, refund or ban. Funds move only on End-OTP + proof, or on the client's cancel. |
> | **Gemini cannot decide alone** | Who is hired · when money moves · whether someone is banned · what a fair wage is (it can only raise it). |

## 1. Consent

| Principle | What the code does |
|---|---|
| Voice is opt-in | Recording starts only after the user taps the mic (browser `getUserMedia` permission prompt). The audio is held **in memory** for one request (`multer.memoryStorage()`, 8 MB cap, `index.ts`) and sent to Cloud STT / Gemini; **it is not written to disk, Firestore or Cloud Storage**. |
| Read-aloud is opt-in | Text-to-speech runs on the user's tap; the concierge screen no longer speaks tool output or JSON, and reading stops when the user moves on. |
| Location is coarse | Browser/OS location prompt. Events that reach analytics round coordinates to **2 decimal places (~1 km)** (`events.ts`, `resilience.ts`, `index.ts` `batch_join`). Exact addresses are never in BigQuery. |
| Photos | Only photos the user picks ("Show it. Get help.", completion proof, receipt) are uploaded, to a private Cloud Storage bucket with signed URLs (`uploads.ts`). |
| Family sees only what the booker shares | `POST /tasks/:id/share` works **only for the client who booked** (`store.ts → createShareLink`). The public snapshot contains only title, status, booked-for name, helper name and a one-line hint — no OTPs, chat, address or photos. The link token is now 122 random bits (it was a 4-digit suffix; fixed in this evaluation). |
| Translation is labelled | A translated chat message shows a "Translated from Tamil/Sinhala/English" badge with the original one tap away, so no one is silently misquoted. |
| Booking for someone else | Tasks carry a "booked for" field so a daughter can book for her mother without impersonating her. |
| Simulated data is never passed off as real | Requests with `x-zivo-simulated: 1` tag every event; `/impact/summary?source=real|simulated|all` keeps them apart. |

## 2. No cash handoff

Zivo's position: *an elder should never have to hand a stranger cash, or a PIN, or an unlabelled parcel.*

1. **Money stays in escrow.** `createTask` holds labor **plus** the goods budget in `escrow_balance` (live test: LKR 3 550 labour + 500 goods = 4 050 held).
   The helper is paid only when `completeTask` runs; unused goods budget is returned to the client.
2. **Safety layer runs on the post _and_ on every chat message** (`/tasks/safety-check`, chat gate in `index.ts`):
   - Deterministic multilingual lexicon (`safety.ts → LEXICON`: drugs, weapons, forgery, cash-mule, ATM + PIN, secret handoff) that can only *tighten* a verdict.
   - Gemini (`gemini-2.5-flash`, thinking off) returns `allow | review | block` + reason in the user's language. Its prompt explicitly lists "giving physical cash to helpers for goods purchases" and "no-questions packages" as blocks, and allows benign alarming words ("kitchen knife set").
   - If Gemini is unreachable the pillar **fails to `review` with `degraded: true`, never to `allow`** (it used to fail open; the evaluation caught that).
3. **Trust Arbitrator** (`trust_arbitrator.ts`) watches chat + timeline for "WhatsApp me", "cash outside", "skip OTP" and can *hold escrow or escalate*. It cannot move money.
4. **Live proof** (`scripts/smoke-lifecycle.mjs`, against Cloud Run): a Tamil chat message containing an OTP arrives in Sinhala; an English "withdraw cash with my friend's ATM PIN" message returns HTTP 422 and is never delivered.

Measured (30 hand-written utterances, `docs/EVALUATION.md`): 12/12 bad requests blocked, 0/18 ordinary requests blocked; keyword list alone caught only 7/12 and **0/3** held-out euphemisms.

## 3. Dispute escrow

| Event | What happens | Code |
|---|---|---|
| Client or helper opens a dispute | status → `disputed`, `trust_hold = true`, reason stored, escrow frozen | `openTaskDispute` |
| Helper tries to finish a held job | `completeTask` throws "Escrow held by Trust Arbitrator" | `store.ts` (trust_hold check) |
| Client tries to cancel a disputed job | refused, so a dispute cannot be dodged by cancelling | `cancelClientTask` |
| Normal completion | needs the **End OTP** **and** completion proof; only the assigned helper may call it; 5 wrong codes → 10-minute lockout. Start/End OTPs are **stripped from every API response unless the caller is the booking client** (found during this review: helpers and anonymous callers could previously read them from `/tasks/helper/active` and `/tasks/:id`; fixed and covered by the lifecycle test) | `index.ts` (`/tasks/:id/complete`) |
| Cancel before start | full refund of labour + goods | tested live + `test_money_paths.ts` |
| Cancel after Start OTP | helper keeps a 30 % call-out share of labour (less 10 % fee); rest refunded; the UI states this before the client confirms | `CANCEL_CALLOUT_SHARE` in `config.ts` |

Money can move in exactly four ways: top-up, escrow hold at posting, release on End-OTP + proof, refund on cancel. **No Gemini output is wired to any of them.**

## 4. What Gemini cannot decide alone

| Decision | Who decides | Gemini's role |
|---|---|---|
| Who gets the job | **The client** taps *Assign* (`/tasks/:id/assign`) | Ranks helpers and explains why (`/match`) — a recommendation |
| Whether money is released | **End OTP visible only to the client + proof** | Reads receipts/photos as *evidence*; never pays |
| Whether a user is banned / paid / refunded | Nobody in-app (human review = future work) | Trust Arbitrator may **hold or escalate**, never decide |
| Fair wage | Wage floor from `pricing.ts` (deterministic) | Explains it; the client can only *raise* the offer |
| Whether a request is allowed | Lexicon **floor** + Gemini | **This one Gemini can decide alone** (block / review). See gap 1 |
| Translation | The sender's original is always stored and shown on tap | Produces the translation |
| Is it safe to go out (flood) | Open-Meteo data thresholds | Explains in plain language; the hazard level is not model-invented |

## 4b. Ability-aware work (disability inclusion)

* **Ability never affects rank, price, wage floor, escrow or payout.** It appears only as an informational "Access note".
* **Opt-in disclosure.** The helper's abilities are stored but only shown to the client if the helper turns disclosure on; third parties and anonymous callers have `helper.access` stripped.
* **Client may choose someone else before the job starts** (escrow stays held). This protects comfort but can be misused to discriminate, so we emit id-free `access_match / access_decline / other_decline` events and a BigQuery view `access_fairness` to monitor the decline rate.
* **AI cannot judge safety from a photo.** Zivo Eyes never guesses expiry dates or medicine and says "can't tell" when unsure; it is an aid, not a certification.
* Ability data is health-adjacent personal data — minimal storage, no analytics identifiers, needs a privacy review before launch.
* We deliberately do **not** claim sign-language translation (no SLSL model exists); see [INCLUSIVE_WORK.md](INCLUSIVE_WORK.md).

## 5. Honest gaps (say these before a judge does)

1. **No human appeal for a Gemini block.** A wrongly blocked user sees the reason and can rephrase, but cannot escalate. Next step: a "ask a person to review" button feeding the Trust queue.
2. **Dispute resolution has no admin tooling.** The freeze is real; the human who unfreezes it is out of scope for the Cup build.
3. **Evaluation is smoke-level**: 30 / 9 / 12 items by the team, synthetic TTS audio for voice, LLM-judged translations (same model family). A native-speaker review is needed. Sinhala voice-to-task is **unmeasured**; Sinhala read-aloud is bridged via English.
4. **Share links do not expire** (they can be re-generated only by the booker; no revoke button yet).
5. **Goods reimbursement uses a receipt total.** The current app finishes jobs with `receipt_total_lkr: 0`, so unused goods budget is refunded rather than paid to a helper who fronted it; the receipt-reading flow that fills it in is not yet wired into the End-OTP step.
6. **The simulated pilot is simulated** (`docs/PILOT_SIMULATED.md`). No real neighbour has used Zivo yet; the 30 % call-out share and 10 % fee are our policy choices, not tested with users.
7. **Watching is not consent-gated.** `POST /tasks/:id/watch` lets any signed-in user who already knows a task's (unguessable) id follow its status; they no longer receive OTPs, but a booker-approved invite would be cleaner.
8. **Rate-limit / quota**: under Vertex 429s responses take longer (retry + fallback); safety degrades to `review`, not to `allow`.
9. **KYC is prototype auto-approval.** The server no longer accepts a client-chosen status (junk values are ignored; `verified` needs a well-formed NIC on file), but there is no real identity check; a provider must replace it.
10. **Inclusion features are unvalidated with disabled users**, and the Sinhala/Tamil strings for them need native review.
11. **Vertex data location:** Gemini requests are routed to US and EU regions for quota; pin `VERTEX_LOCATIONS` if data residency matters.
