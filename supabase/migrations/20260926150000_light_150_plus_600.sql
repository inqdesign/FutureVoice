-- ---------------------------------------------------------------------------
-- The two products settle: Light 150 min + 10 scenes, Plus 600 min + 30
-- scenes (2026-09-26, founder decision — the last of the day's four passes).
--
-- `20260926110000` cut Light to 100 min to pay for its scenes; the founder's
-- answer is better — keep the 150 minutes people bought the plan for and cut
-- the SCENES, which is where the money actually goes. A scene costs $0.12
-- against a talk minute's $0.03, so ten scenes buy back forty minutes.
--
--                      talk           scenes     full-use cost   net     US
--   Light  $9.99       150 min        10         $4.5 + $1.2     $8.49   +$2.8 (33%)
--   Plus  $19.99       600 min        30         $18  + $3.6    $16.99   −$4.6
--
-- Light is the healthiest it has ever been, and the ceiling is nowhere near
-- anyone: the heaviest Light account has played FOUR scenes in a month, and
-- the two accounts that ever passed ten scenes in thirty days were both Plus.
-- A Light learner who does hit it has somewhere to go — Plus — which is what
-- makes ten defensible where it would not be on the top tier.
--
-- Plus loses $4.6 fully used, deliberately and with the number written down:
-- 600 min is "20 minutes a day", the size the founder wants the tier to
-- mean, and $16.99 of net buys 446 minutes beside 30 scenes. The exposure is
-- bounded and small (three live Plus rows, the heaviest of which talked 108
-- minutes and played 0 scenes in September, i.e. +$10 of margin today). If
-- real Plus months ever approach the pool, the fix is the price — that is
-- the pricing principle, and this is the case it was written for.
--
-- TWO PRODUCTS FOR NOW: the minute pack stays unsold. `talk_topups` keeps
-- its row and `apple-topup` stays deployed, but no consumable is created in
-- App Store Connect, and `TalkTopUpButton` draws nothing without a live
-- price — so the app is a two-subscription app with no code change. The
-- consequence to keep in mind: a Plus learner who empties the pool has
-- nothing to buy, which is why Plus is the generous side of this pair.
--
-- Grandfathering is untouched: the Light row keeps 150 + 60, the legacy Plus
-- rows keep whatever `20260926140000` left them (900 + 60), and trials are
-- re-stamped below with today's plan, since that is what they convert into.
-- ---------------------------------------------------------------------------

update public.subscription_plans
   set monthly_seconds = 9000,    -- 150 min
       daily_seconds   = 300,     -- descriptive: "about 5 min a day"
       monthly_scenes  = 10,
       daily_scenes    = 0        -- descriptive only; nothing renders it
 where tier = 'light';

update public.subscription_plans
   set monthly_seconds = 36000,   -- 600 min
       daily_seconds   = 1200,    -- descriptive: "about 20 min a day"
       monthly_scenes  = 30,
       daily_scenes    = 1,
       talk_unlimited  = false
 where tier = 'plus';

-- A trial converts into the plan as it is sold TODAY (the rule from
-- `20260926130000`, re-applied because the catalog moved under it).
update public.user_subscriptions s
   set monthly_seconds = p.monthly_seconds,
       talk_unlimited  = coalesce(p.talk_unlimited, false),
       monthly_scenes  = p.monthly_scenes
  from public.subscription_plans p
 where p.id = s.plan_id
   and s.status = 'trialing';
