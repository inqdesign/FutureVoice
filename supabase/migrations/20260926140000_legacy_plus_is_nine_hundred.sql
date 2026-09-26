-- ---------------------------------------------------------------------------
-- The Plus subscriptions sold before the bounded plans get 900 min + 60
-- scenes, instead of no ceiling at all (2026-09-26, founder decision).
--
-- `20260926110000` stamped them with what they were sold — uncapped talk and
-- 120 scenes — which keeps the promise and keeps the tail risk with it: the
-- only stop on those rows is `abuse_seconds` (3,000 min = $90 of talk on a
-- $19.99 subscription, $16.99 net), and the fair-use flag at 1,800 min is a
-- flag, not a wall. 900 minutes is the middle: three times the new Plus pool,
-- a bound at −$17 worst case instead of −$73, and nine times what the
-- heaviest of them has ever talked.
--
--   sold (until today)   uncapped talk        120 scenes
--   now                  900 min (54,000 s)    60 scenes
--   new buyers           300 min (18,000 s)    60 scenes
--
-- This IS a reduction, which is the thing this app does not normally do to
-- someone already paying, so it is recorded plainly: the three live rows have
-- used 108, 93 and 5 minutes and 0, 28 and 1 scenes in September — nobody is
-- within 8× of the talk ceiling or half of the scene count, so no session
-- that would have run will now stop. What does change for them is the SCREEN:
-- with a cap on the row the app draws the Home ring, says "N of 900 min" in
-- Me, and offers minute packs if they ever reach it. That is the honest
-- version of what they hold, and they were never shown a number before.
--
-- Trials are untouched — `20260926130000` put them on today's plan, which is
-- what they convert into.
--
-- Known hole, unchanged by this file and not worth machinery for three rows:
-- the stamp survives a plan CHANGE inside the group, so a legacy Plus that
-- downgrades to Light would keep 900 minutes on a $9.99 plan. Nothing rewrites
-- the stamp on a plan change (neither `apple-webhook` nor `apple-claim` writes
-- these columns — that is what makes the stamp survive renewals). Watch it if
-- anyone downgrades; the fix is to clear the stamp when `plan_id` moves.
-- ---------------------------------------------------------------------------

update public.user_subscriptions
   set monthly_seconds = 54000,   -- 900 min
       talk_unlimited  = false,
       monthly_scenes  = 60
 where status in ('active', 'grace')
   and coalesce(talk_unlimited, false);
