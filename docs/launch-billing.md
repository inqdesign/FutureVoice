# Billing & pricing — source of truth

> Status: **2026-08-11 — pivoting to the minutes model (below). Phase 1 live.**  
> Owner: product/marketing. Ops (ElevenLabs tier) is separate — upgrade EL
> whenever real beta/paid usage warrants it; do not let capacity math block
> product or pricing decisions.

---

## Pricing principle (owner, 2026-08-20)

**We do not make money from people being unable to use what they bought.**
Stated by the owner directly: the wish is that every Daily subscriber really
does talk their five minutes a day. If that leaves no margin, the answer is a
higher price — not a structure that quietly relies on the allowance going
unspent, and not one that makes the allowance harder to reach.

This is a constraint on design, and it rules things out:

- No mechanism whose PURPOSE is to keep usage below what was sold. Caps exist
  to bound cost per unit and to keep one account from starving the rest; they
  must never be tuned to make the plan's own number unreachable.
- "Acceptable with normal under-use" is not a verdict a plan may pass on. The
  question to ask of a price is **what it earns when every subscriber uses
  everything**, not what it earns on today's usage curve.
- Where full use doesn't clear cost, the fix is the PRICE (or the cost), and
  the numbers below are the ones that need re-deriving — see §4, whose current
  verdicts still lean on under-use and predate both the minutes model and the
  2x fidelity model on scenes.

The flat-rate-bias note further down is about not putting a METER in front of
people, which stays true. It is not a licence to price against under-use.

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
| **4. Hard paywall + trial** | No free tier: new signups get 0 seconds (`handle_new_user_credits` creates the row at zero), so the first talk 402s into the paywall — voice clone + onboarding greeting stay free as the hook. The 7-day trial is Apple's intro offer (`status='trialing'` via apple-webhook) and is metered at the **Daily** allowance (300 s/day) regardless of which plan is being trialed, so a trial-then-cancel can't cost 7 × 60 min. `PaywallView.offerTrial` removed — Apple's `isEligibleForIntroOffer` is the only trial gate now. Migration `20260811180000_hard_paywall_trial`. **BLOCKED on ASC**: products must exist under the new ids (`com.roro.futurevoice.daily_monthly` …) with a 7-day free-trial intro offer, and the beta's survey-mode paywall had to go — done 2026-08-18, `BetaConfig` deleted with it. | **Server shipped 2026-08-11 / app gated** |

| **5. Watch leaves the talk meter** | Talk seconds meter against `daily_seconds` ALONE. Watch scenes meter by **count** against a new `subscription_plans.daily_scenes` (**Daily 2/day**, **Unlimited 20/day** fair-use), claimed once per scene via `begin_scene_play(user, scene_key)` — one key across every line of a scene, so a ten-line scene costs one count and a scene under way is never cut off. Cap-out returns 402 `scene_cap_reached` (never a paywall). Cached scenes never reach the server, so replays cost nothing, as promised. Backward compatible: a client that sends no `scene_key` stays on the `scene_seconds` pool and keeps today's economics exactly — only a registered scene moves to `scene_counted`, which the daily-seconds cap ignores. Migration `20260814100000_watch_scenes_by_count`. | **Shipped 2026-08-14 (server) / app in this build** |

