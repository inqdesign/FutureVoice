-- ElevenLabs cost per character, MEASURED instead of assumed.
--
-- `set_elevenlabs_usd_per_credit` priced turbo/flash at 0.5 credit per
-- character and multilingual_v2 at 1.0, and the seed was the Creator tier
-- ($0.00022/credit) — so every ledger-priced turbo character cost $0.00011.
-- Neither half was ever checked against an invoice. Measured 2026-10-11 in
-- ElevenLabs' own analytics (Developers → Analytics, model filter = Eleven
-- Turbo v2.5, credits ÷ characters):
--
--   2026-09-20   8.21K credits / 27.1K chars = 0.30 credit/char
--   2026-10-11   6.58K credits / 27.1K chars = 0.24 credit/char  ($1.08 = $40 / 1M)
--
-- The −20% lines up with the Eleven v4 launch (standard rates cut 20%). The
-- account has been on Pro since launch ($99 / 600k = $0.000165/credit).
-- multilingual_v2 and v3 are listed at exactly twice turbo per character on
-- the API price table, so they take 2× the measured turbo ratio.
--
-- Effect: ledger-priced TTS was overstated ~2.2× (Sept) to ~2.8× (Oct).
-- Credit counts read straight from the ElevenLabs API were always right.
-- The cut-over date is approximate (v4 launch, ~2 weeks before 2026-10-13);
-- verify in Analytics if a day around it matters.

-- History: Pro tier, Sept ratios. Overwrites the Creator seed rows.
insert into public.provider_rates (provider, model, unit, usd_per_unit, effective_from, note)
values
  ('elevenlabs', 'eleven_turbo_v2_5',      'char', 0.000165 * 0.30, timestamptz '2026-01-01', 'Pro $0.000165/cr × 0.30 cr/char — measured 2026-09-20'),
  ('elevenlabs', 'eleven_flash_v2_5',      'char', 0.000165 * 0.30, timestamptz '2026-01-01', 'Pro $0.000165/cr × 0.30 cr/char — = turbo'),
  ('elevenlabs', 'eleven_multilingual_v2', 'char', 0.000165 * 0.60, timestamptz '2026-01-01', 'Pro $0.000165/cr × 0.60 cr/char — 2× turbo per API price table')
on conflict (provider, model, unit, effective_from) do update
  set usd_per_unit = excluded.usd_per_unit, note = excluded.note;

-- From the v4 launch: −20%.
insert into public.provider_rates (provider, model, unit, usd_per_unit, effective_from, note)
values
  ('elevenlabs', 'eleven_turbo_v2_5',      'char', 0.000165 * 0.24, timestamptz '2026-09-29', 'Pro × 0.24 cr/char — measured 2026-10-11 ($40/1M)'),
  ('elevenlabs', 'eleven_flash_v2_5',      'char', 0.000165 * 0.24, timestamptz '2026-09-29', 'Pro × 0.24 cr/char — = turbo'),
  ('elevenlabs', 'eleven_multilingual_v2', 'char', 0.000165 * 0.48, timestamptz '2026-09-29', 'Pro × 0.48 cr/char — 2× turbo')
on conflict (provider, model, unit, effective_from) do update
  set usd_per_unit = excluded.usd_per_unit, note = excluded.note;

-- Future tier changes go through the function, so it carries the measured
-- ratios too. Same signature — this replaces, it does not overload.
create or replace function public.set_elevenlabs_usd_per_credit(
  p_usd_per_credit numeric,
  p_effective_from timestamptz default now(),
  p_note text default null
) returns void
language sql
as $$
  insert into public.provider_rates (provider, model, unit, usd_per_unit, effective_from, note)
  values
    ('elevenlabs', 'eleven_multilingual_v2', 'char', p_usd_per_credit * 0.48, p_effective_from, p_note),
    ('elevenlabs', 'eleven_turbo_v2_5',      'char', p_usd_per_credit * 0.24, p_effective_from, p_note),
    ('elevenlabs', 'eleven_flash_v2_5',      'char', p_usd_per_credit * 0.24, p_effective_from, p_note)
  on conflict (provider, model, unit, effective_from) do update
    set usd_per_unit = excluded.usd_per_unit, note = excluded.note;
$$;
