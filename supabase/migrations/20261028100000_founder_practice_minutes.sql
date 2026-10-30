-- ---------------------------------------------------------------------------
-- 600 extra talk minutes for the founder's own account, for testing tutor
-- mode (2026-10-28: the Plus pool ran out mid-lesson).
--
-- Extra minutes live in `user_credits.balance` (seconds) and are spent
-- BEFORE the plan's pool (`consume_metered_seconds` step 1), so the account
-- can talk again at once. Idempotent: the ledger key is fixed, and the
-- balance is only added when that row is new.
-- ---------------------------------------------------------------------------

do $$
declare
  v_uid uuid := '72bcaa7e-3dd2-4364-b197-078ba59c1ce4';
  v_seconds int := 36000;
  v_new int;
begin
  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (v_uid, 'grant', v_seconds, 'founder_practice', 'migration',
          'founder-practice:2026-10-28:' || v_uid::text,
          jsonb_build_object('reason', 'tutor mode testing'))
  on conflict do nothing;
  get diagnostics v_new = row_count;
  if v_new = 0 then
    raise notice 'founder practice minutes: already granted';
    return;
  end if;

  insert into user_credits (user_id, balance, updated_at)
  values (v_uid, v_seconds, now())
  on conflict (user_id) do update
    set balance = user_credits.balance + v_seconds,
        updated_at = now();
end $$;
