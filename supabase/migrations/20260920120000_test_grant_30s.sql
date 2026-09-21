-- ---------------------------------------------------------------------------
-- 30 s of talk on the dev account, to test the pool closing at the wall
-- (20260920110000). One tick is 15 s, so the run is: preflight takes 1,
-- the first flush takes 15, the second flush wants 15 against 14 — which is
-- exactly the remainder case. Expect ONE wall, a balance of 0 afterwards,
-- and a paywall on the next tap.
-- ---------------------------------------------------------------------------

do $$
declare
  v_user uuid;
begin
  select id into v_user from auth.users where email = 'inqde.lee@googlemail.com';
  if v_user is null then raise exception 'dev account not found'; end if;

  perform public.grant_credits(
    v_user, 30, 'grant'::public.ledger_kind,
    'test_grant', 'migration',
    'test_grant:20260920120000:' || v_user::text,
    jsonb_build_object('reason', 'wall test', 'migration', '20260920120000'));
end $$;
