-- The Core stops paying anything.
--
-- It was designed with a reward: a seated member got `bonus_seconds` added to
-- that day's talk cap. Two problems, and the second one is the real one.
--
-- 1. It was worth wildly different amounts by tier. Against Daily's 300 s/day
--    the 240 s bonus is +80%; against Unlimited's 3600 s it is +6.7% —
--    nothing. And Unlimited subscribers are the MOST likely to clear 28/30,
--    because they talk the most. So the club's likeliest members were the
--    ones its headline reward meant nothing to.
-- 2. Paying for it at all made the Core an economics feature, and it isn't
--    one. What the design has actually been building this whole time is a
--    record of having kept something up: a permanent badge, a permanent day
--    count, a seat nobody can take from you. Those are dignity mechanics.
--    Bolting a discount onto them made the club look like a loyalty scheme
--    that happened to have feelings.
--
-- So: the Core grants NOTHING. It is a standing and a record — honour, and a
-- promise kept to yourself — and the platform hands over no goods for it. The
-- seal other learners see stays, because being seen is not a payout.
--
-- Consequences worth having:
--   * The Core no longer touches billing at all. `consume_metered_seconds`
--     goes back to exactly what 20260814100000 shipped, and the app's most
--     sensitive code path stops having a club in the middle of it.
--   * There is no longer anything to farm. Wall-clock talk time is gameable
--     (leave the line open), which mattered while minutes were the prize;
--     gaming a scoreboard that pays nothing is a much smaller worry.
--   * The reward can never be underwater, so the club needs no cost ceiling
--     and the seat count can be whatever the design wants.
--
-- Order below matters: rewrite the two functions off the column first, then
-- drop the function that reads it, then drop the column.

-- 1) Metering, with the bonus removed. Otherwise byte-identical to
--    20260814100000 — Watch's count split, the trial rate and the hard
--    paywall fall-through all stay exactly as they were.

create or replace function public.consume_metered_seconds(
  p_user_id uuid,
  p_seconds integer,
  p_pool text,                  -- 'talk_seconds' | 'scene_seconds' | 'scene_counted'
  p_action text,
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   bigint;
  v_scenes  bigint;
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

  select s.status = 'trialing',
         case when s.status = 'trialing'
              then coalesce((select min(daily_seconds) from subscription_plans
                              where tier = 'daily'), p.daily_seconds)
              else p.daily_seconds end
    into v_trial, v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  if v_cap is not null then
    if v_today > v_cap then
      raise exception 'DAILY_CAP_REACHED' using errcode = 'P0005';
    end if;
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                                    'scene_seconds_today', v_scenes,
                                    'pool', p_pool,
                                    'covered_by', case when v_trial then 'trial' else 'plan' end));
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today, 'daily_cap', v_cap,
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
$$;

-- 2) Progress payload loses `bonus_seconds`; there is no bonus to report.

