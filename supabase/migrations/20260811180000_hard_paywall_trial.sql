-- Hard paywall + 7-day trial, and the trial is metered as DAILY.
--
-- Two changes, both about who may speak:
--
-- 1) New signups get NO free talk pool. The free tier stops being "66 minutes
--    on the house" and becomes "clone your voice, hear it say hello, then
--    subscribe" — the clone and the onboarding greeting stay free (they're
--    the entry ticket, not usage), and the first real talk hits the paywall.
--    EXISTING balances are untouched: the beta testers' leftovers are theirs.
--
-- 2) A subscription in TRIAL is capped at the Daily allowance (5 min/day) no
--    matter which plan is being trialed. Someone trialing Unlimited would
--    otherwise get 60 min/day × 7 days ≈ €19 of upstream cost before a single
--    cent of revenue, and cancelling on day 7 is free for them. The trial
--    exists to prove the product works, and 5 minutes a day is exactly the
--    habit the product is selling — so the trial IS the Daily experience.
--    On conversion the real plan's cap takes over with no further change.

-- ---------------------------------------------------------------------------
-- 1) Signup: create the credit row at ZERO instead of granting seconds.
--    The row must exist (charge_credits raises NO_CREDIT_ROW without one,
--    which the edge functions map to the same 402 — but an explicit row keeps
--    balance reads and the Me tab honest).
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.user_credits (user_id, balance, updated_at)
  values (new.id, 0, now())
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Metering: trialing → the Daily tier's allowance, whatever the plan.
--    Everything else is unchanged from 20260811160000.
-- ---------------------------------------------------------------------------

create or replace function public.consume_metered_seconds(
  p_user_id uuid,
  p_seconds integer,
  p_pool text,                  -- 'talk_seconds' | 'scene_seconds'
  p_action text,                -- ledger action tag ('talk_time', 'tts_scene', …)
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
  v_cap     integer;
  v_trial   boolean := false;
  v_balance integer;
begin
  if p_seconds < 0 or p_seconds > 3600 then
    raise exception 'p_seconds out of range';
  end if;
  if p_pool not in ('talk_seconds', 'scene_seconds') then
    raise exception 'unsupported pool %', p_pool;
  end if;

  -- Idempotency: a retried key must neither re-accumulate nor re-charge.
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

  select coalesce(sum(chars), 0) into v_today from tts_char_pool
   where user_id = p_user_id and day = current_date
     and action in ('talk_seconds', 'scene_seconds');

  -- Entitled subscriber: the plan's daily allowance covers it, balance
  -- untouched. A TRIAL is metered at the Daily tier's allowance regardless of
  -- which plan is being trialed (see header). Past the cap → raise (rolls
  -- back this call's accumulation).
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
                                    'covered_by', case when v_trial then 'trial' else 'plan' end));
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today, 'daily_cap', v_cap,
                              'covered_by', case when v_trial then 'trial' else 'plan' end);
  end if;

  -- No entitlement: debit the seconds balance. For a new signup that balance
  -- is 0, so this raises INSUFFICIENT_CREDITS → 402 → paywall. Beta testers
  -- keep spending whatever they had left.
  v_balance := public.charge_credits(
    p_user_id => p_user_id,
    p_credits => p_seconds,
    p_action  => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                            'covered_by', 'balance'));
  return jsonb_build_object('balance', v_balance, 'charged', p_seconds,
                            'seconds_today', v_today, 'covered_by', 'balance');
end;
$$;
