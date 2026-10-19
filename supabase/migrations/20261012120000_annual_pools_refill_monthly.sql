-- ---------------------------------------------------------------------------
-- An ANNUAL plan's pools refill every MONTH (2026-10-12).
--
-- Every meter counts from `billing_period_started_at()` /
-- `billing_period_start()`, which read the subscription's
-- `current_period_start` — and on an annual subscription that moves once a
-- year. So "150 min a month" on Light annual was 150 min for the WHOLE YEAR,
-- and the German `plus_annual` row (2026-09-27 → 2027-09-27) has been metered
-- against 600 min for twelve months. Found while reading b989b404, a Plus
-- monthly learner who tapped Light annual today: at ~7 min a day they would
-- have been walled within three weeks of paying for a year.
--
-- The fix is in the two functions every meter already asks: a subscription
-- whose period is longer than 35 days is cut into monthly periods anchored on
-- its own start (09-27 → 10-27 → 11-27 …, a 31st falls back to the month's
-- last day the way Postgres adds months). A monthly or trial row is left
-- exactly as it was — its period IS the month, and nothing about it moves.
-- `talk_allowance` / `scene_allowance` are the live definitions with only the
-- `period_end` they report changed, so the refill date on screen is the
-- monthly one rather than the renewal a year away.
-- ---------------------------------------------------------------------------

-- The start of the month-long slice of [p_start, …) that contains p_at.
create or replace function public.monthly_anchor(p_start timestamptz, p_at timestamptz)
 returns timestamptz
 language plpgsql
 immutable
as $$
declare
  s timestamp := p_start at time zone 'UTC';
  a timestamp := p_at at time zone 'UTC';
  n integer;
begin
  if p_at <= p_start then
    return p_start;
  end if;
  n := (extract(year from age(a, s)) * 12 + extract(month from age(a, s)))::int;
  -- age() and month addition disagree at month ends (Jan 31 + 1 month is
  -- Feb 28, but age(Feb 28, Jan 31) is 28 days): take the next slice once
  -- its start has passed.
  if s + make_interval(months => n + 1) <= a then
    n := n + 1;
  end if;
  return (s + make_interval(months => n)) at time zone 'UTC';
end;
$$;

create or replace function public.billing_period_started_at(p_user_id uuid)
 returns timestamptz
 language sql
 stable security definer
 set search_path to 'public'
as $$
  select coalesce(
           (select case when s.current_period_end - s.current_period_start > interval '35 days'
                        then public.monthly_anchor(s.current_period_start, now())
                        else s.current_period_start end
              from user_subscriptions s
             where s.user_id = p_user_id
               and s.status in ('trialing', 'active', 'grace')
               and s.current_period_start is not null
               and s.current_period_start <= now()
             order by s.current_period_start desc
             limit 1),
           date_trunc('month', now() at time zone 'UTC') at time zone 'UTC'
         );
$$;

-- The date form, from the same rule, so `period_start` and `fair_use_flags`'
-- key can never name a different month from the one being metered.
create or replace function public.billing_period_start(p_user_id uuid)
 returns date
 language sql
 stable security definer
 set search_path to 'public'
as $$
  select public.billing_period_started_at(p_user_id)::date;
$$;

create or replace function public.billing_period_ends_at(p_user_id uuid)
 returns timestamptz
 language sql
 stable security definer
 set search_path to 'public'
as $$
  select case when s.current_period_end - s.current_period_start > interval '35 days'
              then ((public.monthly_anchor(s.current_period_start, now()) at time zone 'UTC')
                    + interval '1 month') at time zone 'UTC'
              else s.current_period_end end
    from user_subscriptions s
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace')
   order by s.current_period_start desc nulls last
   limit 1;
$$;

revoke all on function public.billing_period_ends_at(uuid) from public, anon, authenticated;
grant execute on function public.billing_period_ends_at(uuid) to service_role;

CREATE OR REPLACE FUNCTION public.talk_allowance()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid       uuid := auth.uid();
  v_cap       integer;
  v_unlimited boolean := false;
  v_entitled  boolean := false;
  v_bonus     integer;
  v_used      integer;
  v_start     date;
  v_end       date;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select balance into v_bonus from user_credits where user_id = v_uid;

  -- The row's stamp outranks the plan (2026-09-26) — the same read the meter
  -- makes in `consume_metered_seconds`, so the number on screen is the
  -- number the wall is judged by.
  select true,
         s.status <> 'trialing' and coalesce(s.talk_unlimited, p.talk_unlimited, false),
         case when s.status = 'trialing'
              then coalesce(s.monthly_seconds,
                            (select min(monthly_seconds) from subscription_plans
                              where tier = 'light'), p.monthly_seconds) * 7 / 30
              else coalesce(s.monthly_seconds, p.monthly_seconds) end,
         public.billing_period_ends_at(v_uid)::date
    into v_entitled, v_unlimited, v_cap, v_end
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid
     and s.status in ('trialing', 'active', 'grace');

  if not coalesce(v_entitled, false) or (v_cap is null and not v_unlimited) then
    return jsonb_build_object('used', 0, 'cap', null, 'bonus', coalesce(v_bonus, 0),
                              'period_start', null, 'period_end', null,
                              'metered_by', 'balance');
  end if;

  v_start := public.billing_period_start(v_uid);
  v_used := public.plan_period_seconds(v_uid);

  return jsonb_build_object('used', v_used,
                            'cap', case when v_unlimited then null else v_cap end,
                            'unlimited', v_unlimited,
                            'bonus', coalesce(v_bonus, 0),
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'plan');
end;
$function$;

CREATE OR REPLACE FUNCTION public.scene_allowance()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_cap   integer;
  v_used  integer;
  v_start date;
  v_end   date;
  v_unlimited boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select case when s.status = 'trialing'
              then coalesce(s.monthly_scenes,
                            (select min(monthly_scenes) from subscription_plans
                              where tier = 'light'), p.monthly_scenes) * 7 / 30
              else coalesce(s.monthly_scenes, p.monthly_scenes) end,
         public.billing_period_ends_at(v_uid)::date
    into v_cap, v_end
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid
     and s.status in ('trialing', 'active', 'grace')
   order by s.current_period_start desc nulls last
   limit 1;

  if v_cap is null then
    select coalesce(c.unlimited, false) into v_unlimited
      from user_credits c where c.user_id = v_uid;
    select count(distinct scene_key) into v_used
      from scene_plays where user_id = v_uid;
    return jsonb_build_object('used', 0, 'cap', null, 'period_start', null,
                              'period_end', null, 'metered_by', 'balance',
                              'free_used', v_used,
                              'free_cap', case when coalesce(v_unlimited, false)
                                               then null else 2 end);
  end if;

  v_start := public.billing_period_start(v_uid);
  select count(*) into v_used from scene_plays
   where user_id = v_uid
     and created_at >= public.billing_period_started_at(v_uid);

  return jsonb_build_object('used', v_used, 'cap', v_cap,
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'scenes');
end;
$function$;
