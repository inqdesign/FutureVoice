-- ---------------------------------------------------------------------------
-- talk_allowance carries BOTH changes made to it on 2026-10-10 / 10-12.
--
-- 20261010120000 (invite minutes expire) added `bonus_expires_at` /
-- `bonus_expiring`; 20261012120000 (annual pools refill monthly) changed
-- `period_end` to the monthly refill. Each file redefines the WHOLE function
-- from the version before it, so applied in order the second one dropped the
-- first one's fields. This is the union, applied after both (2026-10-16).
-- ---------------------------------------------------------------------------

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
  v_exp_at    timestamptz;
  v_exp_secs  integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select balance into v_bonus from user_credits where user_id = v_uid;

  -- The next batch of invite minutes to lapse (20261010120000): when, and how
  -- much of the balance goes with it. Null when nothing is waiting to expire.
  select e.expires_at, sum(e.remaining)::integer
    into v_exp_at, v_exp_secs
    from expiring_balance e
   where e.user_id = v_uid and e.remaining > 0 and e.settled_at is null
     and e.expires_at = (select min(expires_at) from expiring_balance
                          where user_id = v_uid and remaining > 0 and settled_at is null)
   group by e.expires_at;

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
                              'metered_by', 'balance',
                              'bonus_expires_at', v_exp_at,
                              'bonus_expiring', v_exp_secs);
  end if;

  v_start := public.billing_period_start(v_uid);
  v_used := public.plan_period_seconds(v_uid);

  return jsonb_build_object('used', v_used,
                            'cap', case when v_unlimited then null else v_cap end,
                            'unlimited', v_unlimited,
                            'bonus', coalesce(v_bonus, 0),
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'plan',
                            'bonus_expires_at', v_exp_at,
                            'bonus_expiring', v_exp_secs);
end;
$function$;
