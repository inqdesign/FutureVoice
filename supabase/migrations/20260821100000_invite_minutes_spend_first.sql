-- ---------------------------------------------------------------------------
-- Invite minutes become spendable BY SUBSCRIBERS — before the monthly pool.
--
-- They were not. `redeem_referral` grants seconds into `user_credits.balance`,
-- and `consume_metered_seconds` only ever reached that balance on the
-- no-plan path: an entitled account was metered against its pool and its
-- balance sat untouched. So the reward went to the one person most likely to
-- invite anybody — a happy subscriber — in a currency they could only spend by
-- CANCELLING. The invite screen said so out loud ("kept for after your plan
-- ends"), which is an apology, not a feature.
--
-- Now the balance is spent first and the pool only starts once it is empty.
-- A Light subscriber who invites five friends gets 150 bonus minutes — a
-- month's worth of talking — on top of the month they pay for, and feels it
-- this week rather than after they leave.
--
-- Spent FIRST rather than added to the cap, for two reasons. The pool's own
-- figures stay honest — "18 of 150 min left this month" keeps meaning the
-- plan, and a gift never inflates the number the plan is judged by. And the
-- bonus has no expiry, so spending it first is the only order that doesn't
-- quietly make it a use-it-or-lose-it allowance.
--
-- Nothing else about the program changes: 30 min a side, the inviter rewarded
-- for the first 10 invites, Watch scenes not included (a scene costs about
-- twice a talk second, so giving a month of scenes would cost more than the
-- talk it is meant to seed). No Apple offer codes — the reward is talk time,
-- and nothing here claims to stop Apple charging for the subscription.
--
-- Zero redemptions had ever happened when this was written, so there is no
-- history to reconcile.
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

  -- The trial is metered at the LIGHT tier's pool, pro-rated to the sample's
  -- length, whatever plan is being trialed. Resolved BEFORE anything is
  -- written, because who pays for this tick decides where it is recorded.
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

  select balance into v_balance from user_credits where user_id = p_user_id;

  -- INVITE MINUTES FIRST. Entitled or not, a positive balance pays for this
  -- tick and the plan's pool is left alone — so these seconds never appear in
  -- `tts_char_pool` and the month's own figures keep describing the month.
  -- Only a WHOLE tick is taken from the balance: a tick is a second or a few,
  -- so the leftover at the boundary is smaller than the thing being split,
  -- and splitting it would buy nothing but a second ledger row.
  if p_seconds > 0 and coalesce(v_balance, 0) >= p_seconds then
    v_balance := public.charge_credits(
      p_user_id => p_user_id,
      p_credits => p_seconds,
      p_action  => p_action,
      p_source_fn => p_source_fn,
      p_idempotency_key => p_idempotency_key,
      p_metadata => coalesce(p_metadata, '{}'::jsonb)
        || jsonb_build_object('seconds', p_seconds, 'pool', p_pool,
                              'covered_by', 'invite_minutes'));
    select coalesce(sum(chars), 0) into v_today from tts_char_pool
     where user_id = p_user_id and day = current_date
       and action in ('talk_seconds', 'scene_seconds');
    return jsonb_build_object('balance', v_balance, 'charged', p_seconds,
                              'seconds_today', v_today,
                              'monthly_cap', v_cap, 'daily_cap', v_cap,
                              'covered_by', 'invite_minutes');
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
-- `talk_allowance()` gains the bonus, so the app can show it beside the pool
-- instead of the learner discovering it only when the pool fails to move.
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
  v_bonus integer;
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

  select greatest(0, coalesce(balance, 0)) into v_bonus
    from user_credits where user_id = v_uid;

  if v_cap is null then
    return jsonb_build_object('used', 0, 'cap', null, 'bonus', coalesce(v_bonus, 0),
                              'period_start', null, 'period_end', null,
                              'metered_by', 'balance');
  end if;

  v_start := public.billing_period_start(v_uid);
  select coalesce(sum(chars), 0)::integer into v_used
    from tts_char_pool
   where user_id = v_uid and day >= v_start
     and action in ('talk_seconds', 'scene_seconds');

  return jsonb_build_object('used', v_used, 'cap', v_cap,
                            'bonus', coalesce(v_bonus, 0),
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'plan');
end;
$$;

revoke all on function public.talk_allowance() from public, anon;
grant execute on function public.talk_allowance() to authenticated, service_role;
