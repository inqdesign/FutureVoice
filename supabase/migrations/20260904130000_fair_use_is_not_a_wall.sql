-- Fair use is a line we watch, never a wall the learner walks into.
--
-- Three things were wrong at once on the uncapped tier (Plus), and they only
-- make sense together.
--
-- 1. `talk_allowance()` in production has no unlimited branch — it hands back
--    `monthly_seconds` for every plan. The app believed it and told a Plus
--    subscriber they had "1,795 of 1,800 min left": a pool that tier does not
--    have, counting down toward a wall that (see 2) does not exist. The client
--    now decides by TIER, but the RPC has to stop saying it.
--
-- 2. Nothing actually stopped an uncapped account, at any number. The plan is
--    sold as no-limit and that is honest, but "no limit" cannot mean a script
--    may bill us for a thousand hours. So the fair-use figure becomes a FLAG:
--    crossing it writes `fair_use_flags` and the learner sees nothing at all.
--    A real stop exists far above it (`abuse_seconds`, 3,000 min = 100 min a
--    day every day) and raises its OWN error, because the spent-allowance
--    sheet — "All 1800 minutes of talk are used up" — is exactly the sentence
--    someone who bought "no limit" must never be shown.
--
-- 3. Invite minutes were spent by that tier. `20260821100000` made the balance
--    pay for every tick "entitled or not", which was right while every tier had
--    a ceiling. On a plan that cannot run out there is nothing to buy: the
--    bonus was destroyed for no gain, and because those seconds never reach
--    `tts_char_pool` the month's own figure could not see them either.
--
-- Light is untouched by all three.

alter table public.subscription_plans
  add column if not exists abuse_seconds integer;

comment on column public.subscription_plans.abuse_seconds is
  'Only for plans with talk_unlimited: the seconds past which talking actually '
  'stops, far above monthly_seconds (which is the fair-use line we merely '
  'watch). Null = no stop. Never shown to a learner and never sold.';

update public.subscription_plans
   set abuse_seconds = 180000            -- 3,000 min: 100 min a day, every day
 where coalesce(talk_unlimited, false)
   and abuse_seconds is null;

-- Who crossed the fair-use line this period. Read by the admin console only:
-- it is a list of people, and nothing in the app may render it.
create table if not exists public.fair_use_flags (
  user_id      uuid not null references auth.users(id) on delete cascade,
  period_start date not null,
  seconds      integer not null,
  updated_at   timestamptz not null default now(),
  primary key (user_id, period_start)
);

