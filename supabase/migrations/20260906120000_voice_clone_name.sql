-- The clone's NAME lived in exactly two places, neither of them ours:
-- ElevenLabs upstream, and the device's UserDefaults
-- (`AppState.voiceDisplayName` — the user's own name, or "Future <persona>").
-- So "which user is 'Future ugg'?" could only be answered by pulling the
-- ElevenLabs voice list and joining it by hand against voice_clones.
--
-- Mirror the name next to the id it belongs to. Every function that mints or
-- renames a clone already HAS the string; none of them were writing it down.
--
-- Nullable, and deliberately not backfilled: for a row written before this
-- migration the name exists only upstream, and inventing one here would make
-- a guess indistinguishable from a record. They fill in on the owner's next
-- rename or re-record.
alter table public.voice_clones
  add column if not exists name text;

comment on column public.voice_clones.name is
  'What the clone is called on ElevenLabs (AppState.voiceDisplayName). NULL = minted before 2026-09-06, or a path that never sent a name.';
