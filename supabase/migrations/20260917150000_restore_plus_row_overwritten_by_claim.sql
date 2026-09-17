-- One account, two live Apple subscriptions (2026-09-17). Verified against
-- the App Store Server API (Get All Subscription Statuses):
--
--   720002729737293  daily_annual      USA storefront, in-app (token set)
--                    free trial → 2026-09-19 16:33:26Z, autoRenewStatus 0
--                    (CANCELLED — ends there, Apple never sent us the
--                    DID_CHANGE_RENEWAL_STATUS)
--   270003123752849  unlimited_monthly KOR storefront, offer-code redeem link
--                    (no token), free trial → 2026-09-23 03:21:21Z, then
--                    renews on `Beta50 Plus Monthly v2` (PAY_AS_YOU_GO,
--                    ₩14,500 × 12 months) — the discount lives in the
--                    RENEWAL info, so no transaction carries offer_type 3
--                    until the first renewal.
--
-- The webhook filed the Plus row on 09-16; on 09-17 13:57Z a fresh sign-in
-- re-sent the device's Light entitlement and apple-claim overwrote it — its
-- guards only stop a DEAD transaction from taking a live row, not a live one
-- from a different original transaction. This puts the row back on the
-- subscription that is actually running past 09-19. Guarded on the stale
-- original tx id so a re-run, or a run after the webhook has already moved
-- the row on, is a no-op.

update public.user_subscriptions
set plan_id              = 'plus_monthly',
    source               = 'apple',
    apple_original_tx_id = '270003123752849',
    status               = 'trialing',
    current_period_start = '2026-09-16 03:21:21+00',
    current_period_end   = '2026-09-23 03:21:21+00',
    trial_ends_at        = '2026-09-23 03:21:21+00',
    cancel_at_period_end = false,
    updated_at           = now()
where user_id = '1f5c04ca-e7e9-4b82-a962-99988b341ed1'
  and apple_original_tx_id = '720002729737293';
