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
| **3. Minutes-NATIVE unit + tiers** | Credits stop existing as a unit: `user_credits.balance` holds **seconds** (beta balances converted ×40/3), and subscribers have **no balance at all** — an entitled `user_subscriptions` row buys `subscription_plans.daily_seconds` per day (**데일리 / Daily** `daily_*` = 300 s, resets midnight UTC; **무제한 / Unlimited** `unlimited_*` = 3600 s fair-use, no meter UI). Webhooks grant nothing on renewal. Signup/referral grants = 3960 s (66 min). Subscriber cap-out returns 402 `daily_cap_reached` (never a paywall); free pool spent returns 402 `insufficient_credits` (paywall). Clones free, capped 5/day past onboarding. Migration `20260811160000_minutes_native`. Caveat: pre-2026-08-11 builds divide the balance by 4.5 for display — numbers inflate until users update. | **Shipped 2026-08-11** |
| **4. Hard paywall + trial** | No free tier: new signups get 0 seconds (`handle_new_user_credits` creates the row at zero), so the first talk 402s into the paywall — voice clone + onboarding greeting stay free as the hook. The 7-day trial is Apple's intro offer (`status='trialing'` via apple-webhook) and is metered at the **Daily** allowance (300 s/day) regardless of which plan is being trialed, so a trial-then-cancel can't cost 7 × 60 min. `PaywallView.offerTrial` removed — Apple's `isEligibleForIntroOffer` is the only trial gate now. Migration `20260811180000_hard_paywall_trial`. **BLOCKED on ASC**: products must exist under the new ids (`com.roro.futurevoice.daily_monthly` …) with a 7-day free-trial intro offer, and `BetaConfig.isBeta` must flip to false — until then a NEW signup can neither talk nor pay. | **Server shipped 2026-08-11 / app gated** |

| **5. Watch leaves the talk meter** | Talk seconds meter against `daily_seconds` ALONE. Watch scenes meter by **count** against a new `subscription_plans.daily_scenes` (**Daily 2/day**, **Unlimited 20/day** fair-use), claimed once per scene via `begin_scene_play(user, scene_key)` — one key across every line of a scene, so a ten-line scene costs one count and a scene under way is never cut off. Cap-out returns 402 `scene_cap_reached` (never a paywall). Cached scenes never reach the server, so replays cost nothing, as promised. Backward compatible: a client that sends no `scene_key` stays on the `scene_seconds` pool and keeps today's economics exactly — only a registered scene moves to `scene_counted`, which the daily-seconds cap ignores. Migration `20260814100000_watch_scenes_by_count`. | **Shipped 2026-08-14 (server) / app in this build** |

Why: measured on 2026-08-13, the one active Daily subscriber spent 101/164/95 s
a day on scenes — about a fifth of a 300 s allowance — so someone using Watch
as intended bought 5 minutes of talk and got three, with nothing on screen
saying why. That is the taximeter-on-exploration failure the 2026-08-11
revision existed to remove, regrown inside the new unit.

Why a COUNT and not a bigger seconds pool: scene audio uses `fidelityModelId`
(~2x per character upstream, model-blind pricing on our side), so a scene
second costs roughly two talk seconds. The shared pool was accidentally acting
as the Daily tier's cost ceiling; a count is what replaces that bound. At 2
scenes/day a maxed Daily subscriber lands near €7.10 net rather than above it.
Do NOT raise `daily_scenes` on the Daily tier without redoing that arithmetic.

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
| daily monthly | **€9.99** | **₩15,000** | ~€7.10 |
| daily annual | **€79.99** | **₩110,000** | ~€57 (33% off 12× monthly; 39% in KRW) |
| premium monthly | **€19.99** | **₩29,000** | ~€14.30 |
| premium annual | **€199.99** | **₩299,000** | ~€143 (~17% off 12× monthly) |

All four KRW figures are Apple's own suggested price points for the EUR base
(App Store Connect, 2026-08-11). Our pre-launch estimates matched on the
unlimited pair and were off by one tier on daily (14,000 → 15,000, 119,000 →
110,000). Note the annual discount lands deeper in KRW (39%) than in EUR (33%)
— price points are a tier table, not a conversion.

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

Weekly SKUs are **off the catalog** since 2026-08-11 (`is_active = false`, migration `20260811190000_weekly_off_catalog`): they were never priced, and the minutes-native model gives `daily_weekly` the SAME 300 s/day as `daily_monthly`, so the credits-era "quarter of a month" rationale is gone. Rows kept — re-selling weekly is price → ASC products → flip the flag, no code change. **Web sells monthly + annual only.**  
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

Apple (blocking — nothing sells until these are done):

- [ ] **Six products in ASC under the RENAMED ids** — `com.roro.futurevoice.daily_{weekly,monthly,annual}` / `unlimited_{…}` (renamed 2026-08-11; they must match `subscription_plans.apple_product_id`)
- [ ] **7-day free-trial introductory offer on each** — the trial funnel reads `product.subscription.introductoryOffer`; with none, the paywall silently degrades to "Subscribe"
- [ ] `APPLE_BUNDLE_ID` / `APPLE_APP_ID` secrets set
- [ ] `apple-webhook` deployed; ASC Server Notifications V2 pointed at it
- [ ] TestFlight: purchase → `user_subscriptions` row goes `trialing`, and talk meters at 5 min/day
- [ ] Ship only builds that set `appAccountToken` (older builds can't attribute)

At launch day:

- [ ] Paywall leaves survey mode (`BetaConfig.isBeta = false`) — **do this only after the ASC products exist**, or the paywall sells nothing while the hard paywall blocks talking
- [ ] Web `PLANS` already match this doc; set Stripe price IDs + `BILLING.enabled`
- [ ] MeTab shows live plan label (already wired)

Done (2026-08-11):

- [x] Hard paywall: signups start at 0 seconds; clone + onboarding greeting stay free
- [x] Trial metered at the Daily allowance whatever plan it trials
- [x] Paywall carries the auto-renew disclosure + Terms of Use (Apple standard EULA) and Privacy Policy links — App Store Review 3.1.2, the top subscription rejection cause
- [x] App-lifetime `Transaction.updates` listener (`StoreKitService.startTransactionListener`, started in `AppDelegate`) so renewals / Ask-to-Buy / interrupted payments get finished
- [x] Restore purchases button (was already there)
- [ ] ~~Signup grant 300 → 100~~ — superseded by the hard paywall (grant is 0; snippet below kept for history)

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
