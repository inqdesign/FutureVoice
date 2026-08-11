-- One learner, one row per language — enforced here rather than trusted to
-- the client.
--
-- The app was inserting a fresh copy of the user on every launch. Its
-- "does my row already exist?" query compared `owner_user_id` against Swift's
-- `UUID.uuidString`, which is UPPERCASE, while Postgres renders uuid columns
-- lowercase — so the lookup never matched, the update path was never taken,
-- and the insert path ran again and again. The client is fixed, but a
-- constraint is what makes it impossible rather than merely unlikely.

-- Collapse existing duplicates, keeping the most recently updated row so the
-- learner's latest introduction is the one that survives.
delete from public.public_personas a
using public.public_personas b
where a.owner_user_id is not null
  and a.owner_user_id = b.owner_user_id
  and a.language = b.language
  and (a.updated_at, a.ctid) < (b.updated_at, b.ctid);

create unique index if not exists public_personas_one_per_owner_language
  on public.public_personas(owner_user_id, language)
  where owner_user_id is not null;
