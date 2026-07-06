-- Word dictionary entries are a SHARED, global cache (word + native_lang key,
-- readable by everyone). Generation cost is paid once per unique word across
-- the whole user base, then every future lookup is a free read. So the
-- per-lookup credit gate never made sense here — it only blocked learners with
-- an empty balance from seeing a word's meaning, the app's core function.
--
-- Generation now runs in the dedicated `word-entry` Edge Function (fixed,
-- server-side prompt — a client can't repurpose it for free arbitrary Gemini)
-- with NO credit charge. The only abuse left is spamming brand-new (garbage)
-- words to run up generation cost + pollute the cache; `created_by` lets that
-- function rate-limit new generations per user per hour. Cache hits stay
-- unlimited and free.

alter table public.word_entry
  add column if not exists created_by uuid references auth.users(id) on delete set null;

-- Rate-limit lookups: "how many new words has this user generated in the last
-- hour" scans by (created_by, created_at).
create index if not exists word_entry_created_by_at_idx
  on public.word_entry (created_by, created_at);
