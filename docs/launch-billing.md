# Billing & pricing — source of truth

> Status: **2026-07-26 — decided for launch.**  
> Owner: product/marketing. Ops (ElevenLabs tier) is separate — upgrade EL
> whenever real beta/paid usage warrants it; do not let capacity math block
> product or pricing decisions.

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
5. **Voice-slot alerts** — the ElevenLabs plan ran out of custom-voice slots
   (already wired; see below)

**Do not** change prices mid-beta without a written reason.  
**Do** upgrade ElevenLabs when the usage dashboard says so — product stays put.

### Voice-slot ceiling (the one alert that needs a same-hour answer)

Every ElevenLabs plan caps how many custom voices the account may hold. Past
that cap `/v1/voices/add` fails for EVERY new user, at the one step that makes
the product theirs — and the only fix is a plan upgrade, i.e. a human.

So it is wired end to end:

- `elevenlabs-voice-clone` classifies the upstream failure
  (`voice_limit_reached` & friends, or a 429) and answers **429
  `{"error":"voice_capacity"}`** instead of leaking upstream JSON. 429, not
  5xx: the app auto-retries 5xx three times, and this doesn't clear in 500ms.
- `_shared/ops_alert.ts` pings Telegram immediately — on the first failure of
  the hour, then at the 5th, 25th and every 50th, so escalation is visible
  without a notification storm. Counts live in `ops_alerts` (owner query:
  `select * from ops_alerts order by last_seen_at desc`).
- The app shows `VoiceCapacitySheet`: too many people at once, we're on it,
  your recording is saved, try again in a few minutes. Retry re-uses the take
  they already read (`VoiceSampleStore`), so it costs them nothing.
- **Before** the ceiling: every successful clone checks
  `/v1/user/subscription` and pings once per remaining-slot step per day from
  the last 10% of the plan (min. 3 slots) — a countdown, so the upgrade
  happens while there's still room.

Requires `TELEGRAM_BOT_TOKEN` + `TELEGRAM_ADMIN_CHAT_ID` in the function env
(`supabase secrets set …` — the same pair the depletion alert uses). Without
them the alert is logged and dropped; the user-facing sheet is unaffected.

After changing any of this: `supabase db push` (for `ops_alerts` +
`record_ops_alert`) and `supabase functions deploy elevenlabs-voice-clone`.

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
