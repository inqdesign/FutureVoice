-- Twenty more minutes by hand for one learner (8b6bb9c6), founder's call on
-- 2026-10-03. Signed up 2026-10-02 and spent the whole 1200 s free pool.
-- Idempotent: the ledger key makes a second run a no-op.
select public.grant_credits(
  '8b6bb9c6-8be6-417f-a052-4e3d2c6e4ef5'::uuid, 1200, 'grant'::public.ledger_kind,
  'free_talk_topup', 'migration',
  'founder_twenty_minutes:8b6bb9c6-8be6-417f-a052-4e3d2c6e4ef5',
  jsonb_build_object('reason', 'founder grant 2026-10-03: twenty more minutes',
                     'migration', '20261003120000'));
