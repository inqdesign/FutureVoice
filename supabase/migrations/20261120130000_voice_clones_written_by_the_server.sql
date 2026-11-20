-- ---------------------------------------------------------------------------
-- voice_clones is written by the server only (2026-11-20, security review).
--
-- "voice_clones: owner write" was FOR ALL, so a signed-in learner could
-- insert a row of their own naming ANY voice id. The table is what `tts`,
-- the gateway's ownsVoice, voice-delete and account-delete read to decide a
-- voice is theirs: with another learner's id in a row of their own they
-- could speak in that voice, or have voice-delete remove it upstream.
-- Nothing public exposes a clone id, so it needed one to leak; the rule
-- "never another person's voice" should not rest on that.
--
-- The apps only SELECT this table. Every write is an edge function, and
-- those write with the service role since the same day (voice-clone,
-- voice-remix, voice-rename, voice-delete). APPLY ONLY AFTER those four
-- are deployed, or a new clone's row is refused.
-- ---------------------------------------------------------------------------

drop policy if exists "voice_clones: owner write" on public.voice_clones;
revoke insert, update, delete, truncate on public.voice_clones from anon, authenticated;
