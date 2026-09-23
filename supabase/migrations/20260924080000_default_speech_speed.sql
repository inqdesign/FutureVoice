-- ---------------------------------------------------------------------------
-- The fluent self's DEFAULT speaking speed, tunable without an app release.
--
-- `SpeechSpeed` (2026-09-23) ships three rungs — Normal 1.0 · Relaxed 0.9 ·
-- Slow 0.8 — and 0.9 is what a learner who never opens the setting gets. That
-- number was chosen by ear on five probe lines before anyone had lived with
-- it; the first week of real calls is what says whether it is right. Without
-- this column, changing it means a build, App Review, and waiting for people
-- to update — by which time every install is already frozen on the old value.
--
-- NULL means "use the app's own default", which is the honest resting state:
-- the column is written only to CHANGE the value, never to restate it, so a
-- row nobody has touched can't drift away from the code.
--
-- Only the DEFAULT rung moves. Normal is upstream's own 1.0 and Slow is the
-- floor a learner deliberately reaches for; retuning those is a ladder change
-- that belongs in a build, with ears on it. Cached audio is unaffected by
-- construction: the default rung's cache tag is empty (PhraseAudioStore keeps
-- what is already produced), so lines synthesized at the old default keep
-- playing as they were.
-- ---------------------------------------------------------------------------

alter table public.app_release
  add column if not exists default_speech_speed numeric;

comment on column public.app_release.default_speech_speed is
  'ElevenLabs voice_settings.speed for the DEFAULT rung of Me → Voice → Speaking speed. NULL = the app''s own default (0.9). Clamped client-side to 0.7–1.2; anything outside is ignored, never an error.';
