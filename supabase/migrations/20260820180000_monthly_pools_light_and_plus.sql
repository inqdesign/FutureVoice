-- ---------------------------------------------------------------------------
-- One switch, made together: MONTHLY POOLS, and the tiers renamed
-- **Daily → Light** and **Unlimited → Plus**.
--
-- They are one migration because they are one decision and because splitting
-- them leaves a state where the old names are still in the enum while the new
-- meter is live — and a half-renamed tier is the thing that makes every later
-- reader hesitate.
--
-- ## Monthly pools
--
-- Light gets **150 minutes of talk and 60 Watch scenes per billing period**,
-- spent however the learner likes: all of it today, none of it for a fortnight.
-- There is no daily ceiling any more. "Five minutes a day" survives only as the
-- description of the size (150 / 30) that the plan card prints.
--
-- This replaces the rolling-week window (`20260820120000` → `140000` →
-- `160000`, all shipped earlier the same day), which was three migrations of
-- arithmetic to answer a question a data plan answers with one number. The
-- window was correct and nobody could explain it in a sentence; a monthly pool
-- is a sentence, and the model people already hold is a mobile data plan.
--
-- The argument that used to rule a monthly pool out was fill rate: a visible
-- monthly balance gets spent, and this tier's margin came from the allowance
-- going unspent. That argument is retired — see "Pricing principle" at the top
-- of docs/launch-billing.md. **We do not earn from people being unable to
-- spend what they bought; if fuller use doesn't pay, the price is what's
-- wrong.** What remains true, and is handled in the UI rather than here, is
-- that a month-long balance must not become a meter the learner watches: the
-- figure lives one tap away in Me, and the home shows a ring with no digits.
--
-- The period is the BILLING period (`current_period_start`), not the calendar
-- month: it is the month they actually paid for, and the only anchor that stays
-- right for someone who subscribed on the 20th. Accounts with no period on file
-- fall back to the calendar month.
--
-- The trial is PRO-RATED (7/30 of the pool ≈ 35 min, 14 scenes) rather than
-- given the month: a 7-day trial that can spend a full month's allowance is a
-- month of costs for an account that may never pay. That is not withholding
-- something bought — it is sizing a free sample to the length of the sample.
--
-- ## The names
--
-- Both old names stopped being true here. "Daily" named a unit that no longer
-- exists. "Unlimited" named something that was never true: that tier has always
-- had a fair-use ceiling (1800 min, 600 scenes a period), and we do not sell a
-- promise the meter doesn't keep.
--
-- Why the SIZE isn't the name ("월 150분", the data-plan move): the numbers are
-- still being tuned, and a name that must be re-registered with App Store
-- Connect every time an allowance moves is a name that will end up lying. The
-- card underneath states the size and reads it from `monthly_seconds`, so that
-- can never drift.
--
-- Why not Light/Heavy, which was the first instinct: PaywallView has carried a
-- note since it was written that the label must not grade the BUYER — "heavy
-- user" tells someone what they are, and "light" tells whoever chose the
-- smaller card that they are the small one. Light/Plus names the amount from
-- the product's side, which is the honest axis.
--
-- Product ids move with the names. That is only free because App Store Connect
-- has no products under the old ids yet (see the go-live checklist) — after
-- launch this would be impossible, an Apple product id being permanent once it
-- has sold.
-- ---------------------------------------------------------------------------

-- Renaming the enum's labels (rather than adding new ones) carries every
-- existing row along with it and needs no backfill.
alter type public.subscription_tier rename value 'daily' to 'light';
alter type public.subscription_tier rename value 'unlimited' to 'plus';

alter table public.subscription_plans
  add column if not exists monthly_seconds integer,
  add column if not exists monthly_scenes  integer;

comment on column public.subscription_plans.monthly_seconds is
  'Seconds of talk per BILLING PERIOD. This is what is enforced. '
  'daily_seconds survives only as the descriptive "N minutes a day" figure '
  '(monthly_seconds / 30) that the plan cards print — keep the two in step.';
comment on column public.subscription_plans.monthly_scenes is
  'Watch scenes per BILLING PERIOD. Enforced; daily_scenes is descriptive.';

-- Light: 5 min/day × 30 = 150 min, 2 scenes/day × 30 = 60.
update public.subscription_plans
   set monthly_seconds = 9000, monthly_scenes = 60
 where tier = 'light';
-- Plus: the same 30× of its old fair-use day. The number is now
-- printable: the tier no longer claims to be unlimited.
update public.subscription_plans
   set monthly_seconds = 108000, monthly_scenes = 600
 where tier = 'plus';

alter table public.subscription_plans
  alter column monthly_seconds set not null,
  alter column monthly_scenes  set not null;

-- The rolling week and everything that propped it up.
drop function if exists public.talk_window_cap(uuid, integer, integer);
alter table public.subscription_plans drop column if exists rollover_window_days;
alter table public.user_subscriptions drop column if exists started_at;

