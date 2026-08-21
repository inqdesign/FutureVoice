-- ---------------------------------------------------------------------------
-- Unused talk time carries over, up to a few days.
--
-- The Daily tier buys 300 s a day and resets at midnight UTC. That is right
-- for the product — the whole app is a daily-call habit, and a per-day reset
-- is what lets it say "today" instead of showing a month-long balance ticking
-- down — but it was wrong for anyone whose week isn't shaped like that. A
-- learner who only wants Saturday got 5 minutes on Saturday and lost the other
-- six days entirely: not "some waste", but a hard 5-minute ceiling on the one
-- day they actually turned up.
--
-- A MONTHLY pool was the obvious alternative and was rejected on the numbers:
-- 300 s × 30 = 150 min either way, so the ceiling is identical, but the FILL
-- RATE is not. Daily's margin comes entirely from under-use (docs/launch-billing.md:
-- "a maxed Daily subscriber lands near €7.10 net", against ~€7.10 of net
-- revenue), and a visible monthly balance is spent because it is visible. It
-- would also put back the taximeter the 2026-08-11 revision existed to remove,
-- and let someone burn the month in two days and go dark for twenty-eight.
--
-- So: a BANK, not a budget. Unused seconds from the last few days are added to
-- today's allowance, clamped by `rollover_max_seconds`.
--
--     today's allowance = daily_seconds + min(rollover_max_seconds,
--                            Σ over the last N days of unused seconds)
--     N = rollover_max_seconds / daily_seconds   (3 days on Daily)
--
-- Two properties make this cheap and safe:
--
--   * It REDISTRIBUTES, it never adds. Over any window, the total a subscriber
--     can spend is what it always was — the bank can only be filled by a day
--     that went unspent. That is also why the trial needs no special guard.
--   * The window rolls, so absence doesn't accumulate. A month away banks three
--     days, not thirty, and one sitting is bounded by daily + max (20 min on
--     Daily) — the peak that decides worst-case cost per call.
--
-- The one place seconds ARE created from nothing is a brand-new subscriber,
-- whose first day arrives with a full bank from days they weren't paying for.
-- That is bounded by `rollover_max_seconds` (15 min, ~€0.7 of talk), happens
-- once, and lands exactly where a generous day is worth the most. Not worth
-- engineering a start-date guard that would also have to survive renewals.
-- ---------------------------------------------------------------------------

alter table public.subscription_plans
  add column if not exists rollover_max_seconds integer not null default 0;

comment on column public.subscription_plans.rollover_max_seconds is
  'Seconds of unused daily allowance that can carry into today, at most. '
  '0 = no rollover. The lookback window is this ÷ daily_seconds days.';

-- Daily: three days' worth, so a weekend learner gets a 20-minute Saturday.
-- Unlimited: none — 3600 s/day is already past any single sitting, and banking
-- on top of it would only widen a fair-use guard that exists to be a ceiling.
update public.subscription_plans set rollover_max_seconds = 900  where tier = 'daily';
update public.subscription_plans set rollover_max_seconds = 0    where tier = 'unlimited';

-- ---------------------------------------------------------------------------
-- The bank itself.
--
-- A day with no pool row is fully unused, so the window is generated rather
-- than summed over existing rows. Today is excluded — it is the day being
-- spent, not a day that went unspent.
--
-- `p_daily` is today's plan value applied to every day in the window: plan
-- changes inside a 3-day window are rare and the alternative is storing the
-- allowance per day, which is a table for an edge case nobody would notice.
--
-- Server-only, like every other function that takes a user id as an argument
-- (see 20260814140000_billing_rpcs_server_only).
-- ---------------------------------------------------------------------------
create or replace function public.talk_bank_seconds(
  p_user_id uuid,
  p_daily   integer,
  p_max     integer
) returns integer
language sql
stable
security definer
set search_path = public
as $$
  select least(
           coalesce(p_max, 0),
           coalesce(sum(greatest(0, p_daily - coalesce(u.used, 0))), 0)
         )::integer
    from generate_series(
           current_date - greatest(1, coalesce(p_max, 0) / greatest(1, p_daily)),
           current_date - 1,
           interval '1 day'
         ) as d(day)
    left join lateral (
      select coalesce(sum(t.chars), 0)::integer as used
        from tts_char_pool t
       where t.user_id = p_user_id
         and t.day = d.day::date
         -- The same two pools the cap is measured against below, so a day
         -- counts as "used" by exactly what would have been billed to it.
         and t.action in ('talk_seconds', 'scene_seconds')
    ) u on true
   where coalesce(p_max, 0) > 0;
