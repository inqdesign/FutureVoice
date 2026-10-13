-- A speech-challenge take with no photo was refused (2026-10-13).
-- The app encodes `p_avatar: String?` with Swift's synthesized Encodable,
-- which LEAVES OUT a nil key instead of sending null. So a learner with no
-- photo (or "Show my photo" off) called submit_speech_challenge_take with
-- nine named arguments, PostgREST found no function taking exactly those,
-- and every take failed: "Perhaps you meant to call the function …". One
-- learner, 25 takes, none on the board.
--
-- An overload without p_avatar, forwarding null. A separate signature rather
-- than a default on p_avatar: Postgres would need a default on every argument
-- after it too, and PostgREST picks the overload by its set of argument
-- names, so the two never collide. Fixes every shipped build at once.

create or replace function public.submit_speech_challenge_take(
  p_challenge uuid, p_display_name text,
  p_overall integer, p_accuracy integer, p_pace integer, p_pause integer,
  p_filler integer, p_steadiness integer, p_seconds integer)
returns table(rank integer, previous_rank integer, entrants integer, best integer, improved boolean)
language sql security definer set search_path = public as $$
  select * from public.submit_speech_challenge_take(
    p_challenge, p_display_name, null::text,
    p_overall, p_accuracy, p_pace, p_pause, p_filler, p_steadiness, p_seconds);
$$;

revoke all on function public.submit_speech_challenge_take(
  uuid, text, integer, integer, integer, integer, integer, integer, integer) from public, anon;
grant execute on function public.submit_speech_challenge_take(
  uuid, text, integer, integer, integer, integer, integer, integer, integer) to authenticated;

notify pgrst, 'reload schema';
