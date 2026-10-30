-- ---------------------------------------------------------------------------
-- Plus 600 → 450 min, Max 1,200 → 900 min, for NEW buyers (2026-10-27,
-- founder decision). Prices unchanged.
--
-- Re-measured the same day (10-21..26, after the call reply moved to Claude
-- Haiku): a talk minute costs ~$0.046 all in (Gemini from the billing
-- console minus Dear RoRo's image SKUs, Claude from the ledger, Cartesia
-- estimated). Fully used:
--
--                      price            net      before (600/1200)  after
--   Plus  450 min      $24.99 / ₩29,000  $21.2 / $16.0   −$6.4 / −$11.6   +$0.5 / −$4.7
--   Max   900 min      $49.99 / ₩58,000  $42.5 / $32.5   −$12.7 / −$22.7  +$1.1 / −$8.9
--
-- Why the pool and not the price: no new paid subscription since 09-28, and
-- the price is the number on the paywall; the pool is a figure nobody paying
-- today comes near (heaviest paying account ~400 min a period). Max keeps
-- "twice Plus, at twice its price", so the bigger plan is never the dearer
-- minute. Light (150 min, +$1.4 fully used) is untouched.
--
-- NOBODY WHO ALREADY BOUGHT IS TOUCHED. Every live Plus/Max row without a
-- stamp is stamped with what it was sold (600 min + 30 scenes) BEFORE the
-- catalog moves; rows already stamped (the legacy 900 rows, the annual
-- uncapped row) keep their stamp. A lapsed row is not stamped — coming back
-- later is buying today's plan. A plan change still clears the stamp
-- (`20261012140000`), as it should.
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
   set monthly_seconds = 27000,   -- 450 min
       daily_seconds   = 900      -- descriptive: "about 15 min a day"
 where tier = 'plus';

update public.subscription_plans
   set monthly_seconds = 54000,   -- 900 min
       daily_seconds   = 1800     -- descriptive: "about 30 min a day"
 where tier = 'max';
