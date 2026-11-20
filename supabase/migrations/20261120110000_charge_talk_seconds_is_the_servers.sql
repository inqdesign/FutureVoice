-- ---------------------------------------------------------------------------
-- charge_talk_seconds is the server's alone (2026-11-20, security review).
--
-- It is SECURITY DEFINER, takes the user id as an ARGUMENT and checks no
-- caller, and it was executable by anon and authenticated (functions are
-- executable by PUBLIC unless revoked). So anyone holding the public anon
-- key could POST /rest/v1/rpc/charge_talk_seconds with another learner's id
-- and spend their talk time, 600 seconds a call. Verified reachable that day
-- (a random id answered NO_CREDIT_ROW, not permission denied).
--
-- Its only caller is the talk-tick edge function, on the service role.
-- ---------------------------------------------------------------------------

revoke all on function public.charge_talk_seconds(uuid, integer, text, text, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.charge_talk_seconds(uuid, integer, text, text, jsonb, text)
  to service_role;
