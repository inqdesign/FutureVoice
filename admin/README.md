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
practice carried more than half of every total. Four tabs, one question each:

- **오늘** — today's numbers against yesterday, a list of what needs a person,
  and one chronological feed of the whole launch (filterable: 가입 · 통화 ·
  구독 · 문제).
- **퍼널** — 가입 → 클론 → 첫 통화 → 다시 통화 → 5분+, over launch signups
  only. Subscription is a SECOND funnel, deliberately: a trial starts within
  minutes of signing up, not after a call, so stacking it under the activity
  bars would state a sequence that never happens.
- **사람** — one row per account, everything else behind the row.
- **돈** — MRR, what the running trials are worth, unit cost, tier margin,
  burn, per-account cost.

Two defaults worth knowing:

- **The owner and the test account are OUT by default** (header toggle).
  Through 2026-09-13 the owner alone carried 57% of every turn ever logged.
  The owner's own subscription is also excluded from revenue — counting it
  printed "결제 구독 0 · 월 $19.99" on one tile, which is what gave it away.
- **The 돈 tab ignores the toggle.** Cost and revenue are account facts, not
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

Charts measure the card they sit in (`innerW`) and are redrawn by
`redrawCharts()` on a tab switch — a hidden section measures 0, so that is the
first moment its real width is knowable — and on resize. Wide tables fold
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
and don't paste a screenshot of the 사람 tab anywhere.
