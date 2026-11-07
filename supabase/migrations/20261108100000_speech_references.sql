-- Native reference readings for Season 2's speech score (2026-11-08).
--
-- One row per (version, language, gender, voice, script text), keyed by its
-- hash: the words of a native TTS reading with their times in ms, as the
-- `speech-reference` edge function timed them (Azure, the calibration's own
-- method). Made once per script by whoever opens it first, read by everyone.
--
-- Written and read only by the edge function with the service role: no
-- client policies (RLS on, nothing granted).

create table if not exists public.speech_references (
  key        text primary key,
  version    smallint not null,
  language   text not null,
  gender     text not null check (gender in ('male', 'female')),
  voice_id   text not null,
  words      jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.speech_references enable row level security;
