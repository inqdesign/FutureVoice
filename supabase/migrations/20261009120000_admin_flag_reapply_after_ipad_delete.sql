-- ---------------------------------------------------------------------------
-- Re-apply the admin flag after the account was deleted a second time.
--
-- b28ca7b1-… (the account `20260916100000` flagged) is gone from auth.users:
-- on 2026-10-08 17:47 UTC the iPad (fresh install, onboarding walk-through)
-- dropped that identity for a new anonymous one — the account-delete path —
-- and every user table cascaded with it, `user_credits.unlimited` included.
-- The phone still held the dead session and met the paywall on 10-09.
--
-- Run this AFTER signing in with Apple again (same relay address). Same body
-- as 20260916100000: resolved by email, newest row first; the ledger key is
-- per user id, so it records once for the new row.
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
    raise notice 'admin flag: chjnp8wmyg@privaterelay.appleid.com not present — sign in again first';
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
          'admin-flag:2026-10-09:' || v_uid::text,
          jsonb_build_object('note', 'admin flag re-applied after account delete on iPad (was b28ca7b1)'))
  on conflict (idempotency_key) do nothing;

  raise notice 'admin flag: unlimited enabled for %', v_uid;
end $$;