$$;

revoke all on function public.talk_bank_seconds(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.talk_bank_seconds(uuid, integer, integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- The capped meter now spends `daily_seconds + bank`.
--
-- Unchanged from 20260814100000 apart from that: the pools it counts, the
-- trial's Daily-tier metering, the ledger row and the balance fall-through for
-- accounts with no plan are all as they were. The returned payload gains
-- `daily_base` and `bank` so the client can SAY where today's number came from
-- — a bigger allowance that appears without explanation is its own confusion.
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
  v_today    bigint;
  v_scenes   bigint;
  v_base     integer;
  v_rollover integer;
  v_bank     integer := 0;
  v_cap      integer;
  v_trial    boolean := false;
  v_balance  integer;
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

  -- The trial is metered at the DAILY tier whatever plan it trials — including
  -- that tier's rollover, so a trial behaves exactly like the thing being sold.
  select s.status = 'trialing',
         case when s.status = 'trialing'
              then coalesce((select min(daily_seconds) from subscription_plans
                              where tier = 'daily'), p.daily_seconds)
              else p.daily_seconds end,
         case when s.status = 'trialing'
              then coalesce((select min(rollover_max_seconds) from subscription_plans
                              where tier = 'daily'), p.rollover_max_seconds)
              else p.rollover_max_seconds end
    into v_trial, v_base, v_rollover
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  if v_base is not null then
    v_bank := public.talk_bank_seconds(p_user_id, v_base, coalesce(v_rollover, 0));
    v_cap  := v_base + v_bank;

    if v_today > v_cap then
      raise exception 'DAILY_CAP_REACHED' using errcode = 'P0005';
    end if;
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                                    'scene_seconds_today', v_scenes,
                                    'pool', p_pool,
                                    'daily_base', v_base, 'bank', v_bank,
                                    'covered_by', case when v_trial then 'trial' else 'plan' end));
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today, 'daily_cap', v_cap,
                              'daily_base', v_base, 'bank', v_bank,
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
-- What the app is allowed to ask about its OWN talk allowance.
--
-- Mirrors `scene_allowance()`: no user argument (it reads auth.uid()), so it
-- keeps a client grant. The client used to compute this itself from
-- `subscription_plans.daily_seconds` + a raw `tts_char_pool` read, which was
-- fine while the cap was one column and is not fine now — the bank is derived,
-- and two implementations of a number the learner is shown would drift.
-- ---------------------------------------------------------------------------
create or replace function public.talk_allowance()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_base     integer;
  v_rollover integer;
  v_bank     integer := 0;
  v_used     integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select case when s.status = 'trialing'
              then coalesce((select min(daily_seconds) from subscription_plans
                              where tier = 'daily'), p.daily_seconds)
              else p.daily_seconds end,
         case when s.status = 'trialing'
              then coalesce((select min(rollover_max_seconds) from subscription_plans
                              where tier = 'daily'), p.rollover_max_seconds)
              else p.rollover_max_seconds end
    into v_base, v_rollover
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
                              'cap', null, 'rollover_max', 0,
                              'metered_by', 'balance');
  end if;

  v_bank := public.talk_bank_seconds(v_uid, v_base, coalesce(v_rollover, 0));

  return jsonb_build_object('used', v_used,
                            'base', v_base,
                            'bank', v_bank,
                            'cap', v_base + v_bank,
                            'rollover_max', coalesce(v_rollover, 0),
                            'metered_by', 'plan');
end;
$$;

revoke all on function public.talk_allowance() from public, anon;
grant execute on function public.talk_allowance() to authenticated, service_role;
