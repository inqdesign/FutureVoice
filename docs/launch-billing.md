# Billing & pricing — source of truth

> Status: **2026-08-11 — pivoting to the minutes model (below). Phase 1 live.**  
> Owner: product/marketing. Ops (ElevenLabs tier) is separate — upgrade EL
> whenever real beta/paid usage warrants it; do not let capacity math block
> product or pricing decisions.

---

## 2026-08-11 revision — credits → minutes

Beta feedback was unanimous: per-click credit charges ("복습만 해도 6~10씩
사라져서… 클릭 한 번도 고민하게 되고 며칠 손을 놓았습니다") created taximeter
anxiety on exactly the behaviours the app needs daily — review and
exploration. The meter also sat in the wrong place: the click-fear surfaces
were Gemini calls (~$0.002 real cost charged at 1 cr ≈ $0.04), while the real
cost (TTS characters) drained invisibly (scene playback, post-call automatic
spend). New model:

**Meter ONE thing — talk time — where the user already expects a meter.
Everything else is free, defended by invisible daily caps.**

| Phase | What | Status |
|-------|------|--------|
| **1. Free the loop** (server-only, no app update) | All Gemini purposes → 0 credits, per-purpose daily request caps (`record_free_usage`). Review TTS (drill/library/shadow/voice_preview/daily-call) free inside a 12k-chars/day pool, falling through to the paid pooled charge past it (`charge_tts_free_pooled`) so purpose-spoofing gains at most the pool. 0-delta ledger rows keep attribution. Migration `20260811100000_free_learning_loop`. | **Shipped** |
| **2. Minutes metering** | Talk debits **wall-clock active-call time** (the in-call timer IS the price; server floor `max(reported seconds, TTS chars ÷ 750 × 60)` against under-reporting clients). Watch scenes debit their audio length (~850 chars ≈ 60 s). Migration `20260811130000_talk_minutes`. | **Shipped** |
| **3. Minutes-NATIVE unit + tiers** | Credits stop existing as a unit: `user_credits.balance` holds **seconds** (beta balances converted ×40/3), and subscribers have **no balance at all** — an entitled `user_subscriptions` row buys `subscription_plans.daily_seconds` per day (**데일리 / Daily** `pro_*` = 300 s, resets midnight UTC; **무제한 / Unlimited** `premium_*` = 3600 s fair-use, no meter UI). Webhooks grant nothing on renewal. Signup/referral grants = 3960 s (66 min). Subscriber cap-out returns 402 `daily_cap_reached` (never a paywall); free pool spent returns 402 `insufficient_credits` (paywall). Clones free, capped 5/day past onboarding. Migration `20260811160000_minutes_native`. Caveat: pre-2026-08-11 builds divide the balance by 4.5 for display — numbers inflate until users update. | **Shipped 2026-08-11** |

Rationale in one line: flat-rate bias — subscription revenue comes from
people who under-use, and a visible per-click meter destroys the willingness
of exactly those people. Guardrails (caps) protect the tail; prices don't
have to.

What stays credit-priced until phase 2: TTS for `turn`/`scene`/`opener`
purposes (pooled chars, as before) and voice re-clone (5 cr; first clone +
24 h grace free). Onboarding greeting ≤120 chars stays free.

> Sections below this line predate the revision — prices and free-tier
> amounts still hold; the credit *charge table* semantics are superseded by
> the phases above.

---

## 0. Positioning (one line)

> **Speak-level conversation practice, in your own cloned voice — at Speak-adjacent prices.**

| Tier | Job to be done | Anchor |
|------|----------------|--------|
| **Free** | Feel the product once | Clone + a few short talks |
| **Pro** | Daily habit (~5 min talk) | Coffee money / TalkPal–ELSA band |
| **Premium** | Serious immersion | Speak / 1 tutor hour per month |

Always free after any paid generation: **replay, drills, progress, saved lines**.
Credits only gate *creating new audio/AI* — never practicing with what exists.

---

## 1. Locked launch catalog

### Prices

| Plan | EUR (list, incl. VAT) | KRW (App Store fallback) | Net ~Apple SB (71%) |
|------|----------------------|---------------------------|---------------------|
| pro monthly | **€9.99** | **₩14,000** | ~€7.10 |
| pro annual | **€79.99** | **₩119,000** | ~€57 (~29% off 12× monthly) |
| premium monthly | **€19.99** | **₩29,000** | ~€14.30 |
| premium annual | **€199.99** | **₩299,000** | ~€143 (~17% off 12× monthly) |

Annual story = **cheaper sticker price** (“~2 months free”), **not** extra credits.

### Credits per cycle (exact 12× for annual)

| Plan | Credits | What it buys (approx.) |
|------|---------|------------------------|
| pro weekly | 125 | Impulse week — app-only |
| **pro monthly** | **500** | ~150 turns ≈ 5 turns/day |
| **pro annual** | **6,000** | 12 × monthly |
| premium weekly | 375 | Impulse week — app-only |
| **premium monthly** | **1,500** | ~480 turns ≈ 15 turns/day + Watch/shadow |
| **premium annual** | **18,000** | 12 × monthly |

Weekly SKUs stay in the DB for StoreKit experiments; **web sells monthly + annual only**.  
v1 paywall default period: **annual** (higher LTV); beta survey defaults to **monthly** (clearer WTP signal).

### Unit definition

- 1 internal credit ≈ 100 TTS chars (`eleven_turbo_v2_5`)
- Typical conversation turn ≈ **3 credits** (TTS ~2 + Gemini 1)
- 10-minute talk ≈ **~45 credits** (~4.5 cr / spoken minute)

Charge table lives in `supabase/functions/_shared/credits.ts` — keep
`CreditGuideView` in sync.

---

## 2. Free tier & acquisition

| Surface | Amount | When |
|---------|--------|------|
| **Beta signup** | **300** | Live now (`beta300:` ledger prefix) |
| **Launch signup** | **100** | Swap trigger at production open |
| **Apple / Stripe trial** | Full selected plan cycle | Intro offer / trial webhook |
| **Referral** (both sides) | **300**, inviter cap 10 | Standing loop; revisit if unit econ shifts |

Beta 300 is intentionally generous so testers can form a habit and we can
read real usage. Launch 100 is enough to clone + taste, not live on.

Real trial = Apple intro offer / Stripe trial (grants a full cycle via webhook).

---

## 3. Beta phase (now) — what we measure

Subscriptions are **not** for sale. The paywall ends in a **preference survey**
(`beta_reviews.context = subscription_survey`) with **price anchors** so
answers are WTP, not vibes.

Watch in Supabase / Telegram:

1. **Credit burn rate** — days to first 402, median cr/session, cr/day
2. **Feature mix** — talk vs Watch vs shadow vs clone
3. **Survey mix** — premium vs pro vs none × period
4. **Depletion alerts** — first-time empty balance (already wired)

**Do not** change prices mid-beta without a written reason.  
**Do** upgrade ElevenLabs when the usage dashboard says so — product stays put.

---

## 4. Unit economics (floor, not a panic button)

| EL plan | $/mo | ~internal cr/mo capacity | Notes |
|---------|------|--------------------------|--------|
| Creator | $22 | ~2,000 | Fine for early beta |
| Pro | $99 | ~10,000 | Typical when paid cohort starts |
| Scale | $330 | ~40,000 | ~15–20+ paying users |

Gemini 2.5 Flash is noise at our prompt sizes.  
Full-use cost vs net revenue at Creator rates:

| Plan | Full-use cost | Verdict at typical use |
|------|---------------|------------------------|
| pro monthly | ~€5 vs ~€7 net | healthy |
| pro annual | ~€60 vs ~€57 net | thin only if every user maxes out |
| premium monthly | ~€15 vs ~€14 net | fine typical; breakeven if maxed |
| premium annual | ~€180 vs ~€143 net | acceptable with 12× credits + normal under-use |

Later (if annual share is high): drip annual credits 1/12 per month via cron.

---

## 5. Go-live checklist

Apple:

- [ ] Migration applied for annual 12× credits (`20260726…_annual_credits_12x`)
- [ ] `APPLE_BUNDLE_ID` / `APPLE_APP_ID` secrets
- [ ] `apple-webhook` deployed; ASC Server Notifications V2 pointed at it
- [ ] Six products in ASC matching `subscription_plans.apple_product_id` + 7-day free trial
- [ ] TestFlight: purchase → `user_subscriptions` + ledger grant with `apple_tx_` key
- [ ] Ship only builds that set `appAccountToken` (older builds can't attribute)

At launch day:

- [ ] Signup grant 300 → **100** (SQL body swap; see historical snippet below)
- [ ] Paywall leaves survey mode (`BetaConfig.isBeta = false`)
- [ ] Web `PLANS` already match this doc; set Stripe price IDs + `BILLING.enabled`
- [ ] MeTab shows live plan label (already wired)

### Launch signup grant (apply at production open)

```sql
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

---

## 6. Out of scope for v1 (parked)

- Credit top-up packs (ledger already has `topup`)
- Lifetime / founding-member SKU
- Family / student plans
- Hiding weekly from the app UI (keep for experiments)
- Monthly drip for annual credits
