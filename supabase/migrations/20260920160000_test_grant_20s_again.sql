-- ---------------------------------------------------------------------------
-- 20 s again, with a fresh idempotency key, to actually WITNESS the tail
-- being cut (20260920150000 shipped but has never fired — the last test
-- happened to land on zero exactly).
--
-- Expected run: the preflight takes 1 (19 left), the first flush takes up to
-- 15 (4 left), and the next tick meets a balance under one whole tick — so
-- it writes a `pool_closed` row for the 4 s, sets the balance to 0 and walls
-- the call ONCE. The next tap is the paywall, not another call.
-- ---------------------------------------------------------------------------

do $$
declare
  v_user uuid;
begin
  select id into v_user from auth.users where email = 'inqde.lee@googlemail.com';
  if v_user is null then raise exception 'dev account not found'; end if;

  perform public.grant_credits(
    v_user, 20, 'grant'::public.ledger_kind,
    'test_grant', 'migration',
    'test_grant:20260920160000:' || v_user::text,
    jsonb_build_object('reason', 'wall test (tail must remain)',
                       'migration', '20260920160000'));
end $$;
