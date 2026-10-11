-- Marketing automation (marketing/AUTOMATION.md §2).
--
-- A build upload starts the marketing team, the App Store release finishes it,
-- and a reviewed piece is posted by scripts/marketing/scheduler.py after a veto
-- window. These three tables are that pipeline's state. They are written only
-- with the service role (scripts/marketing/db.py through the Management API, the
-- admin Worker), so RLS is on with NO policies. The community page reads one
-- thing: the `marketing_public` view, which exposes only posted pieces marked
-- show_in_community, and only the columns listed there.

-- ── pieces ────────────────────────────────────────────────────────────────
create table if not exists public.marketing_pieces (
  id                 uuid primary key default gen_random_uuid(),
  slug               text unique not null,          -- = marketing/content/<slug>/
  version            text,
  build              int,
  phase              text check (phase in ('upload', 'release', 'manual')),
  stage              text not null default 'idea' check (stage in (
                       'idea', 'brief', 'copy', 'design', 'review', 'ready',
                       'scheduled', 'vetoed', 'posting', 'posted', 'failed')),
  title_ko           text,
  title_en           text,
  one_message        text,
  review_verdict     text,
  review_fixes       int,
  caption_ko         text,
  caption_en         text,
  threads_text       text,
  slides             jsonb not null default '[]'::jsonb,
  scheduled_at       timestamptz,
  vetoed_at          timestamptz,
  veto_reason        text,
  posted_at          timestamptz,
  ig_media_id        text,
  ig_permalink       text,
  threads_media_id   text,
  threads_permalink  text,
  community_news_id  text,
  show_in_community  boolean not null default true,
  error              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint marketing_pieces_slides_is_array check (jsonb_typeof(slides) = 'array')
);

create index if not exists marketing_pieces_due
  on public.marketing_pieces (scheduled_at) where stage = 'scheduled';
create index if not exists marketing_pieces_by_version
  on public.marketing_pieces (version, stage);

drop trigger if exists marketing_pieces_updated_at on public.marketing_pieces;
create trigger marketing_pieces_updated_at
  before update on public.marketing_pieces
  for each row execute function public.set_updated_at();

-- ── events ────────────────────────────────────────────────────────────────
-- piece_id is NULL for run-level events (run_start / run_end of a kickoff run),
-- which carry "<phase> <version> (<build>)" in the message.
create table if not exists public.marketing_events (
  id        bigserial primary key,
  piece_id  uuid references public.marketing_pieces(id) on delete cascade,
  at        timestamptz not null default now(),
  kind      text not null check (kind in (
              'stage', 'run_start', 'run_end', 'media', 'scheduled', 'veto',
              'post', 'post_error', 'metrics', 'note')),
  message   text
);

create index if not exists marketing_events_by_piece
  on public.marketing_events (piece_id, at desc);
create index if not exists marketing_events_recent
  on public.marketing_events (at desc);

-- ── metrics ───────────────────────────────────────────────────────────────
create table if not exists public.marketing_metrics (
  id           bigserial primary key,
  piece_id     uuid not null references public.marketing_pieces(id) on delete cascade,
  channel      text not null check (channel in ('instagram', 'threads', 'community')),
  captured_at  timestamptz not null default now(),
  views        int,
  reach        int,
  likes        int,
  comments     int,
  saves        int,
  shares       int,
  raw          jsonb
);

create index if not exists marketing_metrics_by_piece
  on public.marketing_metrics (piece_id, channel, captured_at desc);

-- ── access: service role only ─────────────────────────────────────────────
alter table public.marketing_pieces  enable row level security;
alter table public.marketing_events  enable row level security;
alter table public.marketing_metrics enable row level security;
-- no policies on purpose

revoke all on public.marketing_pieces, public.marketing_events, public.marketing_metrics
  from anon, authenticated;
revoke all on sequence public.marketing_events_id_seq, public.marketing_metrics_id_seq
  from anon, authenticated;

-- ── the community page's one window ───────────────────────────────────────
-- A plain (owner-rights) view: it reads past RLS by design, and is therefore
-- the whole of what anon can see — only these columns, only posted pieces the
-- founder left on the community page. Never add a column here without asking
-- whether a stranger may read it.
create or replace view public.marketing_public
  with (security_invoker = false, security_barrier = true) as
  select slug, title_ko, title_en, caption_ko, caption_en, slides, posted_at
    from public.marketing_pieces
   where stage = 'posted' and show_in_community;

revoke all on public.marketing_public from anon, authenticated;
grant select on public.marketing_public to anon, authenticated;
