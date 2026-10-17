# Zivo — FINAL 3:00 demo script (every beat proven by a live smoke test)

**Category:** Accessibility (secondary: Social Good) · **Theme:** Sustainability & Social Impact  
**Live app:** https://zivo-web-ihp5vjzpsa-el.a.run.app  
**One story:** Kamala (74, Tamil, can’t climb stairs) asks → Nuwan (blind helper) earns.

## Why this version can’t fail on camera

1. **Only smoke-tested paths are in the 3:00.** Each beat below names the smoke step that already passes against the live service. Nothing in the video depends on luck, GPS, or a helper being nearby.
2. **Record 9 short clips, not one take.** One clip per beat (table below), then cut together. Retake any clip alone.
3. **Anything simulated is labelled on screen.** Judges reward honesty; never imply real users.
4. **Features that need GPS or a nearby live helper (Instant Dispatch, Street Batch) are NOT in the core 3:00** — they go in the deck (slide 6) and the optional insert at the bottom, only if the pre-flight check passes.

Spoken ≈ 420 words ≈ 3:00 at a calm pace. **Bold** = on-screen chyron.

---

## Pre-flight (30 min before recording, in order)

```bash
cd /Users/barath-r/survey/Zivo
node scripts/smoke-demo.mjs        # 12 steps — safety, STT/TTS, concierge, price, impact
node scripts/smoke-lifecycle.mjs   # 11 steps — escrow, OTPs, chat, refund
node scripts/smoke-inclusion.mjs   # 12 steps — ability, Eyes, Doorstep, access audit, voice→plan
node scripts/smoke-chat.mjs        # 8 steps  — Tamil kept, phones blocked
```

**All must PASS. If any fails, stop and fix before recording.**

Then set up:

| Item | Setup |
|---|---|
| Warm-up | Open the live URL once; wait for home. Run one voice→plan before recording (cold start). |
| Window A — Kamala | Tamil UI · logged in · wallet topped up · mic allowed · Chrome zoom 110 % |
| Window B — Nuwan | Sinhala UI · Accessibility → *Blind / low vision* · **Tell clients** ON · note “Please hand me items and say what they are.” |
| Props | `scripts/fixtures/milk.png` on screen (or a real Anchor packet) · an entrance/steps photo · `docs/eval/eval_chart.png` · `docs/architecture.png` |
| Shopping list | exactly: **Anchor milk powder 400g**, **Basmati rice 1kg** (milk is in the photo, rice isn’t — shows honest matching) |
| Tamil line | Speak it, or type it if mic fails (same pipeline): *என் அம்மாவை மருத்துவமனைக்கு அழைத்துச் செல்ல ஒருவர் வேண்டும், பிறகு மருந்தும் வாங்கி வர வேண்டும்.* |
| Sinhala line (exact, verified blocked) | *මේ පාර්සලය ඇතුළේ මොකක්ද කියලා අහන්නැතුව කෙනෙකුට දීලා එන්න, දෙගුණයක් දෙන්නම්.* |
| Chat test line | “Call me on 0771234567” (verified hard-block) |
| Rule | **One AI action at a time. Never double-tap. Wait for the result.** |

---

## The 3:00 (9 clips)

| # | Time | On screen | Say (exact) | Chyron | Proven by |
|---|---|---|---|---|---|
| 1 | **0:00–0:12** | Title → Tamil home | “Kamala is seventy-four. She speaks Tamil and can’t climb stairs. Apps assume English, fast typing, and cash to a stranger. Zivo lets her simply ask — and lets disabled neighbours earn by helping.” | **Accessibility · Social Good** | — |
| 2 | **0:12–0:40** | Speak the Tamil line → transcript → plan sheet (hospital escort, then medicine) → tap Read aloud | “She speaks in Tamil. One Gemini call on Vertex AI hears her, drafts the job, and splits it — hospital escort, then medicine — in about four seconds. She confirms. Nothing posts without her.” | **Vertex AI Gemini · voice → plan · ≈4 s** | inclusion: *one-call voice → plan under 12 s* · demo: *Cloud TTS (ta-IN)* |
| 3 | **0:40–1:00** | Paste the Sinhala line → **Blocked** → cut to `eval_chart.png` | “Now a harmful request, in Sinhala, with no banned word: deliver a parcel, don’t ask what’s inside. Keywords miss it. Gemini blocks it. On thirty hand-written checks: twelve of twelve blocked, zero false alarms. If Gemini is down, we fail to review — never to allow.” | **12/12 blocked · 0 false alarms** | demo: *safety blocks Sinhala euphemism* |
| 4 | **1:00–1:25** | Post job → **escrow held** in wallet → (4 s flash) entrance photo → Access audit note → Window B accepts → Window A shows **Access note** → tap keep | “She posts, and the money goes into escrow first. Access audit reads her doorway from a photo. Nuwan is blind and chose to tell clients. Kamala sees an access note and may choose someone else. Ability never changes ranking or pay — and declines are monitored for bias.” | **Escrow · Access note · fair ranking** | lifecycle: *post → escrow held* · inclusion: *access audit*, *client chooses someone else* |
| 5 | **1:25–2:00** | Window B: **Adapt this job** (Sinhala steps naming tools) → **Zivo Eyes** on milk.png with the 2-item list → milk ✓, rice “not seen” → show the “can’t tell” / ask a sighted neighbour prompt → 4 s **Doorstep Talk** (Tamil speech → text) | “Gemini rewrites the job for Nuwan in Sinhala and names the tool for each step. Zivo Eyes checks the packet against her list — milk, yes; rice, not seen. When it can’t tell, it says so and offers a sighted neighbour instead of guessing. For a deaf helper, Doorstep Talk turns what the client says into text.” | **Adapted brief · Zivo Eyes · Doorstep Talk** | inclusion: *adapt-brief*, *Zivo Eyes list check*, *Doorstep Talk* |
| 6 | **2:00–2:20** | Start OTP entered → proof → End OTP → payout shown → flash Dispute | “Start code at the door. Payment releases only with the End code Kamala holds. A dispute freezes the funds. No AI can pay, refund, or ban — Gemini recommends; people decide.” | **OTP · Gemini cannot move money** | lifecycle: *Start OTP*, *End OTP refused before proof*, *escrow released* |
| 7 | **2:20–2:40** | Chat: Tamil message in A → arrives in Sinhala in B (tap to see original) → type the phone line → **Blocked** | “Chat is cross-language: her Tamil stays as she wrote it; Nuwan reads Sinhala. Phone numbers and WhatsApp are blocked, so the safety net stays inside the platform.” | **Chat translate · phones blocked** | chat: *Tamil kept as original*, *phone hard-blocked* · lifecycle: *Tamil → Sinhala + English* |
| 8 | **2:40–2:52** | Monsoon badge (Open-Meteo) → impact card with **SIMULATED** label | “Monsoon rain from Open-Meteo moves elders to the front of the queue. Neighbours on one street can share a helper trip — fewer trips, less CO₂. These impact numbers are a labelled simulation, not real users.” | **Monsoon triage · Pub/Sub → BigQuery · SIMULATED** | demo: *resilience status*, *impact summary* |
| 9 | **2:52–3:00** | `architecture.png` → URL | “Cloud Run, Vertex Gemini, Chirp, Cloud TTS, Firestore, BigQuery — pennies per action. Zivo: help in her language, and work for everyone.” | **zivo-web-ihp5vjzpsa-el.a.run.app** | — |