-- ---------------------------------------------------------------------------
-- Where this account's current period began. One definition, used by every
-- allowance below — two call sites resolving "this month" differently is the
-- drift the whole billing model keeps being rewritten to avoid.
-- ---------------------------------------------------------------------------
create or replace function public.billing_period_start(p_user_id uuid)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
           (select max(current_period_start)::date
              from user_subscriptions
             where user_id = p_user_id
               and status in ('trialing', 'active', 'grace')
               and current_period_start is not null
               and current_period_start <= now()),
           date_trunc('month', current_date)::date
         );
$$;

revoke all on function public.billing_period_start(uuid) from public, anon, authenticated;
grant execute on function public.billing_period_start(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- The capped meter, now a monthly pool.
-- ---------------------------------------------------------------------------
create or replace function public.consume_metered_seconds(
  p_user_id uuid,
  p_seconds integer,
  p_pool text,
  p_action text,
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_today   bigint;
  v_period  bigint;
  v_scenes  bigint;
  v_start   date;
  v_cap     integer;
  v_trial   boolean := false;
  v_balance integer;
begin
  if p_seconds < 0 or p_seconds > 3600 then
    raise exception 'p_seconds out of range';
  end if;
  if p_pool not in ('talk_seconds', 'scene_seconds', 'scene_counted') then
    raise exception 'unsupported pool %', p_pool;
  end if;

  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_balance from user_credits where user_id = p_user_id;
    select coalesce(sum(chars), 0) into v_today from tts_char_pool
     where user_id = p_user_id and day = current_date
       and action in ('talk_seconds', 'scene_seconds');
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today);
  end if;

  if p_seconds > 0 then
    insert into tts_char_pool (user_id, day, action, chars)
    values (p_user_id, current_date, p_pool, p_seconds)
    on conflict (user_id, day, action) do update
      set chars = tts_char_pool.chars + excluded.chars,
          updated_at = now();
  end if;

  -- 'scene_counted' is deliberately absent from both sums: those seconds were
  -- paid for with a scene count. 'scene_seconds' stays in so that an
  -- un-updated client keeps today's economics.
  select coalesce(sum(chars), 0) into v_today from tts_char_pool
   where user_id = p_user_id and day = current_date
     and action in ('talk_seconds', 'scene_seconds');

  select coalesce(sum(chars), 0) into v_scenes from tts_char_pool
   where user_id = p_user_id and day = current_date
     and action in ('scene_seconds', 'scene_counted');

  -- The trial is metered at the LIGHT tier's pool, pro-rated to the sample's
  -- length, whatever plan is being trialed.
  select s.status = 'trialing',
         case when s.status = 'trialing'
              then coalesce((select min(monthly_seconds) from subscription_plans
                              where tier = 'light'), p.monthly_seconds) * 7 / 30
              else p.monthly_seconds end
    into v_trial, v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  if v_cap is not null then
    v_start := public.billing_period_start(p_user_id);
    select coalesce(sum(chars), 0) into v_period from tts_char_pool
     where user_id = p_user_id and day >= v_start
       and action in ('talk_seconds', 'scene_seconds');

    if v_period > v_cap then
      raise exception 'DAILY_CAP_REACHED' using errcode = 'P0005';
    end if;
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                                    'seconds_period', v_period, 'period_start', v_start,
                                    'scene_seconds_today', v_scenes, 'pool', p_pool,
                                    'covered_by', case when v_trial then 'trial' else 'plan' end));
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today,
                              'seconds_period', v_period,
                              'monthly_cap', v_cap, 'daily_cap', v_cap,
                              'period_start', v_start,
                              'scene_seconds_today', v_scenes,
                              'covered_by', case when v_trial then 'trial' else 'plan' end);
  end if;

  v_balance := public.charge_credits(
    p_user_id => p_user_id,
    p_credits => p_seconds,
    p_action  => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                            'pool', p_pool, 'covered_by', 'balance'));
  return jsonb_build_object('balance', v_balance, 'charged', p_seconds,
                            'seconds_today', v_today,
                            'scene_seconds_today', v_scenes,
                            'covered_by', 'balance');
end;
$function$;

