-- The update sheet shows release notes in SECTIONS (New / Fixed / Improved)
-- from builds after 2026-10-18. `notes_ko` / `notes_en` keep the flat list
-- with the headings stripped, because builds already on phones draw them
-- with a parser that glues a heading line onto the bullet above it. The
-- headed copy (the store file as written) goes here, and only new builds
-- read it, in a query of its own.
alter table public.app_release
  add column if not exists notes_sections_ko text,
  add column if not exists notes_sections_en text;
