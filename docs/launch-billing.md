# Billing launch plan — pricing, webhooks, free tier

> Status: 2026-07-03. Stripe (web) + Apple (iOS) webhooks are implemented.
> Current ElevenLabs plan: **Creator** ($22/mo) — confirmed 2026-07-03,
> upgradeable anytime. App uses `eleven_turbo_v2_5` everywhere
> (0.5 EL-credits/char), so: 100k EL credits = 200k chars = **2,000 internal
> credits of monthly capacity**.

## 1. Unit economics (the pricing floor)

One internal credit = 100 TTS chars (turbo) ≈ 1 conversation turn's audio.
A typical turn costs ~3 credits (TTS 2 + Gemini 1).

| ElevenLabs plan | $/mo | capacity (internal cr/mo) | cost per internal cr | supports (at ~full utilization) |
|---|---|---|---|---|
| **Creator (current)** | $22 | **2,000** | ~$0.011 | ~4 pro subs OR 1 premium + 1 pro |
| Pro | $99 | 10,000 | ~$0.010 | ~20 pro / ~6 premium |
| Scale | $330 | 40,000 | ~$0.008 | ~80 pro / ~26 premium |

(Gemini 2.5-flash adds roughly $0.002–0.003 per turn — noise at these
volumes. Overage past plan capacity bills at ElevenLabs' usage-based rate —
verify the current rate before relying on it; upgrading tiers is cheaper.)

**Capacity is the binding constraint, not margin.** Creator's 2,000 cr/month
means: one dev-bootstrap signup (1,000 cr) can consume half a month's
capacity, and ~4 paying pro users saturate it.

Upgrade triggers (check monthly EL usage dashboard):
- → **Pro ($99)** when granted credits/month (subs + signups) exceed ~1,400
  (70% of Creator capacity). In practice: ~3 paying users or an active
  TestFlight cohort.
- → **Scale ($330)** past ~7,000 granted credits/month (~15–20 paying users).
Each upgrade also improves margin (0.011 → 0.008 per credit).

What a subscriber actually receives per month:
- **pro 500cr** ≈ 150–160 conversation turns ≈ 5 turns/day — a light daily habit
- **premium 1,500cr** ≈ 480 turns ≈ 15 turns/day + heavy shadow/Watch use

## 2. Recommended prices (EUR, incl. VAT)

Remember the stack of cuts: 19% VAT off the top, then Apple 15% (Small
Business) or Stripe ~2% on what's left. Net revenue ≈ 71% (Apple) / 82%
(Stripe web) of sticker price.

| Plan | Price | Net (Apple SB) | Full-use cost (Creator) | Verdict |
|---|---|---|---|---|
| pro monthly | **€9.99** | ~€7.10 | ~€5.00 | healthy |
| pro annual (6,500cr) | **€79.99** | ~€57 | ~€65 | thin at full use — acceptable (few max out) |
| premium monthly | **€19.99** | ~€14.30 | ~€15.00 | breakeven worst-case, fine typical |
| premium annual (19,500cr) | **€199.99** | ~€143 | ~€195 | **danger at full use** — see below |

Annual-plan guardrails (pick one before launch):
1. **Reduce annual bonus**: 6,500 → 6,000 and 19,500 → 18,000 (exactly 12×monthly).
   The "2 months free" story then lives in the price, not in extra credits.
2. **Drip annual credits monthly** (1/12 per month via cron) — kills the
   "buy annual in month 1, burn 19,500 credits, refund" abuse tail.
3. Keep as-is and accept the tail risk while user counts are small.

Recommendation: (1) now — it's a single UPDATE on subscription_plans — plus
(2) later if annual uptake grows.

Weekly plans: keep them **app-only** (impulse tier). Web sells monthly/annual only.

## 3. Free tier — replace the dev bootstrap

Today every signup gets 1,000 credits (`dev_bootstrap` trigger — ~2 months of
pro-level usage, ~$11+ upstream cost per signup, abusable with throwaway
Apple IDs). Replace **at production launch** (keep for TestFlight):

```sql
-- Launch migration: shrink signup grant from 1000 (dev) to 100.
-- 100 credits ≈ 30 conversation turns + a few drills — enough to feel the
-- product (clone voice = 5cr, ~10 short sessions), not enough to live on.
create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
begin
  perform public.grant_credits(
    p_user_id => new.id,
    p_credits => 100,
    p_kind => 'grant',
    p_action => 'signup_grant',
    p_source_fn => 'auth_trigger',
    p_idempotency_key => 'signup:' || new.id::text,
    p_metadata => jsonb_build_object('reason', 'launch signup grant')
  );
  return new;
end;
$$;
```

(Trigger stays the same; only the function body changes. The `bootstrap:` and
`signup:` idempotency prefixes keep old/new grants distinguishable in the
ledger.) The real trial lives in Apple's intro offer / Stripe trial — those
grant a full cycle's credits via the webhooks.

Referral grants (500/friend, InviteView) are unchanged but should get a cap
audit before launch.

## 4. Go-live checklist (webhooks)

Apple:
- [ ] Apply migration `20260703120000_stripe_web_billing.sql` (also used by Apple flow's `source` column)
- [ ] `supabase secrets set APPLE_BUNDLE_ID=com.roro.futurevoice APPLE_APP_ID=<numeric ASC app id>`
- [ ] `supabase functions deploy apple-webhook --no-verify-jwt`
- [ ] ASC → App Information → App Store Server Notifications V2:
      Production + Sandbox URL `https://<project>.supabase.co/functions/v1/apple-webhook`
- [ ] Create the 6 subscription products in ASC with the exact
      `apple_product_id`s from subscription_plans; add intro offer (free trial)
- [ ] Verify on TestFlight: purchase → `user_subscriptions` row (source
      'apple') + `usage_ledger` grant with `apple_tx_` key
- [ ] NOTE: purchases from builds BEFORE the appAccountToken change cannot be
      attributed — ship that build before opening sales

Stripe (web): see `web/README.md`.

At launch:
- [ ] Swap the signup-grant function (SQL above)
- [ ] Update paywall + web PLANS copy to the final prices
- [ ] MeTab "Beta — no subscription" copy is already replaced by the live plan label
