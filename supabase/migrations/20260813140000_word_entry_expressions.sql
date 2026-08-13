-- word_entry: an expression is not a word, and a target language is not a
-- decoration.
--
-- The table was born as a single-word EN→native dictionary cache, keyed by
-- (word, native_lang). Two things outgrew that key:
--
-- 1. Expressions. The card for a multi-word chunk routed through the same
--    lookup, and the generation prompt ("For the English WORD the user
--    sends", schema = pos/senses/phrases/properNoun) has no shape for a
--    phrase — so the model picked a head word and glossed THAT.
--    "hundred active users" came back as 100의; 100개[명]의 with the example
--    "There were a hundred people at the party."; "that covers everything"
--    came back as the pronoun "that". 82 of 464 rows were multi-word and
--    every one of them was wrong this way. They are deleted below, not
--    fixed: the entries are unsalvageable and the table is a GLOBAL shared
--    cache, so a poisoned row is served to every user forever.
--
-- 2. Target language. The key never recorded which language the entry
--    teaches, and the prompt hardcoded English. A Korean-target learner's
--    "막 시작했거든" came back as 느슨한/헐거운 — i.e. the word "slack", the
--    only English word in the system prompt (it appears there as an
--    example). Those rows are deleted too. Going forward the key carries
--    target_lang, so entries for different targets can never collide.
--
-- Legacy rows are stamped target_lang='en', kind='word', which is what they
-- actually are; a non-English-target lookup simply misses them and
-- generates fresh.

alter table public.word_entry
  add column if not exists target_lang text not null default 'en',
  add column if not exists kind        text not null default 'word';

comment on column public.word_entry.target_lang is
  'BCP-47 code of the language the entry TEACHES (the headword''s language).';
comment on column public.word_entry.kind is
  '"word" | "expression" — decides which generation prompt wrote this row.';

-- Purge what the single-word English prompt could only have got wrong.
-- Deletes are idempotent, so re-running this migration is a no-op.
delete from public.word_entry where word ~ '\s';                 -- multi-word
delete from public.word_entry where word !~ '^[[:ascii:]]+$';    -- non-English headword

alter table public.word_entry drop constraint if exists word_entry_pkey;
alter table public.word_entry
  add constraint word_entry_pkey primary key (word, native_lang, target_lang, kind);
