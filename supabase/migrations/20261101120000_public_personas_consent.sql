-- Find people shows a learner's row only once they have AGREED to it.
--
-- Until 2026-09-15 the app mirrored every learner's onboarding profile into
-- the pool without asking; the consent sheet (PublicIntroPreviewSheet) came
-- after, and its yes lived only in the phone's defaults, so the server could
-- never tell an agreed row from one an old build put up. Those old rows were
-- still on every stranger's map (founder, 2026-11-01: hide them).
--
-- `consented_at` is that yes, on the row. A build from today stamps it on
-- every publish and, at launch, on the row of a learner who already said yes
-- (the preview's Publish, or publishing by hand). Every row on file starts
-- NULL — nothing records who agreed — so all learner rows leave the pool now
-- and each comes back the next time its owner opens a current build. A row
-- an old build inserts later is NULL too, and stays out.
--
-- Curated rows (owner_user_id null) are ours and need no consent. The owner
-- always reads their own row: the app's fetchMine and the trim of an
-- unconsented row both depend on it.

alter table public.public_personas
  add column if not exists consented_at timestamptz;

comment on column public.public_personas.consented_at is
  'When the owner agreed to be in Find people. NULL = never agreed (an old build published it); such a row is visible to its owner only.';

drop policy if exists "public_personas: read active" on public.public_personas;
create policy "public_personas: read active" on public.public_personas
  for select using (
    is_active
    and (
      owner_user_id is null
      or consented_at is not null
      or owner_user_id = auth.uid()
    )
  );
