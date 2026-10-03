-- Twenty minutes by hand for one early learner (07ad19f0), as offered in the
-- founder's letter of 2026-10-01 (`scripts/early-learners-letter-mail.py`).
-- APPLY ONLY AFTER THEY HAVE ANSWERED. Idempotent: the ledger key makes a
-- second run a no-op.
select public.grant_credits(
  '07ad19f0-6383-4242-b03a-4bfe993409c3'::uuid, 1200, 'grant'::public.ledger_kind,
  'free_talk_topup', 'migration',
  'letter_twenty_minutes:07ad19f0-6383-4242-b03a-4bfe993409c3',
  jsonb_build_object('reason', 'founder letter 2026-10-01: twenty more minutes',
                     'migration', '20261001170000'));
