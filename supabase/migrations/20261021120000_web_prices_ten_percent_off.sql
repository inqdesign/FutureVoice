-- Web prices are the App Store's minus 10% (2026-10-21, founder decision).
--
-- Apple keeps 15% of the VAT-free price; Stripe from the German account costs ~5–6%
-- on a Korean or US card (fee + EUR conversion), so -10% on the web nets about what
-- the App Store does. New live Prices on the same products, made by
-- scripts/stripe-web-discount.sh (lookup_key moved onto them):
--   light_monthly  $8.99    ₩13,500   €8.99
--   light_annual   $89.99   ₩134,000  €89.99
--   plus_monthly   $22.49   ₩26,000   €20.69
--   plus_annual    $224.99  ₩261,000  €206.99
--   max_monthly    $44.99   ₩52,000   €40.49
-- The 2026-10-11 Prices stay active and unused (no web subscription existed), so
-- 20261011100000's ids are the way back.

update subscription_plans set stripe_price_id = 'price_1USzPgEwYewqhSDOVOiZOC4H' where id = 'light_monthly';
update subscription_plans set stripe_price_id = 'price_1USzPgEwYewqhSDOBDd3P8pi' where id = 'light_annual';
update subscription_plans set stripe_price_id = 'price_1USzPhEwYewqhSDO6gwUV3xx' where id = 'plus_monthly';
update subscription_plans set stripe_price_id = 'price_1USzPhEwYewqhSDOAzOa34Ay' where id = 'plus_annual';
update subscription_plans set stripe_price_id = 'price_1USzPiEwYewqhSDOiuUovj9U' where id = 'max_monthly';

