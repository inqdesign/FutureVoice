-- `profiles.setup_at`: was this row ever written by the app?
--
-- The three learner columns have had defaults since the first migration
-- ('ko' / 'en' / 'b1') and `handle_new_user` inserts `(id)` alone, so every
-- one of the 31 rows on 2026-09-14 held the same three values and none of
-- them was an answer. A console that read `target_language` would have
-- reported every learner as an English learner by construction — which is the
-- bug it looks like a fix for.
--
-- `LearnerSetupSync` (client) now upserts the real choice and stamps this
-- column. NULL therefore means "no build has written this row": the values
-- are the trigger's and must not be read as a choice. It fills from the next
-- release onward, on each learner's next launch; there is nothing to
-- backfill, because the answer was never stored anywhere we can reach (the
-- client sent it to PostHog only).
alter table public.profiles
  add column if not exists setup_at timestamptz;

comment on column public.profiles.setup_at is
  'When the app last wrote this row. NULL = the other columns are trigger defaults, not the learner''s choice.';
