-- ---------------------------------------------------------------------------
-- One row that says which build is current, and which is too old to keep using.
--
-- The app has no way to know either. Apple's iTunes lookup endpoint answers
-- only for what is PUBLIC on the App Store, which is wrong twice over here:
-- it says nothing before the first release, and it would tell every TestFlight
-- tester they are behind while they are in fact ahead. A row we write is the
-- only source that can describe a build before Apple has one.
--
-- Two numbers, because they answer different questions:
--
--   latest_build     what a current install should be on. Behind it → a sheet
--                    that can be dismissed, shown once per build.
--   min_build        below this the app is not safe to keep using. The sheet
--                    has no way out. Reserved for the case that actually
--                    happened on 2026-08-20/21: the billing model changed
--                    under builds already on phones, and an old client went on
--                    describing allowances that no longer existed. Raise this
--                    only when the SERVER has moved somewhere the old client
--                    misreports — never to push an optional update.
--
-- Build numbers, not version strings, because the version string is a label
-- the team can move for marketing reasons (it went 1.1.0 → 1.0 on 2026-08-21)
-- while the build number is the only thing that has to keep increasing for
-- App Store Connect to accept an upload at all. Comparing labels would have
-- told every 1.1.0 tester they were ahead of 1.0.
--
-- Readable by anyone, including a signed-out launch — the same policy shape
-- `subscription_plans` and `core_club_config` already use. It holds no
-- personal data and the app needs it before it has a session.
-- ---------------------------------------------------------------------------

create table if not exists public.app_release (
  platform      text primary key default 'ios',
  latest_build  integer not null,
  min_build     integer not null default 0,
  latest_version text,
  notes_ko      text,
  notes_en      text,
  updated_at    timestamptz not null default now(),
  constraint app_release_min_not_above_latest check (min_build <= latest_build)
);

comment on table public.app_release is
  'What the client compares its own CFBundleVersion against. One row per '
  'platform. Bump latest_build with every TestFlight/App Store upload; raise '
  'min_build ONLY when an older client would misreport the server.';

insert into public.app_release (platform, latest_build, min_build, latest_version, notes_ko, notes_en)
values ('ios', 14, 0, '1.0',
        '초대로 받은 시간을 이번 달 통화 시간보다 먼저 쓰도록 고쳤어요. 초대 공유에 앱 링크도 함께 나가요.',
        'Invite minutes are now spent before your monthly time, and sharing an invite carries an App Store link.')
on conflict (platform) do update
  set latest_build = excluded.latest_build,
      latest_version = excluded.latest_version,
      notes_ko = excluded.notes_ko,
      notes_en = excluded.notes_en,
      updated_at = now();

alter table public.app_release enable row level security;

drop policy if exists "app_release: read" on public.app_release;
create policy "app_release: read" on public.app_release for select using (true);
