-- Shared topic pools for a learner's FIELD: their subject at university, their
-- job, the role they're applying for (Talk's Studies / Work / Interview chips).
--
-- Like news_topics, a pool is written once and read by everyone: the first
-- learner who studies robotics engineering pays the Gemini call, every later
-- one reads the same topics. What a learner typed ("로봇 엔지니어링",
-- "Robotik", "robotics eng.") is mapped to ONE canonical field first
-- (field_aliases), so spellings and languages land on the same pool.
--
-- Only the field travels: never the school, the learner's role in their job,
-- or anything else from their profile. A pool is generic to the field by
-- construction, which is what makes it shareable.

create table public.field_aliases (
  raw         text primary key,              -- lowercased, trimmed input
  kind        text not null,                 -- study | work | interview
  slug        text not null,                 -- e.g. 'robotics-engineering'
  name        text not null,                 -- e.g. 'Robotics engineering'
  created_at  timestamptz not null default now()
);

create table public.field_topics (
  id          bigserial primary key,
  kind        text not null check (kind in ('study', 'work', 'interview')),
  slug        text not null,
  name        text not null,
  language    text not null,                 -- target language, e.g. 'en'
  band        text not null check (band in ('a', 'b', 'c')),  -- CEFR A / B / C
  topics      jsonb not null default '[]',   -- [{ "title": "...", "blurb": "..." }]
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (kind, slug, language, band)
);

alter table public.field_aliases enable row level security;
alter table public.field_topics enable row level security;
-- No client policies: only the service-role edge function reads and writes.