| **6. Monthly pools, and Daily/Unlimited → Light/Plus** | Allowances become **pools per billing period**, like a mobile data plan: **Light 150 min + 60 scenes**, **Plus 1800 min + 600 scenes** (Plus's talk ceiling was removed on 2026-08-21 and its scene pool cut to **120** on 2026-08-23 — see below). No daily ceiling of any kind — spend the month in one call if you like. `daily_seconds` / `daily_scenes` survive as the DESCRIPTIVE "5 minutes a day" figure only; `monthly_seconds` / `monthly_scenes` are what `consume_metered_seconds` and `begin_scene_play` enforce, both counted from `billing_period_start()`. The trial is pro-rated 7/30 (≈35 min, 14 scenes) so a week's sample can't spend a month. Tier names and internal plan ids move to `light_*` / `plus_*`; the **Apple product ids do NOT** (`20260820220000`) — four subscriptions were already registered in ASC under the old names, and an Apple product id is permanent per app. Migration `20260820180000_monthly_pools_light_and_plus`. | **Shipped 2026-08-20** |

Four designs were shipped and replaced in one day getting here; the discarded
ones are worth knowing so they don't come back.

1. **Daily cap, no carry-over** (the original). Broke on the person whose week
   only has room for Saturday: they got 5 minutes on Saturday and lost the
   other six days. Not "some waste" — a hard ceiling on the one day they
   turned up.
2. **A BANK of unused days** (`20260820120000`). Computed today's extra as "the
   unused seconds of the last N days". It reads correctly and double-spends:
   nothing debits an idle day once it has been drawn, so every window still
   containing it counts it again. Measured +40%. A bank must be debited to be
   correct, which means storing a balance.
3. **A rolling 7-day WINDOW** (`140000`, `160000`). Correct — the usage rows are
   the ledger, so no stretch of 7 days can exceed 7 × daily — but it needed a
   signup clamp to stop a new subscriber's first day opening with the whole
   week, and it could not be explained in a sentence. Three migrations of
   arithmetic to answer what a data plan answers with one number.
4. **Monthly pool** — where it landed. The objection that had ruled it out was
   fill rate: a visible monthly balance gets spent, and this tier's margin came
   from the allowance going unspent. **That objection was retired by the
   pricing principle at the top of this file**, not out-argued.

What survives from the window era: the taximeter risk is real and is handled in
the UI rather than the meter — the figures live one tap away in Me, and the
home shows an arc with no digits.

**Watch scenes are a separate pool, not a share of the talk one** (since phase
5) and they do NOT get a daily allowance either. 60 a month on Light, spent
whenever.

**The Apple product ids stay `…daily_monthly` / `…unlimited_annual` and that is correct.** They were registered before the rename, and an Apple product id can never be renamed or reused — not even after removal from sale. Nobody ever reads one; what a buyer sees is the localized Display Name, which IS editable, so the tiers are renamed there instead. `apple-webhook` resolves `apple_product_id` → `subscription_plans.id` and the app reads ids out of the catalog, so the two id spaces were already independent. Read `apple_product_id` as "what Apple calls this", never as "what this plan is". Registering four fresh ids would burn four more permanent strings, need four more introductory offers, and leave four dead products in the group forever.

Why the names: "Daily" named a unit that no longer exists, and "Unlimited"
named something that was never true — that tier has always had a fair-use
ceiling, and under the pricing principle we don't sell a promise the meter
doesn't keep (its scene count is printed on the card). The SIZE
isn't in the name because the numbers are still being tuned and an Apple
product id is permanent once it has sold. Not Light/**Heavy** because
`PaywallView` has always held that the label must not grade the BUYER.

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

## Plus: no talk ceiling (2026-08-21, `20260821120000_plus_talk_unlimited`)

Talking is uncapped on Plus. Watch keeps `monthly_scenes` on every tier.

**The asymmetry is the whole argument.** A Watch scene is consumed by TAPPING —
an idle afternoon can farm a month of them, and each is billed to us on
`fidelityModelId` at roughly twice the per-character rate of a talk turn, so a
count is the only thing between us and that. Talking is consumed by SPEAKING.
Nobody talks for six hours; effort is the limiter, and it is one no ceiling can
improve on. At 1,800 min the pool was therefore doing no work — that is an hour
every day, which almost no account approaches — while costing us exactly what
the ceiling existed to protect: a subscriber who has to ration the one activity
the product is for.

**This is a measurement decision as much as a pricing one.** No account has ever
run without a talk ceiling, so the honest ceiling cannot be derived from
anything we currently hold. Usage keeps being recorded in full
(`tts_char_pool`, `usage_ledger`, `talk_seconds_by_language`); revisit with real
data rather than an estimate. `talk_unlimited` is a COLUMN precisely so
restoring the ceiling is one `UPDATE` — but note the client reads the TIER, so
flipping it back means updating the paywall card in the same release or the card
will keep promising "No limit".

**What this depends on:** the meter must charge for SPEECH, not for a screen
left open. `TalkMeter.isBillable` + `ConversationView.someoneIsTalkingHere()`
(close-mic voiced audio, three witnesses, café-tested 2026-08-18) are what make
the effort argument true. Weaken them and this becomes an open tab, and the
margin arithmetic below stops holding.

## Plus: Watch scenes 600 → 120 (2026-08-23, `20260823140000_plus_scene_count`)

**600 was 20 scenes a day.** It came from the 2026-08-20 monthly-pool
migration as "the same 30× of the old fair-use day" — arithmetic carried
forward from a daily cap, never a number anyone asked the cost of.

### Measured unit cost

From `usage_cost_component` over 2026-08-14..23 (15 registered scene plays,
140 talk minutes), at the seeded ElevenLabs Creator rate of $0.00022/credit:

| Unit | Measured | Upstream cost |
|------|----------|---------------|
| One Watch scene | 1,157 chars · 82 s audio · 868 credits | **$0.190** |
| One talk minute (turn TTS) | 365 chars, all turbo | **$0.040** |
| One talk minute (all non-scene TTS: daily call, drills, shadow, library) | — | $0.058 |
| Gemini | ~2.3 turns/min at $0.0012 + $0.0001 transcribe | ~$0.003/min |

**So one scene costs 4.7 talk minutes.** Not 6.4, which is what
`cost_per_scene` reports and what the earlier note recorded: the view's
back-fill dates every `purpose = 'scene'` character to the fidelity model, but
exactly HALF of a scene's characters are the COUNTERPART, whose preset voice
has always run on turbo (`WatchView`: `isOwnVoice ? fidelityModelId :
"eleven_turbo_v2_5"`). Measured split: 8,610 chars on the clone, 8,739 on
presets. The back-fill only touches rows written before `model_id` began being
recorded (2026-08-23) — but that is every row the 6.4 figure came from. **Fix
the view before quoting scene cost again.**

### Why 600 could not stand

Plus net revenue is **$16.99/mo** ($19.99 × 85% US) and **$10.20/mo** on the
annual ($143.99 × 85% ÷ 12). 600 scenes is **$114.24** of upstream cost —
6.7× the monthly net, 11.2× the annual, before a single minute of the talk
that `20260821120000` uncapped.

The scene pool was quietly the larger of the two things Plus sells: 600 × 4.7
= **2,820 talk-minutes of cost**, against the 1,800-minute talk pool the
previous migration deleted for being "an hour every day, which almost no
account approaches". The same sentence was true of 20 scenes a day, and there
it was still being called a cost bound. A cap nobody can reach earns from
under-use, which the pricing principle at the top of this file forbids.

### Why 120

Light's 60 doubled, and Plus is Light's price doubled — one rule, printable on
the card. Four a day is ~5.5 min of scene audio plus the study around it: a
number an intense learner can genuinely spend in full. Plus's differentiator is
already uncapped talking, so the scene count does not have to carry the tier
ladder and is sized to what it costs.

### What 120 does NOT fix

120 × $0.190 = **$22.80 against $16.99 net**. Scenes alone are still 1.3× the
monthly net and 2.2× the annual. **Cutting the count fixed the order of
magnitude, not the sign.** The rest has to come off the unit cost or out of the
price:

| Lever | Saving | Where |
|-------|--------|-------|
| ElevenLabs Creator → Scale ($330/2M cr) | −25% | ops only, no code |
| Scene length 82 s → 55 s | −33% | `ScenarioCurriculumEngine` prompt |
| The clone half of a scene on turbo | −33% | quality call — but note `fidelityModelId`'s own rule is "only where `PhraseAudioStore` caches the result", and `SceneWatchView(freshTake:)` writes new text every run, so nothing caches and the 2× repeats forever. Currently in violation of that rule. |

All three together put a scene at **$0.066**, where 120 costs $7.90 and leaves
$9.09 of the monthly net for uncapped talk (~227 min). Not bundled into the
migration: three separate decisions with three separate risks, and the count
needed no code change at all.

**Light is not fixed either, and was not touched.** Its 60 scenes cost $11.42
against $8.49 net, and its 150 talk minutes cost $8.66 — either half alone is
most of the plan's revenue. Fixing Plus only moves the loss-making account down
a tier. Re-derive Light against the same table before launch.

### Blast radius

None beyond the number. `PaywallView` reads `monthly_scenes` off the catalog
([PaywallView.swift](../FutureVoice/Views/PaywallView.swift) `pools(_:)`), so the
card follows with no app release; `begin_scene_play` enforces it unchanged.
`subscription_transactions` is empty — no purchased allowance shrinks.

**Margin exposure:** unbounded per subscriber in principle. Bounded in practice
by how much a person will talk, and by the server's chars-per-minute floor on
turn TTS. Watch — the farmable half, and the expensive one per character —
is still capped, so the tail this removes is the talking tail only.

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

| Plan | USD (base) | EUR (Apple auto) | KRW (set by hand) | Annual discount |
|------|-----------|------------------|-------------------|-----------------|
| light monthly | **$9.99** | €9.99 | **₩15,000** | — |
| light annual | **$79.99** | €89.99 | **₩110,000** | 33% / 25% / 39% |
| plus monthly | **$19.99** | €22.99 | **₩29,000** | — |
| plus annual | **$143.99** | €149.99 | **₩209,000** | 40% / 46% / 40% |

**Registered 2026-08-21; these are the live ASC values, not a proposal.** USD is
the base storefront — Apple auto-generates the other 174 from it, and the EUR
column above is what it produced (VAT-inclusive, hence higher than USD). **KRW
was overridden by hand**, because Korea is a main market and Apple's conversion
knows the exchange rate but not that Speak has anchored Korean expectations at
₩29,000 / ₩129,000; left on auto, Light annual would have landed at ₩129,000
(28% off) and Plus annual at ~₩232,000 (33%).

**Apple never re-adjusts an auto-renewable subscription** for FX or tax drift,
so every figure above stays until someone edits it.

**Apple's actual take is better than this doc long assumed.** The ASC price
table reports Year-1 proceeds of **85.0% in the US** and **77.3% in Korea and
Japan** — the latter being `list ÷ 1.1 VAT × 0.85`, i.e. the Small Business
Program rate on the VAT-exclusive amount. The old "~71% net" figure below was
conservative by 9–20%, so **every margin verdict in §4 is more favourable than
it reads** — re-derive them against 85% / 77.3% before concluding anything
about price.

**The one soft spot: Light annual is 25% in EUR** because its monthly stayed on
the old €9.99 while the annual was regenerated to €89.99. It is the shallowest
discount in the table and sits under Fluently's 30%. Setting EUR Light annual to
€79.99 by hand restores 33% and leaves the Plus-deeper-than-Light ordering
intact. Not urgent — the ordering is what mattered, and it is correct.

Annual story = **cheaper sticker price**, **not** extra allowance.

**The discount is ~33% on Light and ~40% on Plus, and the higher tier must
never be the shallower one.** It was, until 2026-08-21: the rule here used to
read "~2 months free", which is 17%. Plus followed it exactly (€199.99) and
Light happened not to (€79.99 = 33%), so the paywall showed `39% off` beside
`14% off` and the plan we most want people on looked like the worse deal. The
comparable set is nowhere near 17% — Speak is 50% on Premium and 62% on
Premium Plus, Fluently 30% — and Speak, the market leader in Korea, discounts
its TOP tier deepest. **Do not restore a flat "two months free" rule.**

Plus stops at 40% rather than matching Speak's 62% for one reason: since
`20260821120000` its talk time has no ceiling, while Speak Premium Plus is
lesson-based and therefore bounded. Selling uncapped voice minutes a year in
advance at half price is the one combination we cannot price from an estimate
— revisit once real usage exists.

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
v1 paywall default period: **monthly** — the smaller commitment; a paywall that opens on the year-long option reads as pressure rather than a choice.

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
| **Referral** (both sides) | **1800 s (30 min)**, inviter cap 10 | Standing loop, and since the hard paywall the ONLY free talk time in the product (`20260818100000_referral_thirty_minutes`) |

Beta 300 is intentionally generous so testers can form a habit and we can
read real usage. Launch 100 is enough to clone + taste, not live on.

Real trial = Apple intro offer / Stripe trial (grants a full cycle via webhook).

---

## 3. Beta phase — closed 2026-08-18

The paywall sells. `BetaConfig`, `BetaWelcomeView` and the paywall's
willingness-to-pay survey were deleted on 2026-08-18, along with the
hardcoded planned-price tables in `StoreKitService` that anchored it —
a second copy of the price list in the binary can only drift from App Store
Connect. Prices now come from StoreKit or aren't shown.

What the survey collected is still in `beta_reviews`
(`context = subscription_survey`); the table itself stays, because
`FeedbackSheet` still writes to it.

Still worth watching in Supabase / Telegram:

1. **Seconds burn rate** — days to first 402, median s/session, s/day
2. **Feature mix** — talk vs Watch vs shadow vs clone
4. **Depletion alerts** — first-time empty balance (already wired)

**Do not** change prices mid-beta without a written reason.  
**Do** upgrade ElevenLabs when the usage dashboard says so — product stays put.

---

## 4. Unit economics (floor, not a panic button)

> **STALE — do not read a verdict off this section.** The table below still
> names `pro` / `premium` (tiers that no longer exist), prices in €, assumes
> ~71% Apple net (it is 85% US / 77.3% KR), predates the minutes model, the 2×
> fidelity model on scenes, and every measured figure. The live unit economics
> are in "Plus: Watch scenes 600 → 120" above; the EL capacity table here is
> still roughly right and is the reason it survives.


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

- [x] **Four products exist in ASC** — `com.roro.futurevoice.{daily,unlimited}_{monthly,annual}`. **Keep these ids** (see above); they must keep matching `subscription_plans.apple_product_id`.
- [ ] **Rename what the BUYER sees** — each product's Reference Name and its localized Display Name to Light / Plus (ko: 라이트 / 플러스). The product id stays as it is and is never shown.
- [ ] **All four in ONE subscription group** — otherwise Light ↔ Plus can't be an upgrade/downgrade, and Apple's one-intro-offer-per-group rule doesn't apply the way the trial funnel assumes. **Weekly is NOT sold** — already switched off in `20260811190000_weekly_off_catalog` (`is_active = false`), and the client selects on `is_active`. Two independent guards keep it hidden: the plan never loads, and `PaywallView.availablePeriods` only offers a period whose StoreKit product actually loaded. Re-enabling it later is one flag plus the ASC products — no migration, no code change.
- [ ] **7-day free-trial introductory offer on each** — the trial funnel reads `product.subscription.introductoryOffer`; with none, the paywall silently degrades to "Subscribe"
- [x] `APPLE_BUNDLE_ID` (`com.roro.futurevoice`) / `APPLE_APP_ID` (`6792794655`) secrets set — 2026-08-20. Note `APPLE_APP_ID` is passed to the verifier for PRODUCTION only (`environment === PRODUCTION ? appAppleId : undefined`), so TestFlight/Sandbox needs the bundle id alone.
- [x] `apple-webhook` deployed (v2, ACTIVE) — **and rewritten 2026-08-20**: Apple's `SignedDataVerifier` cannot verify a chain on the Supabase edge runtime (`X509Certificate.verify` / `.checkIssued` are unimplemented, and throw with an empty message), so it had never accepted a single notification. Now verifies the JWS itself on Web Crypto via `@peculiar/x509`. Don't "simplify" it back to the library.
- [x] **End-to-end verified 2026-08-20** — Sandbox purchase → RC → webhook `200` → `user_subscriptions` row (`apple_original_tx_id 2000001224361429`, `light_monthly`, active). The Apple product id `…daily_monthly` resolved to plan `light_monthly`, confirming the id split.
- [ ] **ASC Server Notifications V2 → RevenueCat → us** (decided 2026-08-20, plan B in `docs/revenuecat-setup.md` §3: no SDK, no app change). ASC's Production AND Sandbox URLs both point at RC's incoming webhook; RC's *Apple Server Notification Forwarding URL* points at `…/functions/v1/apple-webhook`; RC's *Track new purchases from server-to-server notifications* is ON. RC forwards Apple's original signed payload, so the function needs no change and `user_subscriptions` stays the source of truth for entitlement. **All three or none** — with the ASC half alone a purchase never reaches our DB and the buyer gets nothing, so verify with a real Sandbox purchase rather than the settings screen.
- [ ] TestFlight: purchase → `user_subscriptions` row goes `trialing`, and talk meters at 5 min/day
- [ ] Ship only builds that set `appAccountToken` (older builds can't attribute)

At launch day:

- [x] Paywall leaves survey mode — `BetaConfig` deleted 2026-08-18
- [ ] Web billing (post-launch, deliberately deferred 2026-08-23): code is ready as of 2026-09-02 — double-subscription 409 guard, 7-day trial parity, per-page currency (krw/usd via Stripe `currency_options`), `stripe-portal` self-serve cancel. Runbook: `web/README.md` § "Web billing" (Stripe products with krw currency_options + tax-inclusive, price IDs into `subscription_plans.stripe_price_id`, secrets, deploy 3 functions, portal config, Apple Services ID, then `BILLING.enabled`)
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
