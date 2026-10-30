-- ---------------------------------------------------------------------------
-- 600 extra talk minutes for the founder's dev-build account
-- (buchhaltung.dearroro@gmail.com), for testing tutor mode (2026-10-28: its
-- Plus pool ran out mid-lesson). `20261028100000` put them on the main
-- account by mistake.
--
-- Extra minutes live in `user_credits.balance` (seconds) and are spent
-- BEFORE the plan's pool. Resolved by email, newest live row first;
-- idempotent through the ledger key.
-- ---------------------------------------------------------------------------

do $$
declare
  v_uid uuid;
  v_seconds int := 36000;
  v_new int;
begin
  select id into v_uid
    from auth.users
   where email = 'buchhaltung.dearroro@gmail.com'
     and deleted_at is null
   order by created_at desc
   limit 1;

  if v_uid is null then
    raise exception 'dev practice minutes: buchhaltung.dearroro@gmail.com not found';
  end if;

  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (v_uid, 'grant', v_seconds, 'founder_practice', 'migration',
          'founder-practice:2026-10-28:' || v_uid::text,
          jsonb_build_object('reason', 'tutor mode testing'))
  on conflict do nothing;
  get diagnostics v_new = row_count;
  if v_new = 0 then
    raise notice 'dev practice minutes: already granted';
    return;
  end if;

  insert into user_credits (user_id, balance, updated_at)
  values (v_uid, v_seconds, now())
  on conflict (user_id) do update
    set balance = user_credits.balance + v_seconds,
        updated_at = now();
end $$;
