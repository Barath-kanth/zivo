# Inclusive work — evaluation, design and what is actually built

**Thesis.** The usual accessibility story is "make the app usable for disabled people." Zivo goes one step further: **let a blind, deaf, speech-impaired, mobility-impaired or dyslexic neighbour be the *helper* and earn** — and use Gemini so that the job, the tools and the client's expectations adapt to the person, not the other way round.

---

## 1. The sign-language translator: evaluated honestly

**Verdict: do not build or claim it for the Cup. Build what it was trying to achieve — Doorstep Talk — instead. Keep sign recognition as a co-designed Phase 2 experiment.**

### Why it fails on the facts

| Question | Finding |
|---|---|
| **Which sign language?** | Sign languages are separate languages (not signed Tamil/Sinhala/English). Sri Lanka uses *Sri Lankan Sign Language (SLSL)*. I know of no public SLSL corpus or recognition model. |
| **SignGemma / Google SL2T** | As described in the brief, they target **American Sign Language → English text**. We have not independently verified the release details (dates, availability, licence) — check Google's own pages before putting any of it on a slide. Even if they exist as described, ASL is not SLSL, and a model for the wrong language gives confidently wrong output. |
| **"MediaPipe → coordinates → Gemini"** | MediaPipe hand/pose/face landmarks on the edge is real and works in a browser. But Gemini is not trained to read a stream of raw joint coordinates as sign grammar. The credible path is a purpose-trained sequence model on labelled video, not prompting. Continuous sign recognition (as opposed to isolated signs) is still an open research problem. |
| **Cost / ops** | Hosting an open-weights model like SignGemma on Vertex AI needs GPU endpoints; that is a cost with no data to justify it for SLSL. |
| **The user insight** | Correct: most Deaf and hard-of-hearing people can type and read. For a *written* exchange, sign translation adds nothing, and a demo that shows signing→text would be rightly challenged by a Deaf judge ("I'd just type"). One nuance: written literacy varies, because sign is a first language for many Deaf people, so Easy-read matters and we built it. |

### Where the real barrier is

A Deaf helper at a stranger's **doorstep**: the client is *speaking*, the helper cannot hear, and the client will not type. That is the exchange that fails in a real job. So:

* **Doorstep Talk** (built): hold up the phone, the client speaks (Tamil / Sinhala / English), Gemini audio returns *what they said* and a translation, with an intent chip. No typing from the client.
* **Say-it cards** (built): the helper taps a pre-written phrase ("I'm deaf — please type or write", "Please sign here", "Job complete — OTP?") in en / si / ta. They show it full-screen or play it through Cloud TTS.
* **Chat** is already translated between ta / si / en and captioned.

### If we ever do sign: the only responsible route

1. Partner with a Sri Lankan Deaf association (co-design, paid participants, consent, data ownership).
2. Phase 2a: a **fixed "quick signals" vocabulary** (~10–20 job-relevant signs — "done", "wait", "how much", "OTP") using MediaPipe GestureRecognizer in the browser, on-device. Label it *"experimental, not sign-language translation"*.
3. Phase 2b: only with a collected SLSL dataset, train/fine-tune a recogniser; evaluate on held-out signers; publish accuracy per signer.

Not built, no code for it in the repo. No claim in the demo.

---

## 2. The idea that is actually differentiating: ability-aware work

Not "no one has ever touched it" — tools like Be My Eyes, Seeing AI, Google Lookout and Live Transcribe exist, and I have not done a formal competitor survey. What we believe is uncommon is the **combination**: those assistive tools *inside an earning marketplace*, with consent, escrow and a fairness rule.

### Flow

1. **Helper picks abilities** in the accessibility hub (Blind/low vision · Deaf/hard of hearing · Speech · Mobility · Learning/reading · other). Stored on the device and synced to `PATCH /me` (`abilities`).
2. **Disclosure is opt-in** (`disclose_access`) with an optional note. Off by default.
3. **Matching is unchanged by ability.** Rank = trust, distance, disputes. Ability appears only as an informational "Access note" reason chip.
4. When the helper accepts, **the client sees an Access card** (only if disclosed) and gets a chat message. The client can **"Choose someone else"** *before the job starts*; escrow stays held and the job goes back to open. That helper cannot re-accept the same job.
5. The helper opens the job and sees **Ability fit** — a deterministic table of how much each category demands of sight / hearing / speech / mobility / reading. It never blocks; it only tells them where to expect friction. Only *driving* (sight), *moving heavy items* (mobility) and *document work* (reading) are flagged "heads up".
6. **Adapted brief** (`/tasks/:id/adapt-brief`): Gemini rewrites the job as numbered steps, naming which Zivo tool helps at each step, in the helper's language, with a deterministic fallback.

### The tools (all Gemini on Vertex AI)

