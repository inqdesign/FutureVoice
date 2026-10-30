# nawana 어드민 (live)

`https://nawana.app/admin` — a password form. The old
`https://nawana-admin.futurevoice-gateway.workers.dev/?k=<ADMIN_TOKEN>` link
still works and is the same Worker: `web/vercel.json` rewrites `/admin` on
nawana.app to it, so the browser stays on nawana.app and the session cookie is
a nawana.app cookie. Anything without a session gets the form (a script asking
for `data.json` gets a 404).

The password is the Worker secret `ADMIN_PASSWORD` (falls back to
`ADMIN_TOKEN` while unset). Change it with
`bash admin/deploy.sh secret ADMIN_PASSWORD` — the cookie carries a hash of
the secret, so a new password logs every browser out at once. Wrong guesses
are throttled per IP. `/admin/logout` clears the cookie ("나가기" in the header).

Every load reads production. There is nothing to rebuild, nothing to
republish, and **no cache** — a reload on a launch day exists to see the
signup from a minute ago.

## Dear RoRo lives here too (2026-10-25)

`/admin/roro` — the same door, a second app. The owner wanted one dashboard
for both, built as a copy of this page first and redesigned together after.
An app switch sits at the top of both sidebars.

- Page: `scripts/admin/roro.html` → `admin/src/roro.html` (refresh.sh copies
  both). It has **no stylesheet of its own**: the Worker pastes page.html's
  `<style>` in at `<!--__SHARED_STYLE__-->`, so a redesign of page.html's CSS
  is a redesign of both.
- Data: `src/roro.ts`, read thin from Dear RoRo's Supabase
  (`DEARRORO_SUPABASE_URL` var + `DEARRORO_SERVICE_ROLE_KEY` secret) plus
  PostHog `app = dearroro` (same project and key as nawana). No migration.
  Profiles is the people list — the Auth admin API on that project answers 500
  for some pages of users, so it only fills in.
- 2.0 is not released yet, so its anonymous accounts count as the owner's
  tests until `V2_RELEASE` in roro.html is set.

## The page is ONE file

`scripts/admin/page.html`. Edit it, run `./scripts/admin/refresh.sh` (which
copies it to `admin/src/shell.html` after checking it still has its
`__ADMIN_DATA__` placeholder and holds no email addresses), then
`bash admin/deploy.sh`.

**Until 2026-09-14 it was not one file**, and that is why it needed rewriting:
`base.html` plus 1,165 lines of Python string surgery in `merge_admin.py`,
with `gather_admin.py` / `derive_cost.py` / `make_shell.py` around it. Nobody
could see the whole page at once, so every addition became another `sub()`
call, and it reached five tabs and twenty-five sections that said the same
things in three places. All five files are deleted; they are in git history.

## What the page answers

The window starts on **launch day, 2026-09-12** (`admin_raw`'s `w.start`).
Before that the console was windowed from 2026-08-10 and the owner's own beta
practice carried more than half of every total.

**Pages in a sidebar** (2026-10-21). Six tabs across the top were replaced by
a left sidebar listing the pages (대시보드 · 전환 · 사용 패턴 · 사람 · 돈 ·
마케팅). Only the open page is shown, and under it in the sidebar its
sections are anchor links, lit as you scroll. A single page holding all 40
sections was tried the same day and was harder to get around than the tabs;
don't go back to it. Pages are `.grp`, sections `section[data-nav]` (a new
section only needs a `data-nav` to appear in the sidebar), and a hash names
either, so `…/admin#heatmapSec` opens that page at that section. On a phone
the sidebar folds into a top bar with a 목차 drawer.

- **대시보드** (first screen) — the LIVE MAP first (the part looked at
  most; not sticky any more, and its 24 h list scrolls inside its card), then
  today's tiles, the money tiles, 지금 봐야 할 것
  beside 일어난 일, both funnels, and the heatmap. The heatmap fits every
  day by shrinking its cells (to 9 px) and no longer has an ID column — the
  ids are on the person card. One line per row on a wide screen (language, voice, build and invite are on the person card). A group over 30 rows shows the 25 most recent
  and a "N명 더 보기".
- **마케팅** is a section like the rest, re-read only while it is in view.

