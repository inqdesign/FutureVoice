-- ---------------------------------------------------------------------------
-- 30 extra minutes for one account (2026-09-25, founder decision).
--
-- 2bda6067-5324-4ad2-ae9b-adbca2592800 started the 3-day Light trial on
-- 2026-09-25 and talked out the trial's 35-minute pool the same morning, then
-- met the spent-pool sheet and the paywall behind it three times. The trial
-- cap exists to stop a trial being worth more than the month it converts to,
-- but nothing said the number before the purchase (fixed the same day in the
-- paywall, the timeline and `DailyAllowanceSheet`).
--
-- The grant goes onto the balance: `consume_metered_seconds` spends a positive
-- balance BEFORE the plan's pool on any capped account, and a trial is never
-- uncapped, so these seconds work today without touching the trial figure.
-- Idempotent by key; re-running grants nobody twice.
-- ---------------------------------------------------------------------------
select public.grant_credits(
  '2bda6067-5324-4ad2-ae9b-adbca2592800'::uuid, 1800, 'grant'::public.ledger_kind,
  'trial_topup', 'migration',
  'trial_topup_30min:2bda6067-5324-4ad2-ae9b-adbca2592800',
  jsonb_build_object('reason', 'trial pool spent on day one, size never stated',
                     'migration', '20260925140000'));