revoke all on function public.consume_metered_seconds(uuid, integer, text, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.consume_metered_seconds(uuid, integer, text, text, text, text, jsonb)
  to service_role;

-- ---------------------------------------------------------------------------
-- Watch scenes: the same pool shape, counted per period.
-- ---------------------------------------------------------------------------
create or replace function public.begin_scene_play(
  p_user_id uuid,
  p_scene_key text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cap   integer;
  v_used  integer;
  v_start date;
  v_fresh boolean;
begin
  if p_user_id is null or coalesce(p_scene_key, '') = '' then
    raise exception 'begin_scene_play: user and scene key required';
  end if;

  select case when s.status = 'trialing'
              then coalesce((select min(monthly_scenes) from subscription_plans
                              where tier = 'light'), p.monthly_scenes) * 7 / 30
              else p.monthly_scenes end
    into v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  -- No entitlement: scenes stay priced in seconds out of the balance, so the
  -- caller must not claim a count.
  if v_cap is null then
    return jsonb_build_object('allowed', true, 'metered_by', 'balance',
                              'counted', false);
  end if;

  insert into scene_plays (user_id, day, scene_key)
  values (p_user_id, current_date, p_scene_key)
  on conflict do nothing;
  v_fresh := found;

  v_start := public.billing_period_start(p_user_id);
  select count(*) into v_used
    from scene_plays
   where user_id = p_user_id and day >= v_start;

  -- Only a NEWLY claimed slot can push past the cap; a line from a scene
  -- already in progress must never be cut off half way through.
  if v_fresh and v_used > v_cap then
    raise exception 'SCENE_CAP_REACHED' using errcode = 'P0006';
  end if;

  return jsonb_build_object('allowed', true, 'metered_by', 'scenes',
                            'counted', true,
                            'used', v_used, 'cap', v_cap, 'fresh', v_fresh);
end;
$$;

revoke all on function public.begin_scene_play(uuid, text) from public, anon, authenticated;
grant execute on function public.begin_scene_play(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- What the app reads about its own allowances. Both report the PERIOD, and
-- both report when it resets, because "150 minutes" means nothing without
-- "until the 14th".
-- ---------------------------------------------------------------------------
create or replace function public.talk_allowance()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_cap   integer;
  v_used  integer;
  v_start date;
  v_end   date;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select case when s.status = 'trialing'
              then coalesce((select min(monthly_seconds) from subscription_plans
                              where tier = 'light'), p.monthly_seconds) * 7 / 30
              else p.monthly_seconds end,
         s.current_period_end::date
    into v_cap, v_end
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid
     and s.status in ('trialing', 'active', 'grace')
   order by s.current_period_start desc nulls last
   limit 1;

  if v_cap is null then
    return jsonb_build_object('used', 0, 'cap', null, 'period_start', null,
                              'period_end', null, 'metered_by', 'balance');
  end if;

  v_start := public.billing_period_start(v_uid);
  select coalesce(sum(chars), 0)::integer into v_used
    from tts_char_pool
   where user_id = v_uid and day >= v_start
     and action in ('talk_seconds', 'scene_seconds');

  return jsonb_build_object('used', v_used, 'cap', v_cap,
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'plan');
end;
$$;

revoke all on function public.talk_allowance() from public, anon;
grant execute on function public.talk_allowance() to authenticated, service_role;

create or replace function public.scene_allowance()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_cap   integer;
  v_used  integer;
  v_start date;
  v_end   date;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select case when s.status = 'trialing'
              then coalesce((select min(monthly_scenes) from subscription_plans
                              where tier = 'light'), p.monthly_scenes) * 7 / 30
              else p.monthly_scenes end,
         s.current_period_end::date
    into v_cap, v_end
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid
     and s.status in ('trialing', 'active', 'grace')
   order by s.current_period_start desc nulls last
   limit 1;

  if v_cap is null then
    return jsonb_build_object('used', 0, 'cap', null, 'period_start', null,
                              'period_end', null, 'metered_by', 'balance');
  end if;

  v_start := public.billing_period_start(v_uid);
  select count(*) into v_used from scene_plays
   where user_id = v_uid and day >= v_start;

  return jsonb_build_object('used', v_used, 'cap', v_cap,
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'scenes');
end;
$$;

revoke all on function public.scene_allowance() from public, anon;
grant execute on function public.scene_allowance() to authenticated, service_role;

-- New rows first: `user_subscriptions.plan_id` is a FK with NO ACTION, so the
-- old rows can only go once nothing points at them.
insert into public.subscription_plans
  (id, tier, period, credits_per_cycle, apple_product_id, is_active,
   daily_seconds, daily_scenes, monthly_seconds, monthly_scenes)
values
  ('light_monthly', 'light', 'monthly', 500,  'com.roro.futurevoice.light_monthly',  true,  300,  2,   9000,  60),
  ('light_annual',  'light', 'annual',  6000, 'com.roro.futurevoice.light_annual',   true,  300,  2,   9000,  60),
  ('plus_monthly',  'plus',  'monthly', 1500, 'com.roro.futurevoice.plus_monthly',   true,  3600, 20,  108000, 600),
  ('plus_annual',   'plus',  'annual',  18000,'com.roro.futurevoice.plus_annual',    true,  3600, 20,  108000, 600)
on conflict (id) do nothing;

-- Existing subscribers keep everything except the name of what they hold.
update public.user_subscriptions set plan_id = 'light_monthly' where plan_id = 'daily_monthly';
update public.user_subscriptions set plan_id = 'light_annual'  where plan_id = 'daily_annual';
update public.user_subscriptions set plan_id = 'plus_monthly'  where plan_id = 'unlimited_monthly';
update public.user_subscriptions set plan_id = 'plus_annual'   where plan_id = 'unlimited_annual';
-- The weekly SKUs were switched off in 20260811190000 and never sold; there is
-- nothing to carry forward, but be safe about it.
update public.user_subscriptions set plan_id = 'light_monthly' where plan_id = 'daily_weekly';
update public.user_subscriptions set plan_id = 'plus_monthly'  where plan_id = 'unlimited_weekly';

delete from public.subscription_plans
 where id in ('daily_monthly', 'daily_annual', 'daily_weekly',
              'unlimited_monthly', 'unlimited_annual', 'unlimited_weekly');