The groups, in order:

- **퍼널** (now split between the dashboard and 전환·리텐션) — 가입 → 클론 → 첫 통화 → 다시 통화 → 5분+, over launch signups
  only. Subscription is a SECOND funnel, deliberately: a trial starts within
  minutes of signing up, not after a call, so stacking it under the activity
  bars would state a sequence that never happens.
- **사람** — one row per account, everything else behind the row, plus two
  distribution sections above it: which languages are being learned, and
  **어느 레벨이 오나** — the onboarding level (`profiles.proficiency`, only
  where `setup_at` says a build reported it) with what each level actually
  did beside it. The level is SELF-DECLARED and the section says so: the
  app's measured CEFR lives in the session summary's `scorecard.cefr_level`
  and never leaves the phone, so a count of levels on its own says nothing
  about where to put effort — every row carries 통화한 사람 · 1인당 통화 ·
  이틀 이상 · 체험·결제 next to the headcount, because the group worth
  working on is the big one that doesn't come back, not the big one.
  Accounts on a build older than `LearnerSetupSync` are their own row
  ("아직 안 들어옴"), never folded into B1 — that value is the signup
  trigger's default.
- **돈** — MRR, what the running trials are worth, Gemini by feature, plan
  usage, what a fully used plan costs, burn and per-account cost, fair use.
  TTS cost comes from the ledger at `provider_rates`' Cartesia rate; the
  call's own voice is streamed by the gateway, which writes no characters,
  so call minutes are priced at ~500 characters a minute.

Two defaults worth knowing:

- **The owner and the test account are OUT by default** (header toggle).
  Through 2026-09-13 the owner alone carried 57% of every turn ever logged.
  The owner's own subscription is also excluded from revenue — counting it
  printed "결제 구독 0 · 월 $19.99" on one tile, which is what gave it away.
- **The 돈 group ignores the toggle.** Cost and revenue are account facts, not
  launch-window ones.

**Turning auto-renew off is not churn until someone has used the app.** All
five of the launch's cancellations happened 2–12 minutes after signing up and
before the first call. The page splits them (써보기 전에 끔 / 써보고 나서 끔)
because the two mean opposite things, and only the second is a verdict.

## How a page load works

1. `admin_raw()` (one SECURITY DEFINER function, `service_role` only) returns
   raw aggregates. Latest migration:
   `20260914090000_admin_raw_launch_window.sql`.
2. `src/assemble.ts` turns them into the page's data blob — indices, origins,
   unit economics and revenue. Prices are not in the database; they live here
   and in `docs/launch-billing.md`.
3. `src/index.ts` substitutes the blob for `__ADMIN_DATA__` in the shell and
   serves it. `/data.json` returns the same blob without the page.

Every launch-tab read is guarded, so a Worker deployed ahead of a migration
renders that part empty rather than failing.

## It is read on a phone

**The page must start with its own `<meta name="viewport">`** — until
2026-09-29 it didn't (only the login form had one), so a phone laid it out at
980 px and shrank it, and none of the rules below ever ran. On a phone the
누가 어느 날 말했나 heatmap shows only the most recent days that fit at a
readable size, and puts 남은 통화 (the pool left plus packs/invites, or a free
account's balance) under each name; on a wide screen that is its own column.

Charts measure the card they sit in (`innerW`) and are redrawn by
`redrawCharts()` on resize (the map waits until it scrolls into view, since an
off-screen map fits its bounds to nothing). Wide tables fold
under 700 px to the columns that answer the question, and the rest is one tap
away in the expandable row. The mobile block is the LAST thing in the
stylesheet on purpose. Grid overrides use `minmax(0,1fr)`, never a bare `1fr`,
whose automatic minimum is min-content.

## Secrets

    bash admin/deploy.sh secret ADMIN_PASSWORD             # the login password
    bash admin/deploy.sh secret ADMIN_TOKEN                # legacy ?k= link
    bash admin/deploy.sh secret SUPABASE_SERVICE_ROLE_KEY

## This page is real people

Real names, real addresses, self-intros. It is `noindex` and `no-store`, and
the password is the only door. Don't put it behind a link anyone can follow,
and don't paste a screenshot of the 사람 group anywhere.
