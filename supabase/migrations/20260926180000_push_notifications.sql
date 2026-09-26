-- ---------------------------------------------------------------------------
-- Push notifications: the first thing this app can SAY to a learner who
-- isn't holding it (2026-09-26).
--
-- Until now every notification was LOCAL — the phone scheduling its own
-- reminders — which means the app could only ever tell someone what it
-- already knew when they last had it open. Three things it could not say at
-- all, and all three are why this exists:
--
--   * a seat in the Core opened and somebody took it (`CoreClubService`
--     polls `core_events` on foreground and posts a local line, so the news
--     waits for the next launch — see the Core section in CLAUDE.md),
--   * a trial ends tomorrow, or a charge failed (server facts; the learner
--     finds out by opening the app, which is exactly what they stopped doing),
--   * anything the founder needs to tell everyone at once.
--
-- Two tables and nothing else. The sending lives in the `push-send` edge
-- function, which is the only thing that holds the APNs key.
--
-- `device_tokens` is one row per INSTALL, not per learner: a phone and an
-- iPad are two rows, and the same phone reinstalled is a new token with the
-- old one left to be reaped by its first 410 from Apple. It carries three
-- things the sender cannot work out on its own:
--
--   * `bundle_id` — APNs routes by topic, and a dev build
--     (com.roro.futurevoice.dev) and the shipped app are different topics.
--   * `environment` — a build signed `aps-environment: development` only
--     exists on api.sandbox.push.apple.com, and a production build only on
--     api.push.apple.com. Sending to the wrong host is a hard failure, not a
--     fallback, so the app states which one it is rather than being guessed at.
--   * `app_language` — chrome follows the language the LEARNER picked, never
--     the device's (see "UI text has ONE language" in CLAUDE.md), and a push
--     is chrome. The server cannot read that choice, so the install reports
--     it and the sender picks its text by this column. A push written in a
--     language the learner didn't choose is the one rule this app has never
--     broken on any other surface.
--
-- `push_sends` is what makes every sender idempotent, because all three of
-- them run on a schedule and a schedule runs twice: a cron retried after a
-- timeout, a settlement re-run, a founder double-tapping send. The unique
-- key is (user, kind, dedupe_key) — the Core passes the event id, the trial
-- reminder passes the subscription's period end, a broadcast passes its own
-- id — so the second attempt writes nothing and sends nothing. It is a
-- LEDGER, not a queue: a row means "this was already said", and nothing
-- reads it to decide what to say next.
--
-- Deliberately NOT here: any notification the phone can schedule by itself.
-- The daily call stays AlarmKit (it has to ring through silent mode, which
-- no push can do), and review reminders stay local (the phone knows when a
-- card is due, and a push for it would be a round trip to say something
-- already on the device).
-- ---------------------------------------------------------------------------

create table if not exists public.device_tokens (
  token         text primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  bundle_id     text not null,
  environment   text not null check (environment in ('sandbox', 'production')),
  app_language  text,
  updated_at    timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;

-- An install may only ever write its OWN rows, and read nothing but them.
-- The sender runs as service role and bypasses this entirely.
drop policy if exists device_tokens_own on public.device_tokens;
create policy device_tokens_own on public.device_tokens
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.push_sends (
  id          bigserial primary key,
  user_id     uuid references auth.users(id) on delete cascade,
  kind        text not null,
  dedupe_key  text not null,
  sent_at     timestamptz not null default now(),
  unique (user_id, kind, dedupe_key)
);

alter table public.push_sends enable row level security;
-- No client policy at all: this says who was told what, which is nobody's
-- business but the sender's.
revoke all on public.push_sends from anon, authenticated;
