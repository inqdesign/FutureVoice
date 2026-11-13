-- One fluent reading per challenge that a learner can LISTEN to (2026-11-13,
-- founder: the challenge page opens on it fading in, and the script page
-- plays it with the words lighting up as it goes).
--
-- The scoring references (`speech_references`) keep only word times; their
-- audio was thrown away after timing. This is a separate take, in ONE voice
-- per challenge, whose audio is kept in R2 (never Supabase Storage) and whose
-- words are timed the same way. It is separate on purpose: the scoring
-- references stay exactly as they were, so nothing on a board moves.
--
-- `reference_voice` is chosen per challenge to fit its role when it is
-- published; null reads as female.

alter table public.speech_challenges
  add column if not exists reference_voice text
  check (reference_voice in ('male', 'female'));

-- Season 2's first two: the docent and the weather presenter.
update public.speech_challenges set reference_voice = 'female'
 where id = '5beec000-0000-4000-8000-00000000002b' and reference_voice is null;
update public.speech_challenges set reference_voice = 'male'
 where language = 'en' and title = 'Don''t put that umbrella away yet' and reference_voice is null;

create table if not exists public.speech_listen_audio (
  key        text primary key,          -- sha256 of version|language|gender|voice|model|text
  version    smallint not null,
  language   text not null,
  gender     text not null check (gender in ('male', 'female')),
  voice_id   text not null,
  url        text not null,             -- public R2 address of the WAV
  words      jsonb not null,            -- [{w, s, e}] in ms, timed like the references
  created_at timestamptz not null default now()
);

-- Written and read only by the `speech-reference` edge function.
alter table public.speech_listen_audio enable row level security;