alter table public.fair_use_flags enable row level security;
revoke all on table public.fair_use_flags from anon, authenticated;

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
  v_entitled  boolean := false;
  v_trial     boolean := false;
  v_unlimited boolean := false;
  v_balance   integer;
  v_abuse     integer;
  v_flag_new  boolean := false;
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

  -- Who is paying for this tick, resolved before anything is written. A trial
  -- is metered at the LIGHT tier's pool pro-rated to the sample's length, and
  -- is never uncapped — a week's sample must not be worth more than the month
  -- it converts to.
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

  select balance into v_balance from user_credits where user_id = p_user_id;

  -- 1. INVITE MINUTES FIRST. Entitled or not, a positive balance pays for this
  -- tick and the plan's pool is left alone — so these seconds never reach
  -- `tts_char_pool` and the month's own figures keep describing the month.
  -- Only a WHOLE tick is taken: a tick is a second or a few, so the leftover
  -- at the boundary is smaller than the thing being split.
  -- ...EXCEPT on a plan whose talking is not capped. There is nothing for the
  -- minutes to buy there — the tick is free to the account either way — so
  -- spending them only destroys a bonus that still has a use later, after the
  -- plan lapses or on a tier that counts. An uncapped account burned ~70
  -- minutes of invite time this way before it was noticed.
  if p_seconds > 0 and coalesce(v_balance, 0) >= p_seconds
     and not (v_unlimited and p_pool = 'talk_seconds') then
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
                              'talk_unlimited', v_unlimited,
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

  -- 2. THE PLAN. `v_unlimited` is checked as well as `v_cap` because a plan
  -- with no ceiling still has to record its seconds — the ceiling can then be
  -- re-derived from real behaviour if it is ever wanted back.
  if v_entitled and (v_unlimited or v_cap is not null) then
    v_start := public.billing_period_start(p_user_id);
    select coalesce(sum(chars), 0) into v_period from tts_char_pool
     where user_id = p_user_id and day >= v_start
       and action in ('talk_seconds', 'scene_seconds');

    if not v_unlimited and v_period > v_cap then
      raise exception 'DAILY_CAP_REACHED' using errcode = 'P0005';
    end if;

    -- An uncapped plan is sold as having no limit, so the fair-use figure is
    -- NOT a wall: crossing it writes a row we can look at and changes nothing
    -- the learner sees. A person cannot reach it by talking (it is an hour a
    -- day, every day); what reaches it is a script.
    if v_unlimited and v_period > v_cap then
      -- `xmax = 0` is true only for a row this statement INSERTED, so the
      -- owner is told once per period rather than every 30 seconds for the
      -- rest of the month. The alert itself is the edge function's job — the
      -- database has no business talking to Telegram.
      insert into fair_use_flags (user_id, period_start, seconds, updated_at)
      values (p_user_id, v_start, v_period, now())
      on conflict (user_id, period_start) do update
        set seconds = excluded.seconds, updated_at = now()
      returning (xmax = 0) into v_flag_new;

      -- The only real stop, and it is far above the line above. Its own error
      -- code, because "you used up your minutes" must never be said to an
      -- account that was sold no limit — this is an account under review, not
      -- a spent allowance.
      select abuse_seconds into v_abuse from subscription_plans p
        join user_subscriptions s on s.plan_id = p.id
       where s.user_id = p_user_id
         and s.status in ('trialing', 'active', 'grace');
      if v_abuse is not null and v_period > v_abuse then
        raise exception 'FAIR_USE_LIMIT' using errcode = 'P0007';
      end if;
    end if;

    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                                    'seconds_period', v_period, 'period_start', v_start,
                                    'scene_seconds_today', v_scenes, 'pool', p_pool,
                                    'talk_unlimited', v_unlimited,
                                    'covered_by', case when v_trial then 'trial' else 'plan' end));
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today,
                              'seconds_period', v_period,
                              'monthly_cap', v_cap, 'daily_cap', v_cap,
                              'talk_unlimited', v_unlimited,
                              'period_start', v_start,
                              'scene_seconds_today', v_scenes,
                              -- Set once, on the tick that crossed the line.
                              'fair_use_flagged', v_flag_new,
                              'fair_use_seconds', v_period,
                              'covered_by', case when v_trial then 'trial' else 'plan' end);
  end if;

  -- 3. No plan: the one-time balance pays, as it always has.
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

-- What the client is told. `cap` null on an entitled plan means "no ceiling",
-- told apart from "no plan" by `metered_by` — `used` is real either way, and
-- on the uncapped tier it is the only figure that means anything.
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
  v_bonus     integer;
  v_used      integer;
  v_start     date;
  v_end       date;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select balance into v_bonus from user_credits where user_id = v_uid;

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
     and s.status in ('trialing', 'active', 'grace');

  if not coalesce(v_entitled, false) or (v_cap is null and not v_unlimited) then
    return jsonb_build_object('used', 0, 'cap', null, 'bonus', coalesce(v_bonus, 0),
                              'period_start', null, 'period_end', null,
                              'metered_by', 'balance');
  end if;

  v_start := public.billing_period_start(v_uid);
  select coalesce(sum(chars), 0)::integer into v_used
    from tts_char_pool
   where user_id = v_uid and day >= v_start
     and action in ('talk_seconds', 'scene_seconds');

  return jsonb_build_object('used', v_used,
                            'cap', case when v_unlimited then null else v_cap end,
                            'unlimited', v_unlimited,
                            'bonus', coalesce(v_bonus, 0),
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'plan');
end;
$$;

revoke all on function public.talk_allowance() from public, anon;
grant execute on function public.talk_allowance() to authenticated, service_role;
