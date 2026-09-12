-- ---------------------------------------------------------------------------
-- Standing comps ROLL; coded comps still END. And the owner gets their seat
-- back.
--
-- What was found on 2026-09-10, the day the owner installed 1.0.1 and saw no
-- subscription:
--
--   * The owner's Plus was a SANDBOX purchase (2026-08-20). Sandbox
--     subscriptions renew a fixed number of times and then stop; Apple sent
--     the last EXPIRED on 2026-09-08 and `apple-webhook` — correctly — wrote
--     `status = 'expired'`. Every talk since has been `covered_by: balance`,
--     spending the one-time pool.
--   * `user_credits.unlimited` was false on EVERY row. `20260706100000`
--     flagged the first-created account, but no auto-reset row has ever been
--     written for it, so the flag was lost somewhere along the minutes-native
--     conversion. The account the app calls "Admin" had been an ordinary free
--     account for weeks; it was only invisible because the Plus row covered
--     it.
--   * The five beta testers comped by hand in August were written as
--     `source = 'apple'` rows with NO receipt (`apple_original_tx_id` null)
--     and a period ending 2026-09-21. Nothing ends them — the expiry sweep
--     only touches `source = 'comp'` and the meter reads `status` alone — but
--     nothing ROLLS them either: `billing_period_start` is
--     `max(current_period_start)`, so from 09-22 the 150-minute Light pool
--     would count every second since 08-21 and never refill. Exactly the
--     failure `20260823100000` describes for a comp with no end.
--
-- The column that already exists says which comp is which.
-- `cancel_at_period_end` means "this plan STOPS at `current_period_end`"
-- (the app reads it to say End vs Refill). A comp CODE writes it true — a
-- gift of N months is meant to end. A comp given by hand to someone the
-- owner wants kept is written false, and a false on a comp now means what it
-- means on a paid plan: renew. The nightly sweep therefore does two things:
-- roll every standing comp forward by whole months until its period covers
-- today (contiguous, so the pool refills exactly at the boundary like a real
-- renewal), then expire the coded ones whose period has ended — the same
-- statement as before, narrowed to `cancel_at_period_end = true`.
--
-- The name `expire_comp_subscriptions` is kept: the cron entry names it, and
-- a rename buys a second cron row to forget.
-- ---------------------------------------------------------------------------

create or replace function public.expire_comp_subscriptions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count  integer;
  v_step   integer;
  v_guard  integer := 0;
begin
  -- 1. Standing comps: advance one month at a time until the period covers
  --    now. One step is the normal case (the sweep is nightly); the loop is
  --    for a sweep that did not run for a while. Bounded so a row with a
  --    corrupt date can never spin the job.
  loop
    update user_subscriptions
       set current_period_start = current_period_end,
           current_period_end   = current_period_end + interval '1 month',
           updated_at           = now()
     where source = 'comp'
       and status in ('active', 'trialing', 'grace')
       and cancel_at_period_end = false
       and current_period_end is not null
       and current_period_end < now();
    get diagnostics v_step = row_count;
    v_guard := v_guard + 1;
    exit when v_step = 0 or v_guard >= 120;
  end loop;

  -- 2. Coded comps end, as before.
  update user_subscriptions
     set status = 'expired', updated_at = now()
   where source = 'comp'
     and status in ('active', 'trialing', 'grace')
     and cancel_at_period_end = true
     and current_period_end is not null
     and current_period_end < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.expire_comp_subscriptions() from public, anon, authenticated;
grant execute on function public.expire_comp_subscriptions() to service_role;

-- ---------------------------------------------------------------------------
-- Data.
-- ---------------------------------------------------------------------------

-- The hand-written beta comps: an active Apple row with no receipt is not an
-- Apple row. File it as the standing comp it is. Idempotent — after this
-- runs the predicate matches nothing, and the webhook never writes a null
-- receipt id.
with fixed as (
  update user_subscriptions
     set source = 'comp',
         cancel_at_period_end = false,
         updated_at = now()
   where source = 'apple'
     and apple_original_tx_id is null
     and status in ('active', 'trialing', 'grace')
  returning user_id, plan_id, current_period_end
)
insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
select user_id, 'grant', 0, 'comp_subscription', 'migration',
       'comp:standing-2026-09-10:' || user_id::text,
       jsonb_build_object('plan_id', plan_id, 'standing', true,
                          'note', 'beta tester comped by hand in August; now rolls monthly')
  from fixed
on conflict (idempotency_key) do nothing;

-- The owner. Resolved by id, not email: `20260706100000` resolved by email
-- and fell through to "first account created" because the owner signs in
-- with Apple; since 2026-09-03 the gmail address DOES exist — as the web
-- sign-in account — so the same lookup today would flag the wrong row. The
-- id is the one the admin console already carries as OWNER_ID.
do $$
declare
  v_uid uuid := '72bcaa7e-3dd2-4364-b197-078ba59c1ce4';
begin
  if not exists (select 1 from auth.users where id = v_uid) then
    raise notice 'owner % not present (local db?) — skipped', v_uid;
    return;
  end if;

  -- The admin flag: charged for real, auto-reset when it would overdraw,
  -- never the wall (20260809120000).
  insert into user_credits (user_id, balance, unlimited, updated_at)
  values (v_uid, 6600, true, now())
  on conflict (user_id) do update
    set unlimited = true, updated_at = now();

  -- And the seat the sandbox took away, as a standing Plus comp. A future
  -- real purchase upserts over this by user_id — the webhooks own the row
  -- the moment a receipt exists.
  insert into user_subscriptions (
    user_id, plan_id, source, status,
    current_period_start, current_period_end, cancel_at_period_end, updated_at)
  values (v_uid, 'plus_monthly', 'comp', 'active',
          now(), now() + interval '1 month', false, now())
  on conflict (user_id) do update
    set plan_id = 'plus_monthly',
        source = 'comp',
        status = 'active',
        apple_original_tx_id = null,
        stripe_subscription_id = null,
        trial_ends_at = null,
        current_period_start = now(),
        current_period_end = now() + interval '1 month',
        cancel_at_period_end = false,
        updated_at = now();

  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (v_uid, 'grant', 0, 'comp_subscription', 'migration',
          'comp:standing-2026-09-10:' || v_uid::text,
          jsonb_build_object('plan_id', 'plus_monthly', 'standing', true,
                             'note', 'owner: sandbox Plus expired 2026-09-08; unlimited flag restored'))
  on conflict (idempotency_key) do nothing;
end $$;
