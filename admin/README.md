# nawana 어드민 (live)

`https://nawana-admin.futurevoice-gateway.workers.dev/?k=<ADMIN_TOKEN>` — the
token is traded for a cookie on the first visit, so the key only ever appears
in the address bar once. Anything without it gets a 404.

Every load reads production. There is nothing to rebuild and nothing to
republish; that is the point. The page used to be a static artifact whose
numbers were gathered by hand, and on 2026-09-04 it was found a week stale
with three signups missing — the gather had run, the republish had not.

## How a page load works

1. `admin_raw()` (one SECURITY DEFINER function, `service_role` only) returns
   raw aggregates — `supabase/migrations/20260904160000_admin_console_live.sql`.
2. `src/assemble.ts` turns them into the page's data blob. This is
   `gather_admin.py` + `derive_cost.py` in JS, including the prices, which are
   not in the database (see `docs/launch-billing.md`).
3. `src/index.ts` injects the blob into `src/shell.html` and serves it.

The result is held for 60 s so a reload is free; `?fresh=1` skips that.
`/data.json` returns the same blob without the page.

## The shell is generated, not written

`src/shell.html` is `scripts/admin/build/admin.html` with the data stripped
(`scripts/admin/make_shell.py`, run by `scripts/admin/refresh.sh`). So the page
still has ONE source — `scripts/admin/base.html` + `merge_admin.py`. Edit those,
run `refresh.sh`, then `bash admin/deploy.sh`. Never hand-edit `shell.html`; it
is committed only so the Worker can bundle it, and the generator refuses to
write one that still contains an address.

## Secrets

    bash admin/deploy.sh secret ADMIN_TOKEN
    bash admin/deploy.sh secret SUPABASE_SERVICE_ROLE_KEY

The service-role key never reaches the browser — the page gets HTML, never a
token and never a Supabase call of its own.

## This page is real people

Real names, real addresses, self-intros. It is `noindex` and `no-store`, and
the token is the only door. Don't put it behind a link anyone can follow, and
don't paste a screenshot of the 사람 tab anywhere.
