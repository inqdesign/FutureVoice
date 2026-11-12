-- The 100-day challenge package (2026-11-12, founder): paid ONCE on the web,
-- no renewal. The challengers' way in.
--
-- Stripe product nawana_challenge, three one-time Prices made by
-- scripts/stripe-challenge-package.sh, the web's monthly price times three:
--   light_challenge  $26.97   ₩40,500    €26.97   price_1UalftEwYewqhSDOEXpRKAHb
--   plus_challenge   $67.47   ₩78,000    €62.07   price_1UalftEwYewqhSDOfSpJmOXy
--   max_challenge    $94.47   ₩121,500   €107.97  price_1UalfuEwYewqhSDOKiKAeAfm
--
-- Same shape as max_annual (20261110250000): no App Store or Play product, so
-- the rows are is_active = false (no paywall lists them) and sold_on_web = true
-- (stripe-checkout sells them, in payment mode because period = 'challenge').
-- Each copies its monthly twin's pool, refilled monthly inside the 100 days by
-- billing_period_started_at's monthly anchor.
--
-- What a purchase writes (stripe-webhook): a user_subscriptions row with
-- source = 'stripe', NO stripe_subscription_id, cancel_at_period_end = true and
-- a period of 100 days. Stripe sends nothing when a one-time purchase runs
-- out, so the nightly sweep that ends coded comps ends these too.
--
-- The reward (founder, same day): each month kept earns one free month. It is
-- given by moving current_period_end forward on the same row.

insert into subscription_plans
  (id, tier, period, credits_per_cycle, apple_product_id, is_active, stripe_price_id,
   daily_seconds, daily_scenes, monthly_seconds, monthly_scenes, talk_unlimited,
   abuse_seconds, google_product_id, scene_talk_seconds, sold_on_web)
select v.id, p.tier, 'challenge', p.credits_per_cycle * 3, 'com.roro.futurevoice.' || v.id, false,
       v.price,
       p.daily_seconds, p.daily_scenes, p.monthly_seconds, p.monthly_scenes, p.talk_unlimited,
       p.abuse_seconds, null, p.scene_talk_seconds, true
  from (values
    ('light_challenge', 'light_monthly', 'price_1UalftEwYewqhSDOEXpRKAHb'),
    ('plus_challenge',  'plus_monthly',  'price_1UalftEwYewqhSDOfSpJmOXy'),
    ('max_challenge',   'max_monthly',   'price_1UalfuEwYewqhSDOKiKAeAfm')
  ) as v(id, twin, price)
  join subscription_plans p on p.id = v.twin
on conflict (id) do nothing;

create or replace function public.expire_comp_subscriptions()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_count  integer;
  v_once   integer;
  v_step   integer;
  v_guard  integer := 0;
begin
  -- 1. Standing comps: advance one month at a time until the period covers
  --    now. One step is the normal case (the sweep is nightly); the loop is
  --    for a sweep that did not run for a while. Bounded so a row with a
  --    corrupt date can never spin the job.
  loop
    update user_subscriptions
       set current_period_start = current_period_end,
           current_period_end   = current_period_end + interval '1 month',
           updated_at           = now()
     where source = 'comp'
       and status in ('active', 'trialing', 'grace')
       and cancel_at_period_end = false
       and current_period_end is not null
       and current_period_end < now();
    get diagnostics v_step = row_count;
    v_guard := v_guard + 1;
    exit when v_step = 0 or v_guard >= 120;
  end loop;

  -- 2. Coded comps end, as before.
  update user_subscriptions
     set status = 'expired', updated_at = now()
   where source = 'comp'
     and status in ('active', 'trialing', 'grace')
     and cancel_at_period_end = true
     and current_period_end is not null
     and current_period_end < now();
  get diagnostics v_count = row_count;

  -- 3. A package paid once on the web (the 100-day challenge) ends on its last
  --    day. It has no Stripe subscription, so no webhook will ever say so.
  update user_subscriptions
     set status = 'expired', updated_at = now()
   where source = 'stripe'
     and stripe_subscription_id is null
     and plan_id in (select id from subscription_plans where period = 'challenge')
     and status in ('active', 'trialing', 'grace')
     and current_period_end is not null
     and current_period_end < now();
  get diagnostics v_once = row_count;
  return v_count + v_once;
end;
$function$;
