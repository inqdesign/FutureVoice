-- ---------------------------------------------------------------------------
-- A second account gets the admin flag.
--
-- chjnp8wmyg@privaterelay.appleid.com (c7565d27-…) is one of the five testers
-- comped by hand in August. That comp is a CODED one since 20260911100000 —
-- `cancel_at_period_end = true`, period ending 2026-09-21 — so in six days the
-- account would have met the hard paywall. The owner wants it kept usable
-- without a subscription, which is what the admin flag already is
-- (20260706100000 / 20260809120000 / the seconds version in 20260811160000):
-- `user_credits.unlimited` charges every talk for real and refills the tank to
-- 6600 s the moment a debit would overdraw, so the account measures true spend
-- and never meets a wall. The client reads the same flag —
-- `AccountStatus.needsSubscription` is false with it, so no BillingGate ever
-- raises the paywall — and prints the plan as "Admin".
--
-- The comp is retired in the same breath, deliberately. Left standing it would
-- outrank the flag until 09-21: an entitled row means `consume_metered_seconds`
-- meters against the Light pool (150 min/period) and `begin_scene_play` claims
-- a scene count, so the account could still hit a cap the flag cannot answer.
-- With no entitlement both fall back to the balance, which now refills itself.
--
-- Idempotent: re-running flips nothing that isn't already flipped.
-- ---------------------------------------------------------------------------

do $$
declare
  v_uid uuid;
begin
  select id into v_uid
    from auth.users
   where email = 'chjnp8wmyg@privaterelay.appleid.com'
   limit 1;

  if v_uid is null then
    raise notice 'admin flag: chjnp8wmyg@privaterelay.appleid.com not present (local db?) — skipped';
    return;
  end if;

  -- The flag. A row already exists for this account; the insert is here so the
  -- migration is safe on a database where it doesn't.
  insert into user_credits (user_id, balance, unlimited, updated_at)
  values (v_uid, 6600, true, now())
  on conflict (user_id) do update
    set unlimited = true,
        balance = greatest(user_credits.balance, 6600),
        updated_at = now();

  -- The tester comp, retired now rather than on 09-21.
  update user_subscriptions
     set status = 'expired', updated_at = now()
   where user_id = v_uid
     and source = 'comp'
     and status in ('active', 'trialing', 'grace');

  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (v_uid, 'grant', 0, 'admin_flag', 'migration',
          'admin-flag:2026-09-15:' || v_uid::text,
          jsonb_build_object('note', 'tester kept on the admin auto-reset flag; Light comp retired early'))
  on conflict (idempotency_key) do nothing;

  raise notice 'admin flag: unlimited enabled for %, comp retired', v_uid;
end $$;
