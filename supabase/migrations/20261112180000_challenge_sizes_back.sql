-- The payment page offers all three sizes after all (2026-11-12, founder, the
-- same day as 20261112150000: Light is where everyone starts, and the page
-- lets someone pick Plus or Max there like a paywall). The two packages go
-- back on the web's shelf; their Stripe Prices now carry every currency the
-- Light one does.
update subscription_plans
   set sold_on_web = true
 where id in ('plus_challenge', 'max_challenge');
