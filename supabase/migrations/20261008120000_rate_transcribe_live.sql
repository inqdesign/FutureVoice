-- The live call's transcriber had no price on the rate card (2026-10-08).
--
-- Until today nothing wrote its usage anywhere — the gateway talks to Google
-- directly — so the gap was invisible. The gateway now writes one row per call
-- (`purpose = call-transcribe`, audio_input_tokens at 25 a second + an
-- estimate of the text out), and without these rows every one of them would
-- land in `unpriced_usage` instead of the cost views.
-- Prices: ai.google.dev/gemini-api/docs/pricing, read 2026-10-08 —
-- Gemini 3.5 Transcribe Live, audio in $3.50 / 1M, text out $21.00 / 1M.
insert into public.provider_rates (provider, model, unit, usd_per_unit, effective_from, note) values
  ('gemini', 'gemini-3.5-transcribe-live', 'audio_input_token', 3.50/1000000, timestamptz '2026-01-01', 'verified 2026-10-08 ($0.005/min)'),
  ('gemini', 'gemini-3.5-transcribe-live', 'output_token',     21.00/1000000, timestamptz '2026-01-01', 'verified 2026-10-08 (estimated count, chars/4)')
on conflict do nothing;
