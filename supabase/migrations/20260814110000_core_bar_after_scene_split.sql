-- The Core's daily bar, re-derived now that Watch left the talk meter.
--
-- 20260813120000 set `daily_bar_seconds` to 180 and justified it like this:
-- the Daily tier buys 300 s/day, talk and Watch scenes SHARED that pool, so a
-- bar near 300 was unreachable for anyone who also watched anything (one
-- 60 s scene left only 240 s of talk). 180 was the number that left room for
-- two scenes.
--
-- 20260814100000 removed that constraint entirely: scenes are metered by
-- COUNT against `daily_scenes`, and talk has all 300 s to itself. The old
-- reasoning no longer holds and the old number is no longer the answer.
--
-- The bar still has to sit BELOW the allowance, for a different and smaller
-- reason: slack. At exactly 300 a learner must spend their whole day's talk,
-- to the second, on 28 of 30 days — a call that ends at 4 min 52 s fails the
-- day, and a couple of near misses lose the month. 240 s asks for four
-- minutes of talking and leaves a minute of room for a call that runs short.
--
-- Watch still does not count toward the bar, and now that is a decision
-- rather than an accident: the Core is about speaking. `core_daily_activity`
-- reads `talk_seconds` alone, so neither the legacy `scene_seconds` pool nor
-- the new `scene_counted` one can move a learner toward a seat.
--
-- NOTE ON CONFIDENCE. This number is still derived from the plan's shape, not
-- from behaviour: on 2026-08-14 only one account emits `talk_seconds` at all,
-- because `TalkMeter` shipped three days ago and is not in any tester build.
-- Once a build with it is out and two weeks of real days exist, revisit with
-- "how many minutes does a Daily subscriber actually talk?" in hand. Until
-- then 240 is the defensible value, not the measured one.

update public.core_club_config
   set daily_bar_seconds = 240,
       updated_at = now()
 where daily_bar_seconds = 180;
