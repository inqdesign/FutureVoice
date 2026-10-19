-- ---------------------------------------------------------------------------
-- The Android update sheet has never had a row to read.
--
-- 20260915120000_app_release_android is recorded as applied in prod, but its
-- SQL never ran there: `app_release` has no `latest_beta_build` / `beta_url`
-- and no 'android' row (checked 2026-10-16). The Android client asks
-- `where platform = 'android'`, gets nothing, and stays silent by design — so
-- no Android install has ever been told a newer build exists. Testers sat on
-- 1.1.9 (versionCode 7) with 1.1.10 (12) live on the closed-test track.
--
-- Re-runs that migration's additive half (idempotent; the iOS client names its
-- columns and filters to 'ios', so it can't notice) and writes the row at what
-- Play is serving today: alpha = 1.1.10 (12). A closed-test install comes from
-- Play, so the client compares against `latest_build`.
-- ---------------------------------------------------------------------------

alter table public.app_release
  add column if not exists latest_beta_build integer;
alter table public.app_release
  add column if not exists beta_url text;

insert into public.app_release
  (platform, latest_build, latest_beta_build, min_build, latest_version, beta_url, notes_ko, notes_en)
values
  ('android', 12, 12, 0, '1.1.10', null,
   E'• 스피치 원고에서 공부하기를 켜면 문법과 표현을 짚어 주고, 문단마다 우리말 번역을 보여 줘요.\n• 원고를 내 목소리로 읽은 오디오를 만들어 들어볼 수 있어요.\n• 통화에서 ''보내기로 답하기''를 켜면 말하다 멈춰도 차례가 넘어가지 않아요. 천천히 말하고, 다 말했을 때 가운데 버튼을 눌러 보내요.\n• 자잘한 버그를 고치고 앱을 더 안정적으로 다듬었어요.',
   E'• Turn on Study in a speech script to see its grammar and expressions explained, with each paragraph translated into your language.\n• Make an audio version of your script read in your own voice.\n• Turn on Answer with Send in a call and pausing won''t end your turn. Take your time, then tap the middle button when you''re done.\n• Minor bug fixes and stability improvements.')
on conflict (platform) do update set
  latest_build = excluded.latest_build,
  latest_beta_build = excluded.latest_beta_build,
  latest_version = excluded.latest_version,
  notes_ko = excluded.notes_ko,
  notes_en = excluded.notes_en,
  updated_at = now();