| Tool | Who | What it does | Guardrail |
|---|---|---|---|
| **Zivo Eyes** `/a11y/eyes` | Blind / low vision | Camera → *describe*, *read text*, or *match against the client's shopping list* ("Anchor milk — yes; rice — not seen") | Never guesses expiry dates or medicine; returns cautions; "I can't tell" is a valid answer |
| **Doorstep Talk** `/a11y/doorstep` | Deaf / HoH | Client speaks → text + translation + intent | Shows the heard text for the helper to verify |
| **Say-it** | Deaf / speech | Pre-written phrase cards + TTS | Static, no model output |
| **Easy-read** `/a11y/simplify` | Learning / reading | Plain-language rewrite of a job or message | Original always viewable |
| **Voice agent** `/tasks/voice-plan` | Everyone | Speak the task; one Gemini call returns transcript, draft and sub-task plan | Client confirms; nothing is posted automatically |

### Fairness rules (enforced in code)

* Ability never changes **rank, price, wage floor, escrow or payout**.
* Disclosure is **opt-in** and revocable; anonymous callers and third parties never see `helper.access` (the response redactor strips it).
* The client's right to decline is a real consent step (a client may be uncomfortable), but **it can be a discrimination channel**. We therefore log, with *no user or task id*, three event types — `access_match`, `access_decline`, `other_decline` — and the BigQuery view `zivo_impact.access_fairness` computes the decline rate for disclosed helpers. If that rate is materially higher than the baseline, the decline step must be redesigned (e.g. mandatory reason, cap, or removal).
* Ability fit is advisory. A helper can accept anything.

---

## 3. Ideas not built, ranked by feasibility

| # | Idea | Effort | Why it is interesting | Risk |
|---|---|---|---|---|
| 1 | **Remote / seated job category** | **Built** (`phoneCheckIn`, `readingAloud`, `remoteTutoring`) | Work that depends on neither sight, hearing nor mobility | — |
| 2 | **Access audit from a photo** | **Built** (`/a11y/access-audit`, attached to task) | Solves the *place* barrier for mobility helpers | Photo-based claims need a human "confirm" |
| 3 | **Sighted-assist micro-task** | **Built** (Eyes → post `sightedAssist` job when unsure) | Closes the loop when AI is uncertain | Abuse / spam monitoring still needed |
| 4 | **Quick signals** (see §1) | High + partner | Eventually on-device sign support | Needs data and Deaf co-design |
| 5 | **Employer / NGO channel**: NGOs fund jobs for disabled helpers | Medium (business, not tech) | Scale and income stability | Needs partner |

---

## 4. Feasibility and scalability

**Measured on the deployed service (single requests, Oct 2026):**

| Path | Result |
|---|---|
| Voice → full plan, one Gemini call (`/tasks/voice-plan`, Tamil) | ~3.7 s median (was ~7.9 s with two calls) |
| Zivo Eyes (shopping-list match) | ~2 s |
| Doorstep Talk (Tamil → English) | ~1.7 s |
| Adapted brief (Sinhala) | ~1.5 s |
| Worst cases | 59–143 s were seen when Vertex returned 429 and SDK back-off compounded. Mitigated by model racing (hedge + 22 s ceiling) and 40–50 s client timeouts. The concierge (a multi-tool agent) now answers in ≈ 10–12 s. |

**Why it scales:** all server logic is stateless Cloud Run behind Firestore; Gemini calls are per-request; the ability table, phrase cards and ability-fit are deterministic and free; models are swappable via env vars. Adding a language is a strings file plus a prompt language name. Any country with a similar informal-care economy can reuse the stack.

**What limits scale (honestly):** Vertex per-minute quota (429s), cost per call (not yet measured per user — do this in the pilot), and above all **data protection**: an ability profile is health-adjacent personal data. We store the minimum (a list of keys and an optional note), require opt-in, keep it out of analytics, and it must be covered by a privacy review before a real launch (e.g. Sri Lanka's Personal Data Protection Act — confirm obligations with counsel).

**Market context (verify before using on a slide):** WHO estimates about 1.3 billion people (~16 %) live with a significant disability. National census figures for Sri Lanka should be taken from the Department of Census and Statistics directly.

---

## 5. Built vs not built

| Built and verified live | Built, not clinically/user validated | Not built |
|---|---|---|
| **Access audit** (entrance photo) · **remote/seated jobs** (phoneCheckIn, readingAloud, remoteTutoring) · **sighted-assist** micro-job when Eyes is unsure · Ability profile + sanitisation (`smoke-inclusion` 8/8) · opt-in disclosure · Access card · client chat notice · "Choose someone else" with escrow kept and re-accept blocked · ability-fit · adapted brief (Sinhala, 1.5 s) · Zivo Eyes list match · Doorstep Talk · one-call voice plan · API timeouts | Zivo Eyes accuracy in real homes · Doorstep Talk in noisy doorways · Sinhala / Tamil UI strings for the new features (written by us — **need native-speaker review**) · usefulness of Say-it phrases | Sign-language recognition · real blind/deaf user testing · NGO channel · quick-signals experiment |

## 6. What to measure in a real pilot

* Share of disclosed helpers who get at least one job in 14 days vs. non-disclosed
* Decline rate for disclosed vs. non-disclosed helpers (`access_fairness` view)
* Time to first accepted job; job completion and dispute rates by group
* Helper earnings by group
* Tool usage (Eyes, Doorstep, Say-it) and whether the job succeeded when used
* Helper and client satisfaction, in Tamil and Sinhala, by a native-speaking interviewer
