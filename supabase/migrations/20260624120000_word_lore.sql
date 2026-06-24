-- Shared word "lore" so the per-word AI calls (example sentence + native-language
-- meaning) are generated ONCE and reused by every user who taps that word.
-- Public read (any signed-in or anon client), insert by authenticated users.

create table if not exists public.word_lore (
  word            text not null,
  lang            text not null default 'en',   -- language of the example
  part_of_speech  text,
  example         text not null,
  created_at      timestamptz not null default now(),
  primary key (word, lang)
);

alter table public.word_lore enable row level security;

drop policy if exists "word_lore readable by everyone" on public.word_lore;
create policy "word_lore readable by everyone"
  on public.word_lore for select using (true);

drop policy if exists "word_lore insertable by authed" on public.word_lore;
create policy "word_lore insertable by authed"
  on public.word_lore for insert to authenticated with check (true);

-- Native-language meaning of a word, keyed by the reader's language.
create table if not exists public.word_meaning (
  word         text not null,
  native_lang  text not null,
  meaning      text not null,
  created_at   timestamptz not null default now(),
  primary key (word, native_lang)
);

alter table public.word_meaning enable row level security;

drop policy if exists "word_meaning readable by everyone" on public.word_meaning;
create policy "word_meaning readable by everyone"
  on public.word_meaning for select using (true);

drop policy if exists "word_meaning insertable by authed" on public.word_meaning;
create policy "word_meaning insertable by authed"
  on public.word_meaning for insert to authenticated with check (true);
