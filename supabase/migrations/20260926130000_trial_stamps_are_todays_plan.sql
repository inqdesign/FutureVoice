-- ---------------------------------------------------------------------------
-- A trial converts into the plan as it is sold TODAY (2026-09-26, same day
-- as the bounded plans).
--
-- `20260926110000` stamped the two rows still trialing with Light's month
-- figure (9000 s), because that is what their 7/30 pro-rate is computed
-- from — the same rule the scene stamp used on 2026-09-25. Right for the
-- trial, wrong the moment it converts: the stamp outlives the trial, the
-- webhook's upsert never touches it, and the non-trial branch of
-- `consume_metered_seconds` would then read 9000 s → a Plus subscriber
-- paying $19.99 with a 150-minute cap. Neither what they were sold nor what
-- the catalog says.
--
-- So a trialing row carries the CURRENT plan's figures instead
-- (Plus: 18000 s, 60 scenes, capped). During the trial the 7/30 pro-rate
-- reads them — 70 min instead of 35 for the last day or two, which takes
-- nothing from anyone (one of the two had already been topped up by hand)
-- — and on conversion the row simply is a Plus bought today. The
-- grandfathering rule is untouched: it is about what an ACTIVE row was
-- sold, and these two were sold a trial of whatever Plus is when it
-- converts.
--
-- Trials cannot start any more once the intro offers are deleted, so this
-- is the last time the trialing stamp matters; the rule is recorded in
-- CLAUDE.md so a future re-stamp doesn't repeat it.
-- ---------------------------------------------------------------------------

update public.user_subscriptions s
   set monthly_seconds = p.monthly_seconds,
       talk_unlimited  = coalesce(p.talk_unlimited, false),
       monthly_scenes  = p.monthly_scenes
  from public.subscription_plans p
 where p.id = s.plan_id
   and s.status = 'trialing';
