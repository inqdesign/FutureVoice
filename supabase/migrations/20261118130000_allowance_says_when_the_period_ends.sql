-- The pool's refill is a MOMENT, and the app was only told its UTC date
-- (2026-11-18). `period_end` is `billing_period_ends_at(...)::date`; the app
-- read that date as UTC midnight and drew it in the phone's time zone, so a
-- Light subscriber in Texas whose plan renews on Nov 19 13:54 UTC was told
-- "Refills on Nov 18", and on the 18th nothing refilled. East of UTC the same
-- date can be a day early for a late renewal.
--
-- `period_end_at` is the moment itself. Additive: every build that does not
-- read it keeps `period_end` exactly as it was. The body below is the live
-- definition (pg_get_functiondef, 2026-11-18) plus that one key, on the
-- plan-metered answer only (the balance answer has no period).

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
              then public.trial_talk_seconds(s.monthly_seconds, p.monthly_seconds)
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
                            'period_end_at', public.billing_period_ends_at(v_uid),
                            'metered_by', 'plan',
                            'bonus_expires_at', v_exp_at,
                            'bonus_expiring', v_exp_secs);
end;
$function$;
