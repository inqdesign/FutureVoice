-- The default accent for builds that can't apply it themselves (2026-10-08).
--
-- A clone made from a native-language recording has no accent of its own in
-- the target language, and the model invents one per line — ~75% of English
-- lines came out Indian for a Korean take (measured 2026-09-30), and German
-- learners hit the same. Builds from 1.1.5 remix every new clone into the
-- language's default accent themselves (`AppState.applyDefaultAccent`) and
-- say so on the clone request (`accent_by_app`). Builds already in the
-- stores don't, and don't tell the server which language is being learned.
--
-- So for THOSE clones the server does it at the speech side: the first time
-- the plain clone speaks English or German, `_shared/default-accent.ts`
-- remixes it once and records the remix here; every later line in that
-- language — `elevenlabs-tts` and the gateway's call — is synthesized with
-- the remix. The app keeps its own id (its caches, its deletes), so nothing
-- on the phone changes.
--
-- The remix is stored as its own `voice_clones` row, INACTIVE, so every sweep
-- that deletes "every voice this user has a row for" (account-delete,
-- cleanup-anonymous-voices, park-idle-voices) deletes it too, and the app's
-- restore never adopts it. `elevenlabs-voice-delete` cascades from the source.

alter table public.voice_clones
  -- Set by elevenlabs-voice-clone on a clone from a build that did NOT say
  -- it applies the accent itself. Only these rows ever get a speak-as voice.
  add column if not exists accent_by_server boolean not null default false,
  -- The remix this voice speaks with, the language it is for, and its accent.
  add column if not exists speak_as_voice_id text,
  add column if not exists speak_as_language text,
  add column if not exists speak_as_accent text,
  -- A remix in progress (concurrent first lines wait on it rather than make
  -- a second one). Stale after two minutes.
  add column if not exists speak_as_started_at timestamptz;
