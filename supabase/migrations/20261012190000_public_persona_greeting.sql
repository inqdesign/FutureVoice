-- What a persona says when a learner comes across them on the Watch map
-- (2026-10-12): written at publish, by the author or for them from the intro
-- (GreetingEngine). Empty on rows published before; the app writes one for
-- those the first time the map needs it and keeps it on the device.
-- The app selects this column, so it must exist before a build that reads it.
alter table public.public_personas add column if not exists greeting text not null default '';
