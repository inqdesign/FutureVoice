-- ---------------------------------------------------------------------------
-- Every plan is a bounded pool, and the tail buys minutes (2026-09-26,
-- founder decision — "Plus unlimited is too much risk").
--
-- The numbers behind it (2026-09-26, ElevenLabs Pro tier, Apple 15%):
-- a talk minute costs ~$0.03 all in, a scene ~$0.12, and net revenue is
-- $8.49 on Light's $9.99. Light fully used (150 min + 30 scenes) cost $8.1 —
-- break-even in the US, a loss in Korea and the EU. Plus's 120 scenes alone
-- cost $14.4 of its $16.99 net, before a single minute of talk; a learner
-- talking 35 min a day (one did, on a trial) is $30/mo of talk, i.e. −$27
-- on that account. The pricing principle (docs/launch-billing.md) asks what
-- a plan earns when EVERY subscriber uses everything — so:
--
--   Light  100 min + 20 scenes   $9.99   cost $5.4  → 36% at full use
--   Plus   300 min + 60 scenes  $19.99   cost $16.2 → 5% at full use
--   +100 min (consumable)        $4.99   cost $3.0  → 29%
--
-- Plus keeps its price (founder's call, no price rise): fully used it is
-- break-even, and about −$0.2 in Korea — a loss bounded to a few dollars per
-- account, which is the whole difference from unlimited. "Unlimited" is
-- replaced by the top-up: someone who talks an hour a day pays ~$55/mo and
-- every minute above the pool clears cost. A cap here bounds
-- the cost per unit; it is not there to make the allowance unreachable
-- (Light's 100 min is "one call a day" — the mean call is 3.5 min; the
-- heaviest paying Plus learner is at ~230 min/mo, inside 300).
--
-- NOBODY WHO ALREADY BOUGHT IS TOUCHED — the same rule as 20260925140000,
-- now for the TALK half too. What a subscription was sold is stamped on the
-- row (`user_subscriptions.monthly_seconds`, `.talk_unlimited`, and
-- `.monthly_scenes` where it wasn't yet), and the plan's own figure applies
-- only where the stamp is NULL, which is everyone new. Today's four Plus
-- subscribers keep unlimited talk and 120 scenes at the price they pay;
-- the Light subscriber keeps 150 + 30; both running trials keep the 35-min
-- pro-rate they were sold. A lapsed row is not stamped — coming back later
-- is buying today's plan.
--
-- Trials: the 7/30 pro-rate formula stays for the two rows still trialing
-- (it reads the row's stamp first), but no new trial can start — the intro
-- offer is deleted in App Store Connect with 20260926100000.
--
-- Top-ups: a consumable App Store product (`talk_topups` catalog, one row:
-- 100 min) that `apple-topup` verifies and lands through `apply_talk_topup`
-- into `user_credits.balance` — the same pool invite minutes live in, which
-- `consume_metered_seconds` step 1 spends BEFORE the plan's pool. That
-- order is kept on purpose: the button lives on the spent-pool sheet, so a
-- top-up is bought when the pool is already empty, and the alternative
-- (a fourth pool with its own order) is a second implementation of the same
-- balance. `talk_allowance().bonus` reports it and the app shows it as
-- "+N min" beside the month. Step 1 skips the balance on an UNCAPPED row
-- (the four grandfathered Plus), so a top-up can never be burned by an
-- account that has no use for it.
--
-- No price changes. App Store Connect work (by hand): the intro offers
-- deleted, and a consumable `com.roro.futurevoice.talk_100` at $4.99. `docs/launch-billing.md` "2026-09-26 revision" has the table.
-- ---------------------------------------------------------------------------

-- 1. The stamps ------------------------------------------------------------

alter table public.user_subscriptions
  add column if not exists monthly_seconds integer,
  add column if not exists talk_unlimited boolean;

comment on column public.user_subscriptions.monthly_seconds is
  'Talk seconds per billing period this subscription was SOLD. NULL = follow '
  'subscription_plans.monthly_seconds. Set only to hold an existing subscriber '
  'at the size they bought when the plan itself changes (2026-09-26).';
comment on column public.user_subscriptions.talk_unlimited is
  'Whether this subscription was SOLD with uncapped talk. NULL = follow '
  'subscription_plans.talk_unlimited. TRUE only on rows that predate the '
  'bounded plans (2026-09-26); no plan sells it any more.';

-- Every LIVE row keeps what it holds today. A trialing row of any tier is
-- stamped with Light's month figure, because that is what its 7/30 pro-rate
-- is computed from (same rule as the scene stamp on 2026-09-25).
update public.user_subscriptions s
   set monthly_seconds = coalesce(s.monthly_seconds, case
         when s.status = 'trialing'
           then (select min(monthly_seconds) from public.subscription_plans
                  where tier = 'light')
         else p.monthly_seconds end),
       talk_unlimited  = coalesce(s.talk_unlimited,
                                  s.status <> 'trialing' and coalesce(p.talk_unlimited, false)),
       monthly_scenes  = coalesce(s.monthly_scenes, case
         when s.status = 'trialing'
           then (select min(monthly_scenes) from public.subscription_plans
                  where tier = 'light')
         else p.monthly_scenes end)
  from public.subscription_plans p
 where p.id = s.plan_id
   and s.status in ('trialing', 'active', 'grace');

-- 2. The new sizes, for everyone who buys from here on ----------------------
--    `daily_*` are descriptive only (monthly / 30, what the card prints as
--    "about N a day"); `abuse_seconds` only ever applies to an uncapped row.

update public.subscription_plans
   set monthly_seconds = 6000,   -- 100 min
       daily_seconds   = 200,
       monthly_scenes  = 20,
       daily_scenes    = 1
 where tier = 'light';

update public.subscription_plans
   set monthly_seconds = 18000,  -- 300 min
       daily_seconds   = 600,
       monthly_scenes  = 60,
       daily_scenes    = 2,
       talk_unlimited  = false
 where tier = 'plus';

-- 3. The meters read the row's stamp before the plan --------------------------

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

  select balance into v_balance from user_credits where user_id = p_user_id;

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
    select coalesce(sum(chars), 0) into v_period from tts_char_pool
     where user_id = p_user_id and day >= v_start
       and action in ('talk_seconds', 'scene_seconds');

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
$function$;

-- 4. Top-ups --------------------------------------------------------------
--    The catalog of consumables, read by the app for WHAT a product grants
--    (Apple stays the source of truth for what it costs, as with the plans).

create table if not exists public.talk_topups (
  apple_product_id  text primary key,
  google_product_id text,
  seconds           integer not null check (seconds > 0),
  is_active         boolean not null default true,
  created_at        timestamptz not null default now()
);

comment on table public.talk_topups is
  'Consumable talk-minute packs. One row per store product; `seconds` is what '
  'a purchase lands in user_credits.balance (2026-09-26).';

alter table public.talk_topups enable row level security;

drop policy if exists "talk_topups are readable" on public.talk_topups;
create policy "talk_topups are readable" on public.talk_topups
  for select to authenticated, anon using (is_active);

insert into public.talk_topups (apple_product_id, google_product_id, seconds)
values ('com.roro.futurevoice.talk_100', 'talk_100', 6000)
on conflict (apple_product_id) do update set seconds = excluded.seconds;

-- Lands a verified store purchase. Called by `apple-topup` (service role)
-- with the store's own transaction id as the key, so a re-sent JWS — the app
-- retries until the server has answered, and Apple re-delivers an unfinished
-- transaction on every launch — grants nothing twice, and a JWS presented by
-- a SECOND account finds the key taken and gets `applied = false` rather
-- than a second pool. The ledger row is the receipt: kind `topup`, the
-- product, the price as the store reported it.
create or replace function public.apply_talk_topup(
  p_user_id uuid,
  p_product_id text,
  p_store text,
  p_transaction_id text,
  p_metadata jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_seconds integer;
  v_key     text := p_store || '_tx:' || p_transaction_id;
  v_balance integer;
begin
  if p_user_id is null or coalesce(p_transaction_id, '') = '' then
    raise exception 'apply_talk_topup: user and transaction id required';
  end if;

  select seconds into v_seconds from talk_topups
   where is_active
     and (apple_product_id = p_product_id or google_product_id = p_product_id);
  if v_seconds is null then
    raise exception 'UNKNOWN_TOPUP' using errcode = 'P0008';
  end if;

  if exists (select 1 from usage_ledger where idempotency_key = v_key) then
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('applied', false, 'seconds', v_seconds,
                              'balance', coalesce(v_balance, 0));
  end if;

  v_balance := public.grant_credits(
    p_user_id, v_seconds, 'topup'::public.ledger_kind,
    'talk_topup', p_store || '-topup', v_key,
    coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('product_id', p_product_id, 'store', p_store,
                            'transaction_id', p_transaction_id));
  return jsonb_build_object('applied', true, 'seconds', v_seconds,
                            'balance', v_balance);
end;
$$;

revoke all on function public.apply_talk_topup(uuid, text, text, text, jsonb) from public, anon, authenticated;