create or replace function public.core_my_progress()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c           core_club_config%rowtype;
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'utc')::date;
  v_days      jsonb;
  v_flags     boolean[];
  v_met_entry integer := 0;
  v_met_keep  integer := 0;
  v_member    jsonb;
  v_qualified boolean := false;
  v_seated    boolean := false;
  v_last_left date;
  v_club      integer;
  v_to_entry  integer;
  v_to_return integer;
  v_requal    boolean := false;
  v_len       integer;
  v_past      integer;
  v_remain    integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into c from core_club_config where id;

  -- Every day in the entry window, gaps filled with zero, so the client can
  -- draw the whole month without inventing dates.
  -- Integer offsets, not generate_series over dates: the date arguments
  -- would resolve to the timestamptz overload and cast back through the
  -- session timezone, which can land a day either side of the UTC day the
  -- settlement uses.
  with span as (
    select v_today - g as day
      from generate_series(0, c.entry_window_days - 1) g
  ), joined as (
    select s.day,
           coalesce(a.talk_seconds, 0)::bigint as seconds,
           coalesce(a.talk_seconds, 0) >= c.daily_bar_seconds as met
      from span s
      left join core_daily_activity a
        on a.user_id = v_uid and a.day = s.day
  )
  select jsonb_agg(jsonb_build_object('day', day, 'seconds', seconds, 'met', met)
                   order by day),
         count(*) filter (where met)::int,
         count(*) filter (where met and day > v_today - c.keep_window_days)::int,
         array_agg(met order by day)
    into v_days, v_met_entry, v_met_keep, v_flags
    from joined;

  select true, m.seated, m.last_left_on,
         jsonb_build_object('join_number', m.join_number,
                            'seated', m.seated,
                            'days_total', m.days_total,
                            'qualified_at', m.qualified_at)
    into v_qualified, v_seated, v_last_left, v_member
    from core_membership m
   where m.user_id = v_uid;

  -- SELECT INTO with no matching row sets its targets to NULL, not to their
  -- initialisers — so a learner who hasn't qualified leaves v_qualified NULL,
  -- `not v_qualified` evaluates to NULL, and the challenger countdown below
  -- silently never runs. Pin them back to booleans.
  v_qualified := coalesce(v_qualified, false);
  v_seated    := coalesce(v_seated, false);

  select count(*) into v_club from core_membership where seated;

  v_len := coalesce(array_length(v_flags, 1), 0);

  -- Days until the entry bar, assuming every day from here is met. Met days
  -- already banked stay banked only while they sit inside the rolling
  -- window, which is why the count shrinks as `k` grows.
  if not v_qualified then
    for k in 0..c.entry_window_days loop
      v_remain := c.entry_window_days - k;
      v_past := 0;
      if v_remain > 0 and v_len > 0 then
        select count(*) into v_past
          from unnest(v_flags[greatest(v_len - v_remain + 1, 1):v_len]) f
         where f;
      end if;
      if v_past + k >= c.entry_required_days then
        v_to_entry := k;
        exit;
      end if;
    end loop;
  end if;

  -- Days until a seatless member is eligible again. A short absence is
  -- measured against the KEEP bar — the month is asked of a first-timer, not
  -- of someone who already proved it. Past requalify_after_days it is the
  -- month again.
  if v_qualified and not v_seated then
    v_requal := v_last_left is not null
                and (v_today - v_last_left) > c.requalify_after_days;
    if v_requal then
      v_to_return := v_to_entry;
      for k in 0..c.entry_window_days loop
        v_remain := c.entry_window_days - k;
        v_past := 0;
        if v_remain > 0 and v_len > 0 then
          select count(*) into v_past
            from unnest(v_flags[greatest(v_len - v_remain + 1, 1):v_len]) f
           where f;
        end if;
        if v_past + k >= c.entry_required_days then
          v_to_return := k;
          exit;
        end if;
      end loop;
    else
      for k in 0..c.keep_window_days loop
        v_remain := c.keep_window_days - k;
        v_past := 0;
        if v_remain > 0 and v_len > 0 then
          select count(*) into v_past
            from unnest(v_flags[greatest(v_len - v_remain + 1, 1):v_len]) f
           where f;
        end if;
        if v_past + k >= c.keep_required_days then
          v_to_return := k;
          exit;
        end if;
      end loop;
    end if;
  end if;

  return jsonb_build_object(
    'bar_seconds',    c.daily_bar_seconds,
    'seats',          c.seats,
    'club_size',      v_club,
    'member',         v_member,
    'days',           coalesce(v_days, '[]'::jsonb),
    'met_entry',      v_met_entry,
    'entry_required', c.entry_required_days,
    'entry_window',   c.entry_window_days,
    'met_keep',       v_met_keep,
    'keep_required',  c.keep_required_days,
    'keep_window',    c.keep_window_days,
    'days_to_entry',  v_to_entry,
    'days_to_return', v_to_return,
    'requalifying',   v_requal,
    -- Bar cleared, badge held, nothing to do but wait for someone to vacate.
    'waiting_for_seat', v_qualified and not v_seated
                        and coalesce(v_to_return, -1) = 0 and v_club >= c.seats);
end;
$$;

-- 3) The bonus itself.

drop function if exists public.core_bonus_seconds(uuid);

alter table public.core_club_config drop column if exists bonus_seconds;
