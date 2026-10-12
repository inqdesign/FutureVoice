-- No more voice parking (2026-10-12, founder decision).
--
-- Parking deleted a non-paying learner's ElevenLabs voice after 7 idle days
-- (20260928140000) because ElevenLabs Pro holds 160 voices for the whole
-- account. New clones are made on Cartesia since the same day, which stores
-- them without a limit, so there is nothing left to free. The job had already
-- been switched off; this removes it so it can't be switched back on.
--
-- The voices parked before this (parked_at set) stay as they are: their
-- ElevenLabs voice is gone, and the app's revival flow rebuilds them from the
-- phone's recording on the next use — on Cartesia now.

do $$
begin
  if exists (select 1 from cron.job where jobname = 'park_idle_voices') then
    perform cron.unschedule('park_idle_voices');
  end if;
end $$;
