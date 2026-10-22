-- One library for every learner of a language (2026-10-22, founder).
--
-- The app ships a graded word list per target language (~8,000 English
-- words) and nothing could add to it. A learner who typed a word the list
-- doesn't carry kept it in their own notebook only, with no level. Now a word
-- or expression a learner adds by hand, once `library-add` has read it (a
-- real word, spelled right, in the language being learned, not a name), is a
-- row here with a CEFR level, and every learner of that language gets it in
-- their library on the next launch.
--
-- Nothing in this table says WHO added a term beyond `created_by`, which only
-- the service role reads (rate limit). Clients read term, kind and level.

create table if not exists public.library_terms (
  id bigserial primary key,
  target_lang text not null,
  kind text not null check (kind in ('word', 'expression')),
  -- As the learner sees it (German nouns keep their capital).
  term text not null,
  -- Lower-cased, trimmed: the identity.
  key text not null,
  level text not null check (level in ('a1', 'a2', 'b1', 'b2', 'c1', 'c2')),
  -- How many times learners added it: a term many people reach for.
  adds integer not null default 1,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (target_lang, kind, key)
);

create index if not exists library_terms_lang_updated
  on public.library_terms (target_lang, updated_at);

alter table public.library_terms enable row level security;

drop policy if exists library_terms_read on public.library_terms;
create policy library_terms_read on public.library_terms
  for select to authenticated using (true);

-- What `library-add` refused, keyed by what was typed, so the same typo or
-- made-up word never costs a second model call. Service role only.
create table if not exists public.library_rejects (
  target_lang text not null,
  kind text not null check (kind in ('word', 'expression')),
  key text not null,
  verdict text not null,
  suggestion text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (target_lang, kind, key)
);

alter table public.library_rejects enable row level security;

-- Someone else added it too: count it, and move it up the "since" feed.
create or replace function public.library_term_bump(p_id bigint)
returns void
language sql
security definer
set search_path = public
as $$
  update public.library_terms
     set adds = adds + 1, updated_at = now()
   where id = p_id;
$$;

revoke all on function public.library_term_bump(bigint) from public, anon, authenticated;
