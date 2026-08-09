-- The English seed batch got applied twice while repairing migration
-- history (the 2026-07-31 dashboard-only versions), leaving every curated
-- en persona duplicated. Dedupe curated rows (owner null) by
-- (display_name, language), keeping one of each. Idempotent by nature —
-- and future seed migrations should stay insert-only with this guard
-- available as the cleanup pattern.

delete from public.public_personas a
using public.public_personas b
where a.owner_user_id is null
  and b.owner_user_id is null
  and a.display_name = b.display_name
  and a.language = b.language
  and a.ctid > b.ctid;
