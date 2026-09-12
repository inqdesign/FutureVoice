-- ---------------------------------------------------------------------------
-- The update sheet told App Store users about builds the App Store didn't have.
--
-- `app_release.latest_build` is written by scripts/beta.sh the moment an
-- upload succeeds — which is the moment the build exists on TESTFLIGHT, a day
-- or more before App Review lets it onto the store. Every App Store install
-- then saw "There's a new version" with a button to a store page still
-- showing the old one (found 2026-09-11, on the first post-launch build).
-- The link itself was right; the timing wasn't.
--
-- Two numbers now, because the two audiences update from different places:
--
--   latest_testflight_build   what a TestFlight install should be on. Written
--                             by beta.sh on upload, as before.
--   latest_build              what an APP STORE install should be on. Written
--                             only when the build is actually live there —
--                             `scripts/beta.sh released`, which checks the
--                             store's own lookup before touching it.
--
-- `min_build` is unchanged and applies to both: it says the server has moved
-- somewhere an older client misreports, which is true regardless of where the
-- client came from.
-- ---------------------------------------------------------------------------

alter table public.app_release
  add column if not exists latest_testflight_build integer;

-- Everything on TestFlight today is at least the current latest_build.
update public.app_release
   set latest_testflight_build = greatest(coalesce(latest_testflight_build, 0), latest_build)
 where platform = 'ios';

comment on column public.app_release.latest_build is
  'Newest build LIVE ON THE APP STORE. Set by `beta.sh released` after App Review, never on upload.';
comment on column public.app_release.latest_testflight_build is
  'Newest build on TestFlight. Set by beta.sh on every successful upload.';
