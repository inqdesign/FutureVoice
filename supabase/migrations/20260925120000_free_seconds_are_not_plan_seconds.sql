-- ---------------------------------------------------------------------------
-- The ten free minutes stop being spent twice (2026-09-25).
--
-- Reported by the founder, and measured on the one account it has reached:
-- d48b0216 spent the whole 600 s free pool at 05:56 UTC on 2026-09-24, bought
-- a Plus trial at 06:11 the same day, and the trial's FIRST tick already read
-- `seconds_period: 608`. The trial pool is Light's month pro-rated 7/30 =
-- 2,100 s, so a third of it was gone before a word was said, and they were
-- walled by DAILY_CAP_REACHED that evening after 1,493 s of trial talk. They
-- were compensated by hand with 1,800 s (20260924190000); this is the rule
-- behind it.
--
-- WHY IT HAPPENED. Step 1 ("invite minutes first") ends with the promise that
-- a tick paid from the balance never reaches `tts_char_pool`, so "the month's
-- own figures keep describing the month". That promise held for subscribers
-- only. On an account with NO subscription row the `select ... into
-- v_entitled, v_trial, v_unlimited, v_cap` finds nothing and PL/pgSQL sets
-- every target to NULL; step 1's guard `not (v_unlimited and p_pool =
-- 'talk_seconds')` is then NULL, and an IF reads NULL as false. So a free
-- learner's every tick fell past step 1, through the unconditional pool
-- insert, into step 3 — which pays from the balance. This is the same NULL
-- trap step 0's comment already warns about (`v_entitled is not true`, never
-- `not v_entitled`), one branch further down.
--
-- The seconds then sat in that day's `talk_seconds` row, and
-- `billing_period_start()` for a subscription bought the same day is that
-- same day — so the plan's period sum swallowed them. Only a same-day start
-- is affected: a learner who spends the free pool on Tuesday and subscribes
-- on Wednesday was always fine, which is why one account has been hit and not
-- twenty.
--
-- THE FIX is to guard the insert with step 2's own condition, so the pool
-- records a tick only when the PLAN is about to pay for it.
--
-- Not fixed by repairing step 1's NULL, although that is the shorter diff: it
-- would route free ticks through step 1, which would rename their ledger
-- `covered_by` from 'balance' to 'invite_minutes' — the key 20260921120000
-- reads to size every top-up to the free offer — and would drop step 3's
-- spend-the-pool-to-zero rule (20260920190000, user's rule), taking whole
-- ticks only and stranding the tail the rule exists to spend.
--
-- BLAST RADIUS. Three readers sum this pool per billing period —
-- `consume_metered_seconds` itself, `talk_allowance()` (Me -> Usage) and
-- `admin_raw()`'s `talk_used`, which reads it for subscribers against their
-- cap — and all three get more correct in the same direction. The free daily
-- caps (`charge_tts_pooled`, `charge_tts_free_pooled`,
-- `charge_turn_tts_floored`, `talk_window_cap`) key on their own `action`
-- values and are untouched. `seconds_today` in the response of a FREE
-- account's tick becomes 0: `TalkMeter` reads it only where `daily_cap` is
-- non-null, which a free account never has, and the Home ring's minutes come
-- from `TalkTimeLog` on the phone.
--
-- History is not rewritten. The seconds already in the pool stay there; the
-- one learner they walled has their 1,800 s.
-- ---------------------------------------------------------------------------

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

    -- An uncapped plan is sold as having no limit, so the fair-use figure is
    -- NOT a wall: crossing it writes a row we can look at and changes nothing
    -- the learner sees. A person cannot reach it by talking (it is an hour a
    -- day, every day); what reaches it is a script.
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

$function$
;
