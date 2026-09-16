# Zivo Admin

Use the **same consumer app URL** — no separate port required:

**http://localhost:7357/admin**

Or: Account → **Admin Dashboard** → phone OTP if asked.

## SMS sender “Kobi 2” vs Uber “ZIVO”

| What users see | Cause |
|----------------|--------|
| Message text `ZIVO: Your code is…` | Controlled by our server ✅ |
| Sender label “Kobi 2” | **Your** phone’s Contacts entry for the TextBee SIM number. Other users who never saved that number see digits, not “Kobi 2”. |

Uber shows “Uber” as From because they pay for a **registered alphanumeric sender ID** (Twilio / Dialog / etc.). Free TextBee SMS always sends from a real SIM — the carrier cannot put “ZIVO” as From without that paid brand registration.

**Users do not rename anything.** Only you (gateway phone owner) might rename a contact for yourself. Production path: paid SMS with sender `ZIVO`.

## Login for admin

Use **phone OTP** (same as the app). Do **not** use email Create account — Supabase email rate limits cause `email rate limit exceeded`.

## Optional separate process

`flutter run -t lib/admin_main.dart -d chrome --web-port=7358` — same dashboard; prefer `/admin` on 7357.

## SQL

- `010_ops_review_kyc.sql`
- `011_identity_lock_verified_gate.sql`
