# Zivo — Grocery / purchase trust (zero cash risk)

## The problem

If a client gives a helper cash to buy groceries, the platform cannot prove who cheated when:

- Helper vanishes with cash  
- Helper buys fewer / cheaper items  
- Store short-changes or substitutes items  

## The rule

**Never hand physical cash to helpers for goods.**

| Bucket | Who pays | How |
|--------|----------|-----|
| Labor fee | Client → escrow → helper (90%) + platform (10%) | After End OTP |
| Goods budget | Client → escrow | Helper pays at till with own money; reimbursed **min(receipt, budget)** after proof |

## Evidence chain (seller vs helper)

1. Client posts **shopping list** + **goods budget**  
2. Helper shops and uploads **receipt photo** + **bag/goods photos** (`submit_purchase_proof`)  
3. Client inspects goods vs list/receipt — only then shares **End OTP**  
4. Escrow releases labor + goods reimbursement; unused budget returns to client  
5. If conflict → **Open dispute** (status `disputed`, escrow frozen for ops)

## SQL to run

In Supabase SQL editor, run:

`supabase/migrations/005_grocery_trust.sql`

## App flags for pilot (no demo lies)

```bash
flutter run -d chrome --web-port=7357 \
  --dart-define=PILOT_MODE=true \
  --dart-define=ENABLE_DEMO_MODE=false \
  --dart-define=FORCE_FREE_OTP=false \
  --dart-define=USE_REAL_GPS=true \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

Configure real SMS on Supabase Auth before `FORCE_FREE_OTP=false`.

## Payments (next)

Replace `mock_wallet_topup` with LankaQR / card gateway; top-up still funds the same escrow path — no change to grocery trust rules.
