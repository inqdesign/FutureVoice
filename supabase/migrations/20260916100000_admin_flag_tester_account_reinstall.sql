-- ---------------------------------------------------------------------------
-- The admin flag follows the PERSON, not the row — re-flag after a reinstall.
--
-- 20260915140000 flagged chjnp8wmyg@privaterelay.appleid.com (c7565d27-…).
-- The next morning that account was deleted and the app set up from scratch,
-- which minted a NEW auth user (b28ca7b1-…, 2026-09-16 08:03) under the same
-- relay address: balance 0, `unlimited = false`, no subscription — so the
-- first tap on Talk met the hard paywall the flag existed to remove. Nothing
-- carried over because the flag lives on `user_credits.user_id`, and Apple's
-- relay address is the only thing the two rows share.
--
-- Same flag, same mechanics (charged for real, tank refilled to 6600 s before
-- an overdraw; `AccountStatus.needsSubscription` false on the client, plan
-- printed as "Admin"). Resolved by email, NEWEST row first, so a further
-- delete-and-reinstall can be answered by re-running this file with a new
-- version stamp rather than by chasing uuids.
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
     and deleted_at is null
   order by created_at desc
   limit 1;

  if v_uid is null then
    raise notice 'admin flag: chjnp8wmyg@privaterelay.appleid.com not present (local db?) — skipped';
    return;
  end if;

  insert into user_credits (user_id, balance, unlimited, updated_at)
  values (v_uid, 6600, true, now())
  on conflict (user_id) do update
    set unlimited = true,
        balance = greatest(user_credits.balance, 6600),
        updated_at = now();

  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (v_uid, 'grant', 0, 'admin_flag', 'migration',
          'admin-flag:2026-09-16:' || v_uid::text,
          jsonb_build_object('note', 'admin auto-reset flag re-applied after account delete + reinstall (was c7565d27)'))
  on conflict (idempotency_key) do nothing;

  raise notice 'admin flag: unlimited enabled for %', v_uid;
end $$;
