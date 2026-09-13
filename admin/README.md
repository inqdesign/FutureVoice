# nawana 어드민 (live)

`https://nawana.app/admin` — a password form (2026-09-13). The old
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
republish, and **no cache** (the 60 s hold was retired 2026-09-13 — a reload
on a launch day exists to see the signup from a minute ago). The page used to
be a static artifact whose numbers were gathered by hand, and on 2026-09-04 it
was found a week stale with three signups missing — the gather had run, the
republish had not.

## Tabs

**런칭** (default, 2026-09-12) is the launch watch: today's tiles, the signup
funnel (가입 → 클론 → 첫 통화 → 5분 → 체험 시작 → 체험 유지 → 결제) over a
cohort, the last 30 days of signups with an expandable per-user detail
(sessions, free-feature use, subscription events, errors, reviews), the App
Store server notifications (Production), the last 7 days of error/retry
events, and the last 14 days of talk sessions. **사람 · 활동 · 비용 · 마진 ·
주석** are the beta-era analysis and unchanged, except that every plan chip
now says what the subscription is DOING (체험 취소 / 해지 예정 / 무료 제공
…) rather than only its status word.

## How a page load works

1. `admin_raw()` (one SECURITY DEFINER function, `service_role` only) returns
   raw aggregates — `supabase/migrations/20260904160000_admin_console_live.sql`,
   extended by `20260912160000_admin_raw_launch_watch.sql` (timestamps,
   subscription state, `sub_events`, `recent_sessions`, `recent_events`,
   `free_recent`). Every launch-tab read is guarded, so a Worker deployed
   ahead of a migration renders the tab empty rather than failing.
2. `src/assemble.ts` turns them into the page's data blob. This is
   `gather_admin.py` + `derive_cost.py` in JS, including the prices, which are
   not in the database (see `docs/launch-billing.md`).
3. `src/index.ts` injects the blob into `src/shell.html` and serves it.

`/data.json` returns the same blob without the page (session cookie required).

## It is read on a phone

Every SVG on the page was drawn at a hardcoded 980 px, which inside a
`.scroll` card meant a phone showed the left third of each chart with no sign
the rest existed. Charts now measure the card they sit in (`innerW`) and are
redrawn by `redrawCharts()` on a tab switch — a hidden section measures 0, so
that is the first moment its real width is knowable — and on resize/rotation.
On a desktop the measured width IS ~980, so nothing about that rendering
changed.

Wide tables fold instead of scrolling: under 700 px each keeps only the
columns that answer the question it exists for, and the rest is one tap away
in the expandable detail row. The mobile block is the LAST thing in the
stylesheet on purpose — spliced in at the top it lost on source order to every
base rule below it. Grid overrides use `minmax(0,1fr)`, never a bare `1fr`,
whose automatic minimum is min-content and would size a column to the widest
table inside it.

## The shell is generated, not written

`src/shell.html` is `scripts/admin/build/admin.html` with the data stripped
(`scripts/admin/make_shell.py`, run by `scripts/admin/refresh.sh`). So the page
still has ONE source — `scripts/admin/base.html` + `merge_admin.py`. Edit those,
run `refresh.sh`, then `bash admin/deploy.sh`. Never hand-edit `shell.html`; it
is committed only so the Worker can bundle it, and the generator refuses to
write one that still contains an address.

## Secrets

    bash admin/deploy.sh secret ADMIN_PASSWORD             # the login password
    bash admin/deploy.sh secret ADMIN_TOKEN                # legacy ?k= link
    bash admin/deploy.sh secret SUPABASE_SERVICE_ROLE_KEY

The service-role key never reaches the browser — the page gets HTML, never a
token and never a Supabase call of its own.

## This page is real people

Real names, real addresses, self-intros. It is `noindex` and `no-store`, and
the token is the only door. Don't put it behind a link anyone can follow, and
don't paste a screenshot of the 사람 tab anywhere.
