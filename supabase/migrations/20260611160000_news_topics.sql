-- Platform-wide news topic pool.
--
-- One row per (category, language, day). The news-topics Edge Function
-- generates a category's batch AT MOST ONCE per day (first requester
-- triggers it); every other user just reads. Users are never charged —
-- this is platform content, and per-user grounded Gemini calls would be
-- pure waste when interests come from a shared preset list.

create table public.news_topics (
  id            bigserial primary key,
  category      text not null,                 -- normalized interest, e.g. 'ai / tech'
  language      text not null,                 -- learner target language, e.g. 'en'
  fetched_date  date not null,
  topics        jsonb not null,                -- [{ "title": "...", "blurb": "..." }]
  created_at    timestamptz not null default now(),
  unique (category, language, fetched_date)
);

create index news_topics_lookup_idx
  on public.news_topics (language, fetched_date, category);

alter table public.news_topics enable row level security;

create policy "news_topics: authenticated read" on public.news_topics
  for select to authenticated using (true);

-- No insert/update/delete policies: only the service-role Edge Function
-- writes. Old rows are harmless (a few KB/day); prune later if ever needed.
