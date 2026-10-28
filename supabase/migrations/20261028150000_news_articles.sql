-- A news story as a short newspaper article to READ (the personal tutor's
-- reading pick, 2026-10-28, founder). The tutor shows only the story's
-- title, taken from the news pool the Talk tab already reads (news_topics);
-- the article is written the first time anyone opens it and kept here for
-- everyone after, per (story, language, band), so it is never written twice.
--
-- Platform content like news_topics: no learner is charged, and nothing
-- about the learner travels, only the story and their CEFR band.

create table public.news_articles (
  id          bigserial primary key,
  story_key   text not null,                 -- sha256 of language | normalized title
  language    text not null,                 -- target language, e.g. 'en'
  band        text not null check (band in ('a', 'b', 'c')),  -- CEFR A / B / C
  category    text not null default '',
  title       text not null,                 -- the article's headline
  summary     text not null default '',      -- one-line standfirst
  body        text not null,                 -- paragraphs separated by a blank line
  model       text not null,
  created_at  timestamptz not null default now(),
  unique (story_key, language, band)
);

alter table public.news_articles enable row level security;
-- No client policies: only the service-role edge function reads and writes.
