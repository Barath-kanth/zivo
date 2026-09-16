# Zivo — Production app checklist

Finish **production-grade app** first; Play Store packaging comes after.

## 1. Apply SQL (Supabase SQL editor or CLI)

```bash
# In order:
# supabase/migrations/005_grocery_trust.sql
# supabase/migrations/006_payhere_wallet_topup.sql
```

Also keep [`supplemental_functions.sql`](../supabase/supplemental_functions.sql) `mock_wallet_topup` for demo builds only.

## 2. Deploy Edge Functions + secrets

```bash
cd hyperlocal

supabase functions deploy create_payhere_checkout
supabase functions deploy payhere_webhook

supabase secrets set \
  PAYHERE_MERCHANT_ID="your_merchant_id" \
  PAYHERE_MERCHANT_SECRET="your_merchant_secret" \
  PAYHERE_SANDBOX="true" \
  PAYHERE_RETURN_URL="https://YOUR_HOST/wallet?topup=success" \
  PAYHERE_CANCEL_URL="https://YOUR_HOST/wallet?topup=cancel" \
  PAYHERE_NOTIFY_URL="https://YOUR_PROJECT.supabase.co/functions/v1/payhere_webhook"
```

In PayHere merchant portal, set **Notify URL** to the same `PAYHERE_NOTIFY_URL`.

## 3. Production Flutter build (no demo / free OTP)

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=FORCE_FREE_OTP=false \
  --dart-define=ENABLE_DEMO_MODE=false \
  --dart-define=PILOT_MODE=true \
  --dart-define=USE_REAL_GPS=true \
  --dart-define=PAYHERE_MERCHANT_ID="$PAYHERE_MERCHANT_ID" \
  --dart-define=PAYHERE_SANDBOX=true \
  --dart-define=CURRENCY_CODE=LKR \
  --dart-define=DEFAULT_COUNTRY_CODE=+94 \
  --dart-define=MARKET_NAME="Sri Lanka" \
  --dart-define=DISPATCH_RADIUS_KM=5.0 \
  --dart-define=PLATFORM_FEE_PERCENT=10.0
```

Web:

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=FORCE_FREE_OTP=false \
  --dart-define=ENABLE_DEMO_MODE=false \
  --dart-define=PILOT_MODE=true \
  --dart-define=USE_REAL_GPS=true \
  --dart-define=PAYHERE_MERCHANT_ID="$PAYHERE_MERCHANT_ID" \
  --dart-define=PAYHERE_SANDBOX=true
```

## 4. Auth SMS

With `FORCE_FREE_OTP=false`, configure Supabase Auth phone provider (Twilio / MessageBird) for `+94`.

## 5. KYC

Ops review stays ([`review_kyc`](../supabase/functions/review_kyc) + in-app ops screen). Soft-launch SLA is fine until a KYC vendor is added.

## 6. Wallet top-up behaviour

| Mode | Behaviour |
|------|-----------|
| `ENABLE_DEMO_MODE=true` (debug/investor) | Instant `mock_wallet_topup` |
| Production / `PILOT_MODE` | PayHere checkout → webhook → `credit_wallet_from_payment` |

Client never holds merchant secret. See [`PaymentRepository`](../../lib/data/repositories/payment_repository.dart).

## 7. Legal pages (host before public traffic)

Static pages in [`docs/legal/`](./legal/): privacy, terms, account deletion. Link from Settings when URLs are live.

## P0 before real money

| Item | Status in code |
|------|----------------|
| PayHere checkout + webhook + SQL | Done — needs merchant secrets + deploy |
| SMS OTP | Needs Supabase provider config |
| Grocery trust SQL `005` | File ready — apply on prod |
| Real GPS | `USE_REAL_GPS=true` |
| Remove relying on committed anon defaults in CI | Pass `--dart-define` always for release |
| Helper bank payouts | Deferred to v1.1 |
| Play Store AAB / listing | Deferred until app is production-complete |

See also: [TRUST_GROCERY.md](../TRUST_GROCERY.md) · [PILOT.md](../PILOT.md)
