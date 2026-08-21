-- Plus: talking is genuinely uncapped. Watch keeps its count.
--
-- WHY THE TWO SIDES DIFFER, and it is not a compromise:
--
--   Watch is consumed by TAPPING. A scene plays itself, so one person with a
--   free afternoon can run through a month of them without doing anything,
--   and every one of those scenes is billed to us on `fidelityModelId` at
--   roughly twice the per-character rate of a talk turn. A count is the only
--   thing standing between us and that, so the count stays.
--
--   Talk is consumed by SPEAKING. Nobody talks for six hours; the effort is
--   the limiter, and it is a limiter no ceiling can improve on. The pool was
--   therefore doing no work on this side — 1,800 minutes is an hour a day,
--   which almost no account approaches — while costing us the thing the
--   ceiling was supposed to protect: a subscriber who has to ration the one
--   activity the product exists for. So it goes.
--
--   The effort argument only holds while the meter charges for SPEECH rather
--   than for a screen left open. `TalkMeter.isBillable` +
--   `ConversationView.someoneIsTalkingHere()` are what make that true (close-
--   mic voiced audio, three witnesses, café-proof since 2026-08-18). Weaken
--   those and this migration becomes an open tab.
--
-- This is a MEASUREMENT decision as much as a product one: nobody knows what
-- a subscriber with no talk ceiling actually does, because no such account has
-- ever existed. Usage is still recorded in full (`tts_char_pool`,
-- `usage_ledger`, `talk_seconds_by_language`), so the ceiling can be re-derived
-- from real behaviour instead of from an estimate. Putting it back is one
-- UPDATE, not a migration — that is why this is a column and not an `if tier =
-- 'plus'` branch.

alter table public.subscription_plans
  add column if not exists talk_unlimited boolean not null default false;

comment on column public.subscription_plans.talk_unlimited is
  'Talking is not capped for this plan; `monthly_seconds` becomes descriptive '
  'only (a fair-use reference). Watch scenes are unaffected — `monthly_scenes` '
  'is always enforced, because scenes cost effort to nobody but us. Flip to '
  'false to restore the ceiling; no code change needed.';

update public.subscription_plans set talk_unlimited = true  where tier = 'plus';
update public.subscription_plans set talk_unlimited = false where tier <> 'plus';

-- ---------------------------------------------------------------------------
-- Talk metering: entitled-and-uncapped is now its own path.
--
-- Nulling `monthly_seconds` would NOT have worked: `v_cap is null` already
-- means "no plan", and falls through to `charge_credits`, so an uncapped Plus
-- subscriber would have started spending `user_credits.balance` — a pool they
-- do not have — and hit `insufficient_credits` on their first call.
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
  v_today     bigint;
  v_period    bigint;
  v_scenes    bigint;
  v_start     date;
  v_cap       integer;
  v_unlimited boolean := false;
  v_entitled  boolean := false;
  v_trial     boolean := false;
  v_balance   integer;
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
  -- length, whatever plan is being trialed — and a trial is NEVER uncapped,
  -- or a week's sample would be worth more than the month it converts to.
  select true,
         s.status = 'trialing',
         s.status <> 'trialing' and coalesce(p.talk_unlimited, false),
         case when s.status = 'trialing'
              then coalesce((select min(monthly_seconds) from subscription_plans
                              where tier = 'light'), p.monthly_seconds) * 7 / 30
              else p.monthly_seconds end
    into v_entitled, v_trial, v_unlimited, v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  if v_entitled and (v_unlimited or v_cap is not null) then
    v_start := public.billing_period_start(p_user_id);
    select coalesce(sum(chars), 0) into v_period from tts_char_pool
     where user_id = p_user_id and day >= v_start
       and action in ('talk_seconds', 'scene_seconds');

    -- The ONLY line this migration removes for Plus. Everything below still
    -- runs, so the seconds are recorded exactly as before and the ceiling can
    -- be re-derived from them later.
    if not v_unlimited and v_period > v_cap then
      raise exception 'DAILY_CAP_REACHED' using errcode = 'P0005';
    end if;

    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                                    'seconds_period', v_period, 'period_start', v_start,
                                    'scene_seconds_today', v_scenes, 'pool', p_pool,
                                    'talk_unlimited', v_unlimited,
                                    'covered_by', case when v_trial then 'trial' else 'plan' end));
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today,
                              'seconds_period', v_period,
                              'monthly_cap', case when v_unlimited then null else v_cap end,
                              'daily_cap', case when v_unlimited then null else v_cap end,
                              'talk_unlimited', v_unlimited,
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
-- What the client is told. `cap` null now means one of TWO things, and they
-- are told apart by `metered_by`:
--   'balance' — no plan; the one-time seconds pool is what's left.
--   'plan'    — entitled, and talking is not capped. `used` is still real,
--               because the app reports what this month HAS been spoken (a
--               subscriber who isn't rationing has nothing to count down).
-- ---------------------------------------------------------------------------
create or replace function public.talk_allowance()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_cap       integer;
  v_unlimited boolean := false;
  v_entitled  boolean := false;
  v_used      integer;
  v_start     date;
  v_end       date;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select true,
         s.status <> 'trialing' and coalesce(p.talk_unlimited, false),
         case when s.status = 'trialing'
              then coalesce((select min(monthly_seconds) from subscription_plans
                              where tier = 'light'), p.monthly_seconds) * 7 / 30
              else p.monthly_seconds end,
         s.current_period_end::date
    into v_entitled, v_unlimited, v_cap, v_end
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid
     and s.status in ('trialing', 'active', 'grace')
   order by s.current_period_start desc nulls last
   limit 1;

  if not coalesce(v_entitled, false) or (v_cap is null and not v_unlimited) then
    return jsonb_build_object('used', 0, 'cap', null, 'period_start', null,
                              'period_end', null, 'metered_by', 'balance');
  end if;

  v_start := public.billing_period_start(v_uid);
  select coalesce(sum(chars), 0)::integer into v_used
    from tts_char_pool
   where user_id = v_uid and day >= v_start
     and action in ('talk_seconds', 'scene_seconds');

  return jsonb_build_object('used', v_used,
                            'cap', case when v_unlimited then null else v_cap end,
                            'unlimited', v_unlimited,
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'plan');
end;
$$;

revoke all on function public.talk_allowance() from public, anon;
grant execute on function public.talk_allowance() to authenticated, service_role;

-- `begin_scene_play` and `scene_allowance` are deliberately UNTOUCHED. Watch
-- keeps `monthly_scenes` on every tier.
