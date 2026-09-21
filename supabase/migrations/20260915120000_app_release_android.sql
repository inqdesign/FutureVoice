-- ---------------------------------------------------------------------------
-- The same "is this build behind?" answer, for the Android app.
--
-- ADDITIVE ONLY, and deliberately so: the shipped iOS client reads this table
-- and must not notice this migration ran.
--
--   * The iOS query is
--       select latest_build,latest_testflight_build,min_build,latest_version,
--              notes_ko,notes_en
--       from app_release where platform = 'ios' limit 1
--     (`AppUpdateService.swift`, and it has named those columns and that
--     filter since the feature was first committed — there has never been a
--     build on a phone that reads this table without the platform filter).
--     A NEW ROW is invisible to a query filtered to 'ios'; the `limit(1)` is
--     applied after the filter, so it still returns the one iOS row.
--   * NEW COLUMNS are invisible to a select that names its columns, and both
--     are nullable with no default, so every existing row keeps behaving
--     exactly as before.
--   * Nothing is renamed, no column changes meaning, and no function's
--     behaviour changes for an iOS caller. `scripts/beta.sh` writes
--     `where platform = 'ios'` on both of its updates and is untouched.
--
-- Two audiences on Android, exactly as on iOS, because the two update from
-- different places:
--
--   latest_build       what a PLAY install should be on. Written only once a
--                      build is actually live on the store — the equivalent
--                      of `beta.sh released`.
--   latest_beta_build  what an internal-test / sideloaded install should be
--                      on. Written on every upload.
--
-- It is NOT `latest_testflight_build`. That column names an Apple channel and
-- is read by the iOS client that is already on phones; repurposing it to also
-- mean "the Android beta track" is exactly the kind of meaning change this
-- migration is forbidden from making. One extra nullable column is cheaper
-- than a column that means two things.
--
-- `min_build` is unchanged and already applies per row: below it the client
-- is not safe to keep running, which is true regardless of where it came from.
-- ---------------------------------------------------------------------------

alter table public.app_release
  add column if not exists latest_beta_build integer;

-- Where a BETA install goes to get the new build. On iOS this is a fixed
-- `itms-beta://` URL the client can hardcode; Play's internal-test opt-in link
-- is per-track and does not exist until the track does, so the server carries
-- it and the client falls back to the store page while it is null.
alter table public.app_release
  add column if not exists beta_url text;

comment on column public.app_release.latest_beta_build is
  'Newest build on the pre-release track (Android: internal test / direct APK). Set on every upload.';
comment on column public.app_release.beta_url is
  'Where a pre-release install gets the new build. Null = send them to the store page.';

-- The Android row. latest_build 0 with min_build 0 is the honest starting
-- state: nothing is live on Play yet, so no install can be behind and the
-- sheet never appears. The check constraint (min_build <= latest_build) holds.
insert into public.app_release
  (platform, latest_build, latest_beta_build, min_build, latest_version, beta_url, notes_ko, notes_en)
values
  ('android', 0, 0, 0, null, null,
   '유창해진 미래의 내 목소리와 매일 통화하면서 언어를 배우는 앱, 나와나예요.',
   'nawana — learn a language by talking with your own fluent voice, every day.')
on conflict (platform) do nothing;
