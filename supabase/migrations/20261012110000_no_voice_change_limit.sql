-- No limit on changing your voice (2026-10-12, founder decision).
--
-- One change per 30 days (20261009090000_voice_changes) existed to save
-- ElevenLabs' monthly voice allowance and 160 slots. New clones are made on
-- Cartesia now (supabase/functions/_shared/cartesia.ts), which stores clones
-- without a limit — and the rule surfaced as "you can change your voice again
-- from Nov 11" to a learner who had only re-recorded once. Gone for everyone:
-- the function always answers "a change is available", which every app build
-- already reads as "no limit".
--
-- `voice_changes` keeps being written (it still says when a voice changed);
-- nothing gates on it. Same signature, so this replaces the function.

create or replace function public.voice_change_status(p_user_id uuid default auth.uid())
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object('left', 1, 'next_at', null)
  where p_user_id = auth.uid() or auth.role() = 'service_role';
$$;
