-- Web billing: point every plan at a Stripe price that matches what the App Store sells today.
--
-- The 2026-09-03 Stripe prices predate the 2026-09-26 bounded plans and the 2026-10-07
-- "2 months free" annuals (Plus $19.99, Light annual $79.99, Plus annual $143.99), and Max
-- had none. New live prices were created 2026-10-11 on the shared Dear RoRo account
-- (tax-inclusive, usd + krw/eur currency_options, lookup_key = plan id, transferred), read
-- from App Store Connect's live USA/KOR/DEU prices:
--   light_annual  $99.99  ₩149,000  €99.99
--   plus_monthly  $24.99  ₩29,000   €22.99
--   plus_annual   $249.99 ₩290,000  €229.99
--   max_monthly   $49.99  ₩58,000   €44.99   (new product nawana_max)
-- light_monthly keeps price_1UB6esEwYewqhSDO3431IoXk ($9.99 ₩15,000 €9.99, already right).
-- The three replaced prices were archived; none had a subscription.
--
-- stripe-checkout reads the price from this column and stripe-webhook maps a subscription's
-- price back to its plan through it, so this is the whole switch.

update subscription_plans set stripe_price_id = 'price_1UPFuSEwYewqhSDO3zhXGRRo' where id = 'light_annual';
update subscription_plans set stripe_price_id = 'price_1UPFuTEwYewqhSDOy27XuLUr' where id = 'plus_monthly';
update subscription_plans set stripe_price_id = 'price_1UPFuTEwYewqhSDOpJnRlFww' where id = 'plus_annual';
update subscription_plans set stripe_price_id = 'price_1UPFuUEwYewqhSDOTmx0Y5Lp' where id = 'max_monthly';
