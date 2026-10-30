-- ---------------------------------------------------------------------------
-- 150 extra talk minutes for fd478861-c68b-4379-8720-3752f09504d9
-- (Light, comp via code SC64C6VZ), founder's grant 2026-10-30.
--
-- Extra minutes live in `user_credits.balance` (seconds) and are spent
-- BEFORE the plan's pool. Idempotent through the ledger key.
-- ---------------------------------------------------------------------------

do $$
declare
  v_uid uuid := 'fd478861-c68b-4379-8720-3752f09504d9';
  v_seconds int := 9000;
  v_new int;
begin
  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (v_uid, 'grant', v_seconds, 'founder_grant', 'migration',
          'founder-grant:2026-10-30:' || v_uid::text,
          jsonb_build_object('reason', 'extra talk minutes from the founder'))
  on conflict do nothing;
  get diagnostics v_new = row_count;
  if v_new = 0 then
    raise notice 'extra minutes: already granted';
    return;
  end if;

  insert into user_credits (user_id, balance, updated_at)
  values (v_uid, v_seconds, now())
  on conflict (user_id) do update
    set balance = user_credits.balance + v_seconds,
        updated_at = now();
end $$;
