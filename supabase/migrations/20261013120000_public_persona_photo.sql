-- A published profile carries its face (2026-10-13, founder: "publishing the
-- profile already means it is public"). Until now the photo never left the
-- phone, so every learner in the pool was an initial on every other phone.
--
-- A ~96 px JPEG as base64 in the row — never Supabase Storage, the same shape
-- speech_challenge_profiles uses. Nullable: no photo, or a build that doesn't
-- send one, is an initial as before. Covered by the existing owner
-- insert/update policies and the anonymous read of active rows.
alter table public.public_personas
  add column if not exists photo text;

alter table public.public_personas
  drop constraint if exists public_personas_photo_size;
alter table public.public_personas
  add constraint public_personas_photo_size
  check (photo is null or char_length(photo) <= 60000);
