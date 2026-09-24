-- ---------------------------------------------------------------------------
-- 30 extra minutes for one account (2026-09-24, founder decision).
--
-- d48b0216-9438-482d-87c1-4947063c6ff1 bought a 3-day Plus trial on the
-- morning of 2026-09-24 and was walled by DAILY_CAP_REACHED that evening after
-- 1,493 s of trial talk: the trial pool is Light's month × 7/30 = 2,100 s, and
-- the 607 s of the free call earlier that day sat in `tts_char_pool` under the
-- same billing day, so they were counted against the trial.
--
-- The grant goes onto the balance: `consume_metered_seconds` spends a positive
-- balance BEFORE the plan's pool on any capped account (a trial is never
-- uncapped), so these seconds work today without touching the trial figure.
-- Idempotent by key; re-running grants nothing twice.
-- ---------------------------------------------------------------------------
select public.grant_credits(
  'd48b0216-9438-482d-87c1-4947063c6ff1'::uuid, 1800, 'grant'::public.ledger_kind,
  'trial_topup', 'migration',
  'trial_topup_30min:d48b0216-9438-482d-87c1-4947063c6ff1',
  jsonb_build_object('reason', 'trial pool consumed by same-day free call',
                     'migration', '20260924190000'));
