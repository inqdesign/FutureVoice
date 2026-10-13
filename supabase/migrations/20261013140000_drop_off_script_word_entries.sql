-- Dictionary entries whose examples / variants came back in the learner's
-- NATIVE language (the model translated the entry instead of writing it in
-- the target language) — "moral cover" showed Korean example sentences on an
-- English learner's card. 18 rows on 2026-10-13. `word-entry` now refuses to
-- cache such an entry and treats one as a miss, but builds already in the
-- store read the table directly, so the rows themselves have to go; the next
-- lookup regenerates them.
delete from word_entry w
where w.target_lang !~ '^(ko|ja|zh)'
  and (
    exists (select 1 from jsonb_array_elements(coalesce(w.data->'examples', '[]'::jsonb)) e
            where e->>'text' ~ '[가-힣ぁ-んァ-ン一-龥]')
    or exists (select 1 from jsonb_array_elements(coalesce(w.data->'phrases', '[]'::jsonb)) p
               where p->>'phrase' ~ '[가-힣ぁ-んァ-ン一-龥]')
  );
