-- Gemini rate card: the seed was a stand-in and under-costed us ~2.5x.
--
-- `20260823120000` seeded gen-3 prices from the 2.5-flash card ("VERIFY").
-- Verified against ai.google.dev/gemini-api/docs/pricing on 2026-08-27:
--
--   gemini-3.6-flash      $0.75 in / $3.75 out / $0.075 cached  (intro, to 2026-12-31)
--                         $1.50 in / $7.50 out / $0.15  cached  (from 2027-01-01)
--                         no separate audio rate is listed — audio bills at input.
--   gemini-3.1-flash-lite $0.25 in / $0.50 audio in / $1.50 out / $0.025 cached
--                         (no change scheduled for 2027)
--
-- The seed rows are UPDATED in place rather than superseded: they were never
-- a price that was true on any day, so keeping them would leave every ledger
-- row before today costed at a number Google never charged. The 2027 rise is
-- a genuine future change and gets its own effective_from, which is exactly
-- what the versioning exists for. 2.5-flash rows are untouched (list price).

update public.provider_rates set usd_per_unit = v.usd / 1000000, note = v.note
  from (values
    ('gemini-3.6-flash',      'input_token',        0.75,  'verified 2026-08-27 — intro price to 2026-12-31'),
    ('gemini-3.6-flash',      'output_token',       3.75,  'verified 2026-08-27 — intro price to 2026-12-31'),
    ('gemini-3.6-flash',      'thought_token',      3.75,  'thinking billed as output — verified 2026-08-27'),
    ('gemini-3.6-flash',      'audio_input_token',  0.75,  'no separate audio rate listed; = input — verified 2026-08-27'),
    ('gemini-3.6-flash',      'cached_input_token', 0.075, 'verified 2026-08-27 — intro price to 2026-12-31'),
    ('gemini-3.1-flash-lite', 'input_token',        0.25,  'verified 2026-08-27'),
    ('gemini-3.1-flash-lite', 'output_token',       1.50,  'verified 2026-08-27'),
    ('gemini-3.1-flash-lite', 'thought_token',      1.50,  'thinking billed as output — verified 2026-08-27'),
    ('gemini-3.1-flash-lite', 'audio_input_token',  0.50,  'verified 2026-08-27'),
    ('gemini-3.1-flash-lite', 'cached_input_token', 0.025, 'verified 2026-08-27 (audio cached is 0.05)')
  ) as v(model, unit, usd, note)
 where provider_rates.provider = 'gemini'
   and provider_rates.model = v.model
   and provider_rates.unit = v.unit
   and provider_rates.effective_from = timestamptz '2026-01-01';

insert into public.provider_rates (provider, model, unit, usd_per_unit, effective_from, note) values
  ('gemini','gemini-3.6-flash','input_token',        1.50/1000000, timestamptz '2027-01-01','intro pricing ends — verified 2026-08-27'),
  ('gemini','gemini-3.6-flash','output_token',       7.50/1000000, timestamptz '2027-01-01','intro pricing ends — verified 2026-08-27'),
  ('gemini','gemini-3.6-flash','thought_token',      7.50/1000000, timestamptz '2027-01-01','thinking billed as output'),
  ('gemini','gemini-3.6-flash','audio_input_token',  1.50/1000000, timestamptz '2027-01-01','no separate audio rate listed; = input'),
  ('gemini','gemini-3.6-flash','cached_input_token', 0.15/1000000, timestamptz '2027-01-01','intro pricing ends — verified 2026-08-27')
on conflict (provider, model, unit, effective_from) do update
  set usd_per_unit = excluded.usd_per_unit, note = excluded.note;
