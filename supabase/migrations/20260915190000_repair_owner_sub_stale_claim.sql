-- ---------------------------------------------------------------------------
-- Put back a subscription row a stale apple-claim took down.
--
-- 2026-09-15 16:30 UTC DID_RENEW filed the owner's Plus period through
-- 09-16 16:31 (transaction 2000001236750884). At 19:00:27 the device claimed
-- the PREVIOUS period (2000001236157217, ended 09-15 16:31); apple-claim only
-- skipped an older period when its liveness matched the row's, so the dead one
-- wrote `expired` and wound current_period_end back a day. The function is
-- fixed in the same change; this restores the row to what the latest
-- transaction on file says.
--
-- Guarded: only touches the row while it still holds the stale period, so a
-- webhook that has since filed a newer one is left alone.
-- ---------------------------------------------------------------------------

update user_subscriptions s
   set status = 'active',
       current_period_start = t.purchase_date,
       current_period_end = t.expires_date,
       updated_at = now()
  from subscription_transactions t
 where s.user_id = '72bcaa7e-3dd2-4364-b197-078ba59c1ce4'
   and s.apple_original_tx_id = '2000001224850776'
   and s.status = 'expired'
   and s.current_period_end = '2026-09-15 16:31:31+00'
   and t.transaction_id = '2000001236750884'
   and t.expires_date > now();
