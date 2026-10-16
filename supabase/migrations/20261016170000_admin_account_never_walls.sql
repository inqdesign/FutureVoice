-- The admin account (user_credits.unlimited) was treated as a free account.
--
-- 1. consume_metered_seconds: refill the admin pool before any step judges
--    it. The auto-reset lived only in charge_credits and fired on an
--    overdraw, which steps 0 and 3 (2026-09-20) made impossible, so an admin
--    account without a live plan was walled at zero ("내 사용량이 0이 된다").
-- 2. owner_alerts_claim: the owner's own paywall views are not news.
--
-- Bodies are the live production definitions with only those lines added.

CREATE OR REPLACE FUNCTION public.consume_metered_seconds(p_user_id uuid, p_seconds integer, p_pool text, p_action text, p_source_fn text, p_idempotency_key text, p_metadata jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

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
  v_take      integer;
  v_admin     boolean := false;
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

  -- Who is paying for this tick, resolved before anything is written. The
  -- SUBSCRIPTION's own stamp outranks the plan (2026-09-26): a row sold with
  -- uncapped talk, or a bigger pool, keeps it after the catalog moves. A
  -- trial is metered at the LIGHT tier's pool pro-rated to the sample's
  -- length, and is never uncapped — a week's sample must not be worth more
  -- than the month it converts to.
  select true,
         s.status = 'trialing',
         s.status <> 'trialing' and coalesce(s.talk_unlimited, p.talk_unlimited, false),
         case when s.status = 'trialing'
              then coalesce(s.monthly_seconds,
                            (select min(monthly_seconds) from subscription_plans
                              where tier = 'light'), p.monthly_seconds) * 7 / 30
              else coalesce(s.monthly_seconds, p.monthly_seconds) end
    into v_entitled, v_trial, v_unlimited, v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  select balance, coalesce(unlimited, false) into v_balance, v_admin
    from user_credits where user_id = p_user_id;

  -- The admin (auto-reset) account is refilled BEFORE any step can judge
  -- its pool (20261016170000). `charge_credits` refills only on an
  -- OVERDRAW, and since 2026-09-20 nothing here overdraws: step 0 discards
  -- a tail under a minute and step 3 spends to exactly zero and walls. So
  -- an admin account with no live plan met the free account's wall.
  if v_admin and coalesce(v_balance, 0) < 60 + p_seconds then
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'grant', 6600 - coalesce(v_balance, 0), 'cycle_grant', p_source_fn,
            case when p_idempotency_key is null then null
                 else p_idempotency_key || ':auto-reset' end,
            '{"auto_reset": true}'::jsonb);
    update user_credits set balance = 6600, updated_at = now()
     where user_id = p_user_id;
    v_balance := 6600;
  end if;

  -- 0. CLOSE A POOL THAT CANNOT CARRY A CALL. A free account's last few
  -- seconds are thrown away here, before anything spends them.
  --
  -- The gateway charges in ticks: 1 s at the start of a call, then whatever
  -- it has accumulated, up to 15 s (`TalkBilling.flushEveryMs`). So a tail of
  -- 3 s paid for the preflight, the call ran, the next flush 402'd, the call
  -- was walled and wrote its book — and the app, which gates on
  -- `balance > 0`, let the learner straight back in to do it again. Six calls
  -- and six books on one 300 s pool (reported 2026-09-20); the two earlier
  -- fixes missed it because they sat in step 3, BEHIND the invite-minutes
  -- branch that a 1 s tick always passes.
  --
  -- Only the OPENING tick judges a pool. Mid-call nothing is ever discarded:
  -- step 3 spends the remainder and walls exactly when it reaches zero, so a
  -- tail cannot form in the first place. The discard is COMMITTED, so it
  -- cannot be an exception — a raise would roll it back. It returns `wall`
  -- instead, which `talk-tick` turns into the same 402; against an
  -- un-deployed talk-tick the tick reads as a success and the next one
  -- raises the ordinary INSUFFICIENT_CREDITS, which is still one wall.
  --
  -- `not v_entitled` is load-bearing: a subscriber's invite minutes are a
  -- bonus with a use later, never a remainder to sweep.
  -- `v_entitled is not true`, never `not v_entitled`: a learner with NO
  -- subscription row leaves the SELECT INTO above with NULL in every target,
  -- so `not v_entitled` is NULL and an IF reads that as false — the rule was
  -- skipped on exactly the free accounts it exists for (2026-09-20, caught by
  -- a tail that refused to be cut).
  --
  -- The floor is a MINUTE at the start of a call and one tick during it.
  -- Under a minute cannot carry a conversation — the learner would get a
  -- greeting and a wall — so the opening tick closes the pool and the tap
  -- answers with the paywall (user's rule, 2026-09-20). Mid-call the floor
  -- stays one tick: cutting a running call at 59 s would throw away time
  -- they still have.
  if v_entitled is not true and p_pool = 'talk_seconds'
     and coalesce((p_metadata->>'preflight')::boolean, false)
     and coalesce(v_balance, 0) > 0
     and coalesce(v_balance, 0) < 60 then
    select coalesce(sum(chars), 0) into v_today from tts_char_pool
     where user_id = p_user_id and day = current_date
       and action in ('talk_seconds', 'scene_seconds');
    select coalesce(sum(chars), 0) into v_scenes from tts_char_pool
     where user_id = p_user_id and day = current_date
       and action in ('scene_seconds', 'scene_counted');
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', -v_balance, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('seconds', v_balance, 'seconds_today', v_today,
                                    'pool', p_pool, 'covered_by', 'balance',
                                    'pool_closed', true,
                                    'discarded_seconds', v_balance));
    update user_credits set balance = 0, updated_at = now()
     where user_id = p_user_id;
    return jsonb_build_object('balance', 0, 'charged', v_balance,
                              'seconds_today', v_today,
                              'scene_seconds_today', v_scenes,
                              'covered_by', 'balance',
                              'wall', 'insufficient_credits');
  end if;

  -- 1. INVITE MINUTES (and bought top-ups) FIRST. Entitled or not, a positive
  -- balance pays for this tick and the plan's pool is left alone — so these
  -- seconds never reach `tts_char_pool` and the month's own figures keep
  -- describing the month. Only a WHOLE tick is taken: a tick is a second or
  -- a few, so the leftover at the boundary is smaller than the thing being
  -- split.
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
    -- A tick that empties the pool carries the wall with it, exactly as
    -- step 3 does — otherwise the call runs on for one more tick against a
    -- balance of zero and is walled a few seconds late. An ENTITLED account
    -- never walls here: its plan pays from the next tick on.
    return jsonb_build_object('balance', v_balance, 'charged', p_seconds,
                              'seconds_today', v_today,
                              'monthly_cap', v_cap, 'daily_cap', v_cap,
                              'talk_unlimited', v_unlimited,
                              'covered_by', 'invite_minutes')
           || case when v_entitled is not true and p_pool = 'talk_seconds'
                        and v_balance <= 0
                   then jsonb_build_object('wall', 'insufficient_credits')
                   else '{}'::jsonb end;
  end if;

  -- The pool is the PLAN'S meter, so only seconds a plan is about to pay for
  -- may enter it. Step 1 above says exactly this already ("these seconds
  -- never reach `tts_char_pool`") and it has been true only for SUBSCRIBERS:
  -- on an account with no subscription row the SELECT INTO leaves every
  -- target NULL, so step 1's `not (v_unlimited and ...)` is NULL, an IF reads
  -- NULL as false, and every free second fell through to here. It was then
  -- summed into the trial's own period the moment that learner subscribed on
  -- the same day (2026-09-24, below).
  --
  -- The condition is step 2's, word for word, so the row that records a tick
  -- and the payer of that tick can never disagree again.
  if p_seconds > 0 and v_entitled is true and (v_unlimited or v_cap is not null) then
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
    -- From the period's start MOMENT (2026-10-05). This tick is already in
    -- the pool but not yet in the ledger, so on the start day — which is read
    -- from the ledger — it is added here.
    v_period := public.plan_period_seconds(p_user_id)
              + case when current_date = (public.billing_period_started_at(p_user_id)
                                          at time zone 'UTC')::date
                     then p_seconds else 0 end;

    if not v_unlimited and v_period > v_cap then
      raise exception 'DAILY_CAP_REACHED' using errcode = 'P0005';
    end if;

    -- An uncapped row (grandfathered Plus only, since 2026-09-26) was sold as
    -- having no limit, so the fair-use figure is NOT a wall: crossing it
    -- writes a row we can look at and changes nothing the learner sees. A
    -- person cannot reach it by talking (it is an hour a day, every day);
    -- what reaches it is a script.
    if v_unlimited and v_period > v_cap then
      insert into fair_use_flags (user_id, period_start, seconds, updated_at)
      values (p_user_id, v_start, v_period, now())
      on conflict (user_id, period_start) do update
        set seconds = excluded.seconds, updated_at = now();

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
                              'covered_by', case when v_trial then 'trial' else 'plan' end);
  end if;

  -- 3. No plan: the one-time balance pays — and the LAST tick takes whatever
  -- is left rather than being refused for asking too much.
  --
  -- A tick is up to 15 s, so an all-or-nothing charge ended the call while
  -- the pool still had seconds in it: the learner was told the time was up
  -- before it was, the book was written early, and the leftover let them
  -- straight back in for another short call and another book. Cutting that
  -- leftover away (the first fix) ended the loop but kept the early ending.
  -- Spending it is the honest version of both: the call runs until the pool
  -- is genuinely empty and lands exactly on zero, so no tail is ever left to
  -- strand anyone (user's rule, 2026-09-20).
  --
  -- The wall then rides on the SAME response, because the pool emptied on
  -- this tick and the call has to stop here. It is a `wall` rather than a
  -- raise for the same reason as step 0: a raise would roll the charge back.
  v_take := least(p_seconds, greatest(coalesce(v_balance, 0), 0));
  if v_take < 1 then v_take := p_seconds; end if;   -- nothing left: the old error
  v_balance := public.charge_credits(
    p_user_id => p_user_id,
    p_credits => v_take,
    p_action  => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('seconds', v_take, 'seconds_today', v_today,
                            'pool', p_pool, 'covered_by', 'balance',
                            'pool_emptied', v_balance - v_take <= 0));
  return jsonb_build_object('balance', v_balance, 'charged', v_take,
                            'seconds_today', v_today,
                            'scene_seconds_today', v_scenes,
                            'covered_by', 'balance')
         || case when v_balance <= 0
                 then jsonb_build_object('wall', 'insufficient_credits')
                 else '{}'::jsonb end;
end;

$function$;

CREATE OR REPLACE FUNCTION public.owner_alerts_claim(p_limit integer DEFAULT 20)
 RETURNS TABLE(kind text, key text, payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
-- The OUT parameters are called kind/key/payload and so are the columns
-- below; without this an unqualified reference is "ambiguous" and the
-- function refuses to run. Nothing here reads the OUT variables by name.
#variable_conflict use_column
begin
  return query
  with candidate as (
    -- 1. Someone became an account.
    select 'signup'::text as kind,
           i.id::text     as key,
           i.created_at   as at,
           jsonb_build_object(
             'user_id',  i.user_id,
             'email',    coalesce(u.email, i.email),
             'provider', i.provider,
             'at',       i.created_at
           ) as payload
      from auth.identities i
      join auth.users u on u.id = i.user_id
     where i.created_at > now() - interval '2 hours'

    union all

    -- 2. Money. The key is what a RENEWAL does not change.
    select 'subscription',
           s.user_id::text || ':' || s.plan_id || ':' || s.status || ':' ||
             coalesce(to_char(s.started_at, 'YYYYMMDDHH24MISS'), '-'),
           s.updated_at,
           jsonb_build_object(
             'user_id',       s.user_id,
             'email',         u.email,
             'plan',          s.plan_id,
             'status',        s.status,
             'source',        s.source,
             'trial_ends_at', s.trial_ends_at,
             'started_at',    s.started_at,
             'at',            s.updated_at
           )
      from public.user_subscriptions s
      join auth.users u on u.id = s.user_id
     where s.status in ('active', 'trialing')
       and s.updated_at > now() - interval '2 hours'

    union all

    -- 3. The paywall, ONCE per learner per day. Someone who meets it four
    -- times in an afternoon is one person deciding, not four events.
    select 'paywall',
           e.user_id::text || ':' || to_char(e.created_at at time zone 'UTC', 'YYYY-MM-DD'),
           min(e.created_at),
           jsonb_build_object(
             'user_id', e.user_id,
             'email',   max(u.email),
             'source',  min(e.properties->>'source'),
             'count',   count(*),
             'at',      min(e.created_at)
           )
      from public.client_events e
      join auth.users u on u.id = e.user_id
     where e.event = 'paywall_shown'
       and e.created_at > now() - interval '2 hours'
       and e.user_id is not null
       -- The owner's own admin accounts open the paywall to LOOK at it.
       and not exists (select 1 from public.user_credits c
                        where c.user_id = e.user_id and c.unlimited)
     group by e.user_id, to_char(e.created_at at time zone 'UTC', 'YYYY-MM-DD')
  ),
  fresh as (
    select c.kind, c.key, c.at, c.payload
      from candidate c
     where not exists (
       select 1 from public.owner_alerts a
        where a.kind = c.kind and a.key = c.key
     )
     order by c.at
     limit greatest(least(p_limit, 50), 1)
  ),
  claimed as (
    insert into public.owner_alerts (kind, key)
    select f.kind, f.key from fresh f
    on conflict (kind, key) do nothing
    returning owner_alerts.kind, owner_alerts.key
  )
  select f.kind, f.key, f.payload
    from fresh f
    join claimed c on c.kind = f.kind and c.key = f.key
   order by f.at;
end $function$;
