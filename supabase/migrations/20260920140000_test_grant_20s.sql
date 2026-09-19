-- ---------------------------------------------------------------------------
-- 20 s of talk on the dev account, to watch the pool close once
-- (20260920130000). The run: the preflight takes 1, the first flush takes up
-- to 15, and the 4 s left cannot pay a whole tick — so that tick closes the
-- pool and walls the call. Expect ONE wall, a balance of 0, and the paywall
-- on the next tap rather than another call.
--
-- Under 15 s would test nothing: the pool closes on the preflight and the
-- call never starts.
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
    'test_grant:20260920140000:' || v_user::text,
    jsonb_build_object('reason', 'wall test', 'migration', '20260920140000'));
end $$;
