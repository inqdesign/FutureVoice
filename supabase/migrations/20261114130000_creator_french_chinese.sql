-- The application form offers French and Chinese (founder, 2026-11-14): both are target
-- languages in the app since 1.3.4. The app's codes are fr and zh, which is what
-- talk_seconds_by_language is keyed by, so the desk's live minutes match.
alter table public.creator_applications
  drop constraint if exists creator_applications_language_check;
alter table public.creator_applications
  add constraint creator_applications_language_check
  check (language in ('en', 'de', 'ja', 'es', 'fr', 'zh', 'ko'));
