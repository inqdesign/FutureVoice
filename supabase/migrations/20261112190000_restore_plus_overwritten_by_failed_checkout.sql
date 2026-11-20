-- One account's PAID Plus was overwritten by its own earlier, failed checkout.
--
-- fd478861 opened the web checkout for Plus monthly on 2026-11-11 01:51 UTC;
-- the card was refused three times (sub_1UaQhV…, never paid). Two minutes
-- later they checked out again and paid ₩26,000 (sub_1UaQjX…, active until
-- 2026-12-11 01:53:55 UTC). Stripe expired the first, `incomplete`
-- subscription 23 hours later and stripe-webhook wrote it over the row:
-- expired, with the dead subscription's id on it.
--
-- This puts the row back on the subscription that was paid for, as Stripe
-- reports it. Guarded on the dead subscription's id, so it does nothing if the
-- row has moved since (a webhook for the live one, a second run).
update user_subscriptions
   set plan_id                = 'plus_monthly',
       source                 = 'stripe',
       status                 = 'active',
       stripe_customer_id     = 'cus_Vbe1CeNvGDyGNf',
       stripe_subscription_id = 'sub_1UaQjXEwYewqhSDOirfUJLB8',
       trial_ends_at          = null,
       current_period_start   = '2026-11-11 01:53:55+00',
       current_period_end     = '2026-12-11 01:53:55+00',
       cancel_at_period_end   = false,
       updated_at             = now()
 where user_id = 'fd478861-c68b-4379-8720-3752f09504d9'
   and stripe_subscription_id = 'sub_1UaQhVEwYewqhSDOxHdD9b6N'
   and status = 'expired';
