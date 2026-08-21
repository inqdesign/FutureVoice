-- ---------------------------------------------------------------------------
-- Carry-over becomes a ROLLING WEEK, and stops double-spending its own days.
--
-- `20260820120000_talk_rollover_bank` (this morning) computed today's extra as
-- "the unused seconds of the last N days". It reads correctly and is wrong:
-- nothing DEBITS a day once its unused seconds have been drawn, so every idle
-- day is re-counted by every window that still contains it.
--
--   Wed/Thu/Fri idle, then Sat 20 min  → fair: Wed+Thu+Fri+Sat = 20 min ✓
--   Sun's window is Thu/Fri/Sat        → Thu and Fri are "unused" AGAIN
--                                      → Sun gets 15 min, from days already spent
--   Wed…Sun is 25 min of allowance, and 35 min came out of it (+40%).
--
-- The fix is to stop modelling a bank at all. A bank has to be debited to be
-- correct, which means storing a balance; a WINDOW BUDGET needs no balance
-- because the usage rows already are the ledger:
--
--     today's cap = window_days × daily_seconds − Σ used over the last (window_days - 1) days
--
-- No total over any `window_days` stretch can exceed `window_days × daily`,
-- by construction — spending shows up in every window that contains it, so it
-- cannot be counted twice. And for someone who talks their 5 minutes every
-- day it evaluates to exactly 5, so the common case is untouched.
--
-- The window is a WEEK (7 days on Daily), which is the unit the learner
-- actually plans in: a week where the only free evening is Saturday now buys
-- a 35-minute Saturday. `rollover_max_seconds` is dropped — a cap in seconds
-- and a window in days are two ways to say the same thing, and keeping both
-- invites them to disagree.
--
-- Cost: the monthly ceiling is what it always was (~150 min on Daily), and it
-- is now genuinely a ceiling rather than an estimate. What rises is the PEAK
-- of one day, 5 min → 35 min. Re-check that peak, not the monthly figure,
-- before widening the window.
-- ---------------------------------------------------------------------------

alter table public.subscription_plans
  add column if not exists rollover_window_days integer not null default 1;

comment on column public.subscription_plans.rollover_window_days is
  'Days in the rolling talk budget. Today''s cap is window_days x daily_seconds '
  'minus what was used over the preceding window_days-1 days. 1 = no carry-over.';

-- Daily: a week, so an unused weekday is still there at the weekend.
-- Unlimited: 1 — 60 min/day is already past any single sitting, and a weekly
-- budget on top of a fair-use ceiling would just be a bigger fair-use ceiling.
update public.subscription_plans set rollover_window_days = 7 where tier = 'daily';
update public.subscription_plans set rollover_window_days = 1 where tier = 'unlimited';

drop function if exists public.talk_bank_seconds(uuid, integer, integer);

-- ---------------------------------------------------------------------------
-- Today's ceiling for one account.
--
-- Days with no pool row simply contribute nothing to the sum, so the window is
-- summed rather than generated — unlike the bank, this formula needs the
-- USAGE, not the absence of it.
--
-- `p_daily` is today's plan value applied across the window: a plan change
-- inside seven days is rare, and the alternative is storing the allowance per
-- day, which is a table for an edge case nobody would notice.
--
-- Server-only, like every other function taking a user id as an argument
-- (20260814140000_billing_rpcs_server_only).
-- ---------------------------------------------------------------------------
create or replace function public.talk_window_cap(
  p_user_id uuid,
  p_daily   integer,
  p_days    integer
) returns integer
language sql
stable
security definer
set search_path = public
as $$
  select greatest(0,
           greatest(1, coalesce(p_days, 1)) * p_daily
           - coalesce((
               select sum(t.chars)
                 from tts_char_pool t
                where t.user_id = p_user_id
                  -- Strictly BEFORE today: today's own usage is what this
                  -- ceiling is compared against, not part of it.
                  and t.day >= current_date - (greatest(1, coalesce(p_days, 1)) - 1)
                  and t.day <  current_date
                  -- The same two pools the cap is measured against, so a day
                  -- counts as used by exactly what was billed to it.
                  and t.action in ('talk_seconds', 'scene_seconds')
             ), 0)
         )::integer;
