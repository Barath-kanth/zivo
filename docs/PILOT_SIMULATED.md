# Simulated neighbour pilot — SIMULATED, not real people

> **Label to show on any slide:** *"Simulated run: 8 invented personas, real Zivo APIs, real Gemini, real Pub/Sub → BigQuery pipeline. No real neighbours took part."*

We did not have 5-10 real neighbours, so this is a clearly labelled simulation. It is useful for one thing: proving the *pipeline* and the *impact arithmetic* end to end with a transparent method.
It is **not** evidence of demand, outcomes or willingness to use Zivo. A real pilot (5-10 elders in Wellawatte / Maradana with a community partner) remains the next step.

Reproduce: `cd gcp/api && GCP_PROJECT_ID=gcp-ai-builder npx tsx eval/simulated_pilot.ts` → [`pilot/pilot_results.json`](pilot/pilot_results.json).

## The 8 personas

| Persona | Lang | Area | Need |
|---|---|---|---|
| Kamala, 74 | Tamil | Wellawatte, Colombo | medicine pickup, cannot climb stairs |
| Nimal, 68 | Sinhala | Peradeniya, Kandy | eye-clinic companion |
| Fathima, 41 | English | Maradana, Colombo | sit with her mother during a shift |
| Ruwan, 33 | Sinhala | Galle Fort | carry a washing machine upstairs |
| Priya, 29 | Tamil | Nallur, Jaffna | maths tutor for her son |
| Dilani, 52 | Sinhala | Narahenpita, Colombo | stand in a government-office queue |
| Arun, 36 | English | Negombo | groceries; wheelchair user |
| Seetha, 61 | Tamil | Batticaloa | dialysis-day hospital companion |

## What is real and what is simulated

| Step | Real? |
|---|---|
| Voice-concierge turn in the persona's own language (`/agent/concierge`) | **Real** call, real Gemini (5 of 8 were answered by the deterministic fallback after Vertex rate-limiting; every reply was still produced and safe) |
| Monsoon hazard at the persona's coordinates (`/resilience/status`) | **Real** Open-Meteo data |
| Fair-price floor for the persona's task (`/tasks/price-quote`) | **Real** |
| Every event those calls cause | **Real** events, tagged `payload.simulated = true` via header `x-zivo-simulated: 1` |
| 5 street-batch joins (Wellawatte ×2, Maradana ×2, Narahenpita ×1) | **Simulated** (needs two logged-in accounts + escrow) |
| 8 cross-language chat messages (ta / si / en) | **Simulated** |
| 1 blocked cash-mule post | **Simulated** |
| Pub/Sub → BigQuery delivery of all of the above | **Real** |

## Result (`GET /impact/summary?source=simulated`)

| Metric | Value | How it is computed |
|---|---|---|
| Simulated events | 42 | |
| Street-batch joins → trips saved | 5 | 1 join ≈ 1 avoided solo helper trip |
| CO₂e avoided | **1.5 kg** | 5 × 2.5 km × 0.12 kg/km (small petrol motorcycle) |
| Cross-language messages | 8 | |
| Safety blocks | 1 | |
| Wage-floor quotes | 8 | counts *every floor quote issued* |
| Resilience events | 12 | includes the concierge's own weather tool call; alerts are now throttled to one per 1 km cell per hazard per hour |

**Read the CO₂e number for what it is:** 1.5 kg is an arithmetic consequence of the stated assumptions (5 joins), not a measurement. It is shown with its assumptions in `GET /impact/summary` → `assumptions[]` so a judge can audit or change them.

Real vs simulated stay separable everywhere: Firestore `impact_events.payload.simulated`, BigQuery view `zivo_impact.events`, and the API's `?source=real|simulated|all`.
