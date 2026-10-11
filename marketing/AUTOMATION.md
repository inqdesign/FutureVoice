# Marketing automation — the contract

Founder decision (2026-10-11): every new or updated feature ships with marketing, without
waiting for the founder. A build upload STARTS the team; the App Store release FINISHES it;
a piece that passes review is SCHEDULED and posts by itself unless the founder vetoes it in
the admin console within the veto window. Views and engagement are collected daily and
shown in the same console.

Every part below is built by a different hand; this file is the interface between them.
Change it first, then the code.

## 1. Triggers

    scripts/marketing/kickoff.sh upload  <version> <build>   # called by scripts/beta.sh after a TestFlight upload
    scripts/marketing/kickoff.sh release <version> <build>   # called by scripts/release-watch.sh after `beta.sh released`

`kickoff.sh` runs headless Claude Code in the background and returns at once:

    claude -p "/marketing auto <phase> <version> <build>" \
      --permission-mode acceptEdits --allowedTools "<the list in kickoff.sh>" \
      > marketing/logs/<date>-<phase>-<version>.log 2>&1 &

- **upload**: find what changed since the last released build (git log since the commit
  of the last `released` build, `fastlane/metadata/*/release_notes.txt`, CLAUDE.md sections
  touched), pick at most TWO pieces worth telling (new or visibly changed features only;
  fixes don't get a carousel), run the pipeline to a reviewer PASS, render, upload media,
  register each piece → stage `ready` (not scheduled yet).
- **release**: for this version's `ready` pieces, re-check facts against what actually
  shipped (a feature cut in review must not be advertised), then schedule them:
  `scheduled_at = now() + VETO_HOURS`. If no upload run happened, do the upload work first.
- A run never posts by itself — posting is the scheduler's job, after the veto window.
- Disk: renders are big; delete a piece's local `renders/` once its media is in R2 —
  with `scripts/marketing/prune-renders.sh <slug>` (refuses until the slides are registered;
  the only delete the headless run is allowed).
- One run per phase+version at a time (lock `marketing/logs/.run-<phase>-<version>.lock`);
  a second kickoff while one is alive starts nothing. Each run writes a `run_start` and a
  `run_end` event with **no piece** (`piece_id` NULL, message `"<phase> <version> (<build>)"`).
- `MARKETING_AUTOPILOT=0` disables kickoff (and the two hooks).
- The headless run's shell is limited to: `python3 scripts/marketing/db.py`, `media.sh`,
  `prune-renders.sh`, `capture.sh`, `compare.sh`, `record.mjs` (node 22), `scheduler.py
  --dry-run`, `metrics.py --dry-run`, ffmpeg, ffprobe, git log/diff/show, ls, cat, sips and
  `community.py news-add` (drafts; `--publish` and `news-publish` are denied). Anything
  else — git writes, deploys, posting — is refused by permissions, not by good manners.

## 2. Database (Supabase, migration `supabase/migrations/20261011121500_marketing.sql`)

    marketing_pieces
      id uuid pk default gen_random_uuid()
      slug text unique not null            -- = marketing/content/<slug>/
      version text, build int, phase text  -- 'upload' | 'release' | 'manual'
      stage text not null default 'idea'
        -- idea · brief · copy · design · review · ready · scheduled · vetoed · posting · posted · failed
      title_ko text, title_en text, one_message text
      review_verdict text, review_fixes int
      caption_ko text, caption_en text, threads_text text
      slides jsonb not null default '[]'   -- [{n, kind:'video'|'image', mp4:'<key>', png:'<key>', jpg:'<key>', jpg_web:'<key>', alt_ko, alt_en}]
                                           -- jpg = 1080×1350 JPEG (Instagram takes JPEG only), jpg_web = 720×900
      scheduled_at timestamptz, vetoed_at timestamptz, veto_reason text
      posted_at timestamptz
      ig_media_id text, ig_permalink text
      threads_media_id text, threads_permalink text
      community_news_id text
      show_in_community boolean not null default true
      error text
      created_at timestamptz default now(), updated_at timestamptz default now()   -- trigger keeps updated_at

    marketing_events (id bigserial pk, piece_id uuid NULL → marketing_pieces on delete cascade,  -- NULL = run-level
                      at timestamptz default now(), kind text, message text)
      kinds: stage, run_start, run_end, media, scheduled, veto, post, post_error, metrics, note

    marketing_metrics (id bigserial pk, piece_id uuid → …, channel text  -- 'instagram'|'threads'|'community'
                       captured_at timestamptz default now(), views int, reach int, likes int,
                       comments int, saves int, shares int, raw jsonb)

    view marketing_public  -- anon-readable, for the community page
      select slug, title_ko, title_en, caption_ko, caption_en, slides, posted_at
      from marketing_pieces where stage = 'posted' and show_in_community

RLS on all three tables with NO policies (service role only). The view is granted to anon.

## 3. Writing state — `scripts/marketing/db.py`

The only door the team uses to the tables (Management API with the Supabase CLI keychain
token, same as `scripts/community.py`):

    db.py piece-upsert <slug> [--version V --build N --phase P --title-ko … --title-en … --one-message …]
    db.py stage <slug> <stage> [--note "…"]
    db.py set <slug> key=value …               # review_verdict, captions, slides (JSON), error …
    db.py event <slug|-> <kind> "<message>"    # '-' = run-level event, no piece
    db.py schedule <slug> [--hours 12]         # stage=scheduled, scheduled_at=now()+hours
    db.py list [--stage S] [--version V] [--json]
    db.py get <slug>                           # one piece as JSON
    db.py slides-merge <slug> '<json array>'   # merge slides by n, keeps alt_ko/alt_en
    db.py metrics-add <slug> <channel> views=… likes=… …

`schedule` refuses a piece without a reviewer PASS (`review_verdict` starting with `PASS`)
or without slides. `stage` refuses `scheduled`/`posting`/`posted` — those move only through
`schedule` and the scheduler. `--hours` defaults to `VETO_HOURS` from marketing.env (12).

## 4. Media — Cloudflare R2, served by the admin Worker

- Bucket `nawana-marketing`, bound to the admin Worker as `MEDIA`.
- Keys: `<slug>/<file>` (e.g. `2026-10-14-daily-call/02.mp4`).
- Public URL (what Instagram/Threads fetch, what the console and community page show):
  `https://nawana.app/admin/media/<slug>/<file>` — `web/vercel.json` already rewrites
  `/admin/:path*` to the Worker; the Worker serves `/admin/media/*` from `MEDIA` with NO
  session check (public marketing material), correct Content-Type, 1-hour cache (re-renders reuse keys), Range support
  for video.
- Upload: `scripts/marketing/media.sh [--set-slides] [--dry-run] <slug> <file>…` (wrangler
  `r2 object put --remote`, Node 22, the gateway's wrangler). For every `NN.png` it also makes
  and uploads `NN.jpg` (1080×1350, for Instagram, which publishes JPEG only) and `NN-web.jpg`
  (720×900, the community page). It prints the slides JSON; `--set-slides` merges it into
  the piece (`db.py slides-merge`) and logs a `media` event.

## 5. Posting — `scripts/marketing/scheduler.py` (launchd, every 15 min)

For each piece with stage `scheduled`, `scheduled_at <= now()`, `vetoed_at is null`:
stage `posting` → post to each CONFIGURED channel → stage `posted` (or `failed` + `error`).
- Instagram (Instagram API with Instagram Login, graph.instagram.com): one container per
  slide (`image_url`, or `media_type=VIDEO` + `video_url`, with `is_carousel_item=true`),
  poll each until `FINISHED`, then a `CAROUSEL` container with `children` + `caption`, then
  `media_publish`. Store id and permalink.
- Threads (graph.threads.net): same shape (`is_carousel_item`, `CAROUSEL`, `threads_publish`),
  max 10 items, `threads_text`.
- Community: nothing to deploy — the page reads `marketing_public`, so a posted piece
  appears at once.
- A channel without credentials is skipped and logged (`post_error: instagram not
  configured`); the piece still becomes `posted` when community is the only channel left.
- `scheduler.py --dry-run` prints what it would do.
- A piece is CLAIMED (`scheduled → posting` in one conditional UPDATE), so a veto that lands
  while the run is queued wins. A channel whose media id is already on the piece is not
  posted again (a retry after a partial failure). Any channel error → `failed` + `error`.
- Image items post `jpg` (falls back to `png`, then `jpg_web`); video items post `mp4`.
  One slide → a single post (a lone Instagram video is a REEL), 2–10 → a carousel.
- Instagram caption: `caption_ko` unless `IG_CAPTION_LANG=en`, the other as fallback.

Credentials: `~/.config/nawana/marketing.env` (never in the repo):
`IG_USER_ID`, `IG_ACCESS_TOKEN`, `THREADS_USER_ID`, `THREADS_ACCESS_TOKEN`, `VETO_HOURS` (12);
optional `IG_CAPTION_LANG` (ko), `IG_API_VERSION` (v22.0), `THREADS_API_VERSION` (v1.0).
Long-lived tokens last 60 days — the scheduler refreshes them weekly and logs the expiry
(a `note` event, no piece); it writes back `*_ACCESS_TOKEN`, `*_TOKEN_REFRESHED_AT` and
`*_TOKEN_EXPIRES_AT` (epoch seconds; prefix `IG` / `THREADS`).

launchd: `scripts/marketing/install-launchd.sh` installs `com.nawana.marketing-scheduler`
(900 s) and `com.nawana.marketing-metrics` (09:00); logs in `marketing/logs/`.

## 6. Metrics — `scripts/marketing/metrics.py` (launchd, daily 09:00)

For every `posted` piece younger than 60 days: Instagram media insights (`views`, `reach`,
`likes`, `comments`, `saved`, `shares`), Threads insights (`views`, `likes`, `replies`,
`reposts`, `quotes`), one `marketing_metrics` row per channel per day.
Threads maps `replies → comments`, `reposts + quotes → shares`; the raw answer is in `raw`.
A same-day re-run replaces that day's row (UTC day). One `metrics` event per run, no piece.

## 7. The console — admin Worker, tab 마케팅

- `GET /admin/marketing.json` (session): pieces (newest first) with recent events, slides
  with media URLs, latest metrics per channel, daily totals.
- `POST /admin/marketing/<id>/veto` {reason} → vetoed_at, stage `vetoed`, event.
- `POST /admin/marketing/<id>/post-now` → scheduled_at = now() (the scheduler picks it up).
- `POST /admin/marketing/<id>/reschedule` {hours}.
- Tab UI: a pipeline board by stage; each piece a card: title, version, stage, countdown to
  posting with 게시 막기 / 지금 올리기, slide previews (video inline), review verdict,
  captions, links to the live posts, per-piece and total charts of views, reach, likes, saves.

## 8. Never

- Never post outside the scheduler path; never post a piece without a reviewer PASS.
- Never deploy the website from automation (community reads the DB; media lives in R2).
- Never commit from automation.