$$;

revoke all on function public.talk_window_cap(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.talk_window_cap(uuid, integer, integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- The capped meter, now spending against the window budget.
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
  v_scenes  bigint;
  v_base    integer;
  v_days    integer;
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

  -- The capped meter. 'scene_counted' is deliberately absent: those seconds
  -- were paid for with a scene count. 'scene_seconds' stays in so that an
  -- un-updated client keeps today's economics.
  select coalesce(sum(chars), 0) into v_today from tts_char_pool
   where user_id = p_user_id and day = current_date
     and action in ('talk_seconds', 'scene_seconds');

  select coalesce(sum(chars), 0) into v_scenes from tts_char_pool
   where user_id = p_user_id and day = current_date
     and action in ('scene_seconds', 'scene_counted');

  -- The trial is metered at the DAILY tier whatever plan it trials —
  -- including that tier's window, so a trial is exactly the thing being sold.
  select s.status = 'trialing',
         case when s.status = 'trialing'
              then coalesce((select min(daily_seconds) from subscription_plans
                              where tier = 'daily'), p.daily_seconds)
              else p.daily_seconds end,
         case when s.status = 'trialing'
              then coalesce((select min(rollover_window_days) from subscription_plans
                              where tier = 'daily'), p.rollover_window_days)
              else p.rollover_window_days end
    into v_trial, v_base, v_days
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  if v_base is not null then
    v_cap := public.talk_window_cap(p_user_id, v_base, coalesce(v_days, 1));

    if v_today > v_cap then
      raise exception 'DAILY_CAP_REACHED' using errcode = 'P0005';
    end if;
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                                    'scene_seconds_today', v_scenes,
                                    'pool', p_pool,
                                    'daily_base', v_base, 'window_days', v_days,
                                    'covered_by', case when v_trial then 'trial' else 'plan' end));
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today, 'daily_cap', v_cap,
                              'daily_base', v_base,
                              'bank', greatest(0, v_cap - v_base),
                              'window_days', v_days,
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
-- What the app reads about its own talk allowance. `bank` survives as a
-- DERIVED figure (cap − the plan's own day) because that is the number the
-- copy explains — "5 from your plan plus 30 you didn't use" — and deriving it
-- here keeps the client from computing an allowance a second time.
-- ---------------------------------------------------------------------------
create or replace function public.talk_allowance()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_base integer;
  v_days integer;
  v_cap  integer;
  v_used integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select case when s.status = 'trialing'
              then coalesce((select min(daily_seconds) from subscription_plans
                              where tier = 'daily'), p.daily_seconds)
              else p.daily_seconds end,
         case when s.status = 'trialing'
              then coalesce((select min(rollover_window_days) from subscription_plans
                              where tier = 'daily'), p.rollover_window_days)
              else p.rollover_window_days end
    into v_base, v_days
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid
     and s.status in ('trialing', 'active', 'grace');

  select coalesce(sum(chars), 0)::integer into v_used
    from tts_char_pool
   where user_id = v_uid and day = current_date
     and action in ('talk_seconds', 'scene_seconds');

  if v_base is null then
    -- No plan: talk comes out of the one-time balance, so there is no daily
    -- cap to report and the client keeps showing the pool.
    return jsonb_build_object('used', v_used, 'base', null, 'bank', 0,
                              'cap', null, 'window_days', 1,
                              'metered_by', 'balance');
  end if;

  v_cap := public.talk_window_cap(v_uid, v_base, coalesce(v_days, 1));

  return jsonb_build_object('used', v_used,
                            'base', v_base,
                            'bank', greatest(0, v_cap - v_base),
                            'cap', v_cap,
                            'window_days', coalesce(v_days, 1),
                            'metered_by', 'plan');
end;
$$;

revoke all on function public.talk_allowance() from public, anon;
grant execute on function public.talk_allowance() to authenticated, service_role;

alter table public.subscription_plans drop column if exists rollover_max_seconds;
