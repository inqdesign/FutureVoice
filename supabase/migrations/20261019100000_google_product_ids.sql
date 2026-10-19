-- The five Play subscriptions exist (created 2026-10-19), so the catalog names
-- them. google_product_id is "what Google calls this plan" — the plan id
-- itself, since nothing on Google's side was registered under an older name
-- (the Apple ids are `daily_*` / `unlimited_*` for that reason, not this).
-- Each product carries ONE base plan (`monthly` or `annual`); BillingService
-- matches on the product id alone, and a product with no active base plan
-- returns no offer, so a row filled here before its plan is activated draws
-- nothing rather than a broken card.

update public.subscription_plans set google_product_id = 'light_monthly' where id = 'light_monthly';
update public.subscription_plans set google_product_id = 'light_annual'  where id = 'light_annual';
update public.subscription_plans set google_product_id = 'plus_monthly'  where id = 'plus_monthly';
update public.subscription_plans set google_product_id = 'plus_annual'   where id = 'plus_annual';
update public.subscription_plans set google_product_id = 'max_monthly'   where id = 'max_monthly';