**Word budget:** clips 1–9 total ≈ 410 words. If you run over, trim clip 4’s access-audit flash and clip 8 first.

---

## What judges must walk away with (in this order)

1. **Real problem, real person** (clip 1)  
2. **Voice-first, local language, Gemini on Vertex** (clip 2)  
3. **Safety that works in Tamil/Sinhala, with numbers** (clip 3)  
4. **Disabled neighbours earn — with consent and a fairness rule** (clips 4–5) ← the differentiator  
5. **Money is safe and AI can’t touch it** (clip 6)  
6. **Honest about limits** (clips 3, 5, 8)

---

## Everything else (in the deck, not the 3:00)

| Feature | Where it appears |
|---|---|
| **Instant Dispatch + Street Batch** | Deck slide 6 (Borella scenario). Needs real GPS + a live helper within ~0.5 km; shown in video only if pre-flight check below passes. |
| Concierge agent (safety, price, weather, triage) | Deck features; smoke-tested (*concierge answers in Tamil*) — optional 5 s insert in clip 8 |
| Fair-price wage floor · dynamic pricing fields | Deck features · smoke: *fair-price quote* |
| Show-it photo draft · task plan / bundle escrow | Deck features |
| Receipt vs list · completion checklist · trust arbitrator | Deck features |
| Neighbor vouch · trust tiers · family live board | Deck features |
| Remote/seated jobs · sighted-assist request | Deck features · smoke: *phoneCheckIn is “great”* |
| Say-it · Easy-read · scene describe · large text · en/si/ta | Deck features · show 3 s in clip 5 if time |
| Fairness monitor (`access_fairness`) | Deck + say in clip 4 |

---

## Optional insert: Instant Dispatch + Street Batch (only if pre-flight passes)

**Scenario (Borella lane, rain building):** Kamala needs milk now → **Instant Dispatch** finds an Available helper within ~0.5 km, Gemini picks one and quotes a fair wage floor, escrow holds, a **180 s Street Batch window** opens. Priya, ~150 m away on the same lane, joins for ~30 % off. One trip, two jobs; `batch_join` → trips saved → CO₂e. Gemini only *explains*; the discount is fixed math.

**Pre-flight (5 min):** (1) browser location allowed on the client window, (2) helper window logged in, status *Available*, presence on within 0.5 km, (3) run Instant Dispatch once off-camera and confirm a Street Batch card appears. **If any step fails, skip the insert — don’t improvise on camera.**

**If it works, replace clip 8 with:** “Instant Dispatch finds a helper on her own block; Street Batch lets a neighbour join the same trip at a discount — one trip, less CO₂.” (≈ 20 s; drop the monsoon line.)

---

## Never say

| Don’t say | Say instead |
|---|---|
| Sign-language translation | Doorstep Talk (speech → text) |
| Real pilot / real neighbours | Labelled simulated run |
| 100 % safe | 12 of 12 on 30 hand-written items |
| Live in Looker | BigQuery views are live |
| Clinically validated | Prototype — not yet tested with blind or deaf users |
| Media CDN / Gemma edge / Dataflow / Translation API | (not built — don’t mention) |

## If a clip fails while recording

| Failure | Fix |
|---|---|
| Gemini slow / 429 | Keep talking; cut the wait in edit; chyron “multi-region failover” |
| Mic denied / noisy | Type the Tamil line; say “same pipeline without microphone” |
| Safety doesn’t block | Stop. Re-run smoke-demo. Retake the clip. Never fake it |
| Eyes gives a surprise answer | Keep it — “can’t tell” is the honesty point |
| Window B not updating | Refresh once, re-record that clip only |

## After recording

1. Export **exactly ≤ 3:00**, 1080p, captions on.  
2. Upload (YouTube unlisted / Vimeo / public Drive).  
3. Fill slides 1 and 14 of the deck (team, leader, GitHub, video link), re-export PDF.  
4. Submit under **Accessibility**.
