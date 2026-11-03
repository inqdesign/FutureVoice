-- ---------------------------------------------------------------------------
-- Give back the seconds the report's narration took (2026-11-02).
--
-- `report-narration` was added to the tts function's FREE_PURPOSES in
-- 25c60191 (2026-10-27 evening), but the deployed tts is the 11:54 UTC build
-- from that morning, so every narrated line went down the PAID pooled path
-- and was charged to `user_credits.balance`. Three accounts paid for it:
--
--   d6cdf426  50 s  (not refunded, founder decision)
--   ecd78251 271 s
--   5f0ec0db 204 s
--
-- Deploy tts (`supabase functions deploy tts`) BEFORE applying this, or the
-- next report opened charges again. Idempotent by key.
-- ---------------------------------------------------------------------------
select public.grant_credits(
  u.id, u.secs, 'grant'::public.ledger_kind,
  'refund', 'migration',
  'refund_report_narration:' || u.id::text,
  jsonb_build_object('reason', 'report-narration charged before tts deploy',
                     'migration', '20261102210000'))
from (values
  ('ecd78251-49c4-4e18-a156-6fbe90fd6e3b'::uuid, 271),
  ('5f0ec0db-6ae7-4b65-9643-106c1cb516e9'::uuid, 204)
) as u(id, secs);
