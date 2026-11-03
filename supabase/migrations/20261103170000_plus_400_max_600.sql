-- ---------------------------------------------------------------------------
-- Plus 400 min, Max 600 min for new buyers (2026-11-03, founder decision).
--
-- Measured the same day with Cartesia's usage API (10-13..11-03, 22 days,
-- credits per voice set against the ledger's metered minutes): a talk minute
-- is ~600 TTS credits, at the Startup plan's $45/M overage $0.027, plus
-- $0.017–0.024 of LLM — ~$0.046 all in, the 10-27 figure confirmed. At that
-- cost Plus 450 loses $4.7 in Korea when fully used and Max 900 $8.9; nobody
-- paying is near either (the heaviest account talks ~260 min a period and
-- would reach ~440 with its scenes counted in minutes). Max 900 at ₩58,000
-- was a size nobody bought. The founder's shape: Plus 400 at the same price
-- (₩29,000 / $19.99, −$2.4 fully used in Korea), Max 600 at ₩45,000 / $34.99
-- (−$2.8) — a step the diligent learner can take instead of a wall. Prices
-- move in App Store Connect by hand (lowering needs no consent sheet).
--
-- Same shape as 20261027120000: every live Plus/Max row is stamped with the
-- size it was sold (450 / 900, or its own earlier stamp) BEFORE the catalog
-- moves, so only purchases from now on get the smaller pool. Scene counts
-- are untouched (new subscribers pay scenes in minutes since 10-19).
-- ---------------------------------------------------------------------------

update public.user_subscriptions s
   set monthly_seconds = p.monthly_seconds,
       talk_unlimited  = coalesce(p.talk_unlimited, false),
       monthly_scenes  = p.monthly_scenes
  from public.subscription_plans p
 where p.id = s.plan_id
   and p.tier in ('plus', 'max')
   and s.status in ('trialing', 'active', 'grace')
   and s.monthly_seconds is null;

update public.subscription_plans
   set monthly_seconds = 24000,   -- 400 min
       daily_seconds   = 800      -- descriptive: "about 13 min a day"
 where tier = 'plus';

update public.subscription_plans
   set monthly_seconds = 36000,   -- 600 min
       daily_seconds   = 1200     -- descriptive: "about 20 min a day"
 where tier = 'max';
