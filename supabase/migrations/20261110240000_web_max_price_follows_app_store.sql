-- The web's Max price follows the App Store's again (2026-11-10).
--
-- Max went to $34.99 / ₩45,000 / €39.99 in App Store Connect on 2026-11-03
-- (20261103170000, 600 min), and the web Price stayed at the old one minus 10%
-- ($44.99 / ₩52,000 / €40.49): dearer on the web than in the store, under a line
-- that said "10% off on the web". New live Price on nawana_max, the App Store's
-- minus 10% like the other four (20261021120000):
--   max_monthly    $31.49   ₩40,500   €35.99
-- The old Price (price_1USzPiEwYewqhSDOiuUovj9U) stays active and unused: no web
-- subscription has ever existed.

update subscription_plans set stripe_price_id = 'price_1UaLsuEwYewqhSDOXAWk6niM' where id = 'max_monthly';
