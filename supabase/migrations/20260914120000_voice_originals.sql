-- ---------------------------------------------------------------------------
-- Keep the learner's ORIGINAL clone recording.
--
-- Until now the only copy off the phone was the sample ElevenLabs holds on
-- the voice, and that copy dies with the voice: picking an accent mints a
-- REMIXED voice and the app then deletes the clone it was made from
-- (`FutureVoiceApp.cleanupPreviousVoiceClone`), so the real recording is gone
-- seconds later. A 10-minute poller (`scripts/voice-archive.sh`) was racing
-- that and losing — the archive log shows learners whose original was already
-- HTTP 400 by the time it asked, with only the remix left behind.
--
-- `elevenlabs-voice-clone` already holds the bytes: it receives the multipart
-- body and forwards it upstream. Writing them down there is the only place
-- the recording is guaranteed to exist, so that is where it now happens.
--
-- KEPT FOR ONE DAY, then purged (20260914130000). The recording is here so a
-- clone that came out wrong can be listened to while the complaint is fresh —
-- that is the only purpose, and it is the one the consent screen states.
-- Anything longer would make this a voice corpus instead.
--
-- The bucket is PRIVATE and carries no policies at all — `storage.objects`
-- has RLS on, so with nothing granted, anon and authenticated can neither
-- read nor list it. Only the service role (the edge functions, and the
-- archive script with a revealed key) can touch it. A voice recording is
-- biometric data; it must never be one mis-scoped policy away from the web.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'voice-originals', 'voice-originals', false,
  26214400,                                   -- 25 MB; a 60 s 16 kHz mono WAV is ~1.9 MB
  array['audio/wav', 'audio/x-wav', 'audio/wave', 'audio/mpeg', 'audio/mp4', 'audio/m4a', 'audio/aac']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Where the recording landed, on the row that names the voice it built.
-- `original_path` is the FOLDER (`<user_id>/<voice_id>`), because one clone
-- may be built from several takes; null means "not saved", which is every row
-- that predates this.
alter table public.voice_clones
  add column if not exists original_path    text,
  add column if not exists original_bytes   bigint,
  add column if not exists original_saved_at timestamptz;

comment on column public.voice_clones.original_path is
  'Folder in the private voice-originals bucket holding the recording this voice was cloned from. Null for rows created before 20260914120000, and for remixed (accent) voices, which have no recording of their own.';
