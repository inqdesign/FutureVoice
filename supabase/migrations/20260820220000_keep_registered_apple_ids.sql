-- ---------------------------------------------------------------------------
-- The Apple product ids go back to the four already registered in App Store
-- Connect. Our own plan ids stay `light_*` / `plus_*`.
--
-- `20260820180000_monthly_pools_light_and_plus` moved both at once, on the
-- checklist's word that ASC had no products yet. It did: four subscriptions
-- were registered under `com.roro.futurevoice.{daily,unlimited}_{monthly,annual}`.
--
-- An Apple product id is permanent PER APP. It cannot be renamed, and it
-- cannot be reused by another product even after the original is removed from
-- sale — so those four strings are spent whatever we do. Registering four more
-- under the new names would buy nothing a user can see (nobody ever reads a
-- product id; they read the localized Display Name, which IS editable) and
-- would cost four more permanent ids, four more introductory offers to
-- configure, and four dead products sitting in the group forever.
--
-- Nothing has actually sold — every `user_subscriptions` row still has a null
-- `apple_original_tx_id` — but that changes nothing here: the ids are burned by
-- registration, not by a sale.
--
-- The two id spaces were already separate by design: `apple-webhook` resolves
-- `apple_product_id` → `subscription_plans.id`, and the app reads product ids
-- out of the catalog rather than hardcoding them. So the mismatch below is not
-- a smell — it is the column doing its job. Read `apple_product_id` as "what
-- Apple calls this", never as "what this plan is".
-- ---------------------------------------------------------------------------

update public.subscription_plans set apple_product_id = 'com.roro.futurevoice.daily_monthly'     where id = 'light_monthly';
update public.subscription_plans set apple_product_id = 'com.roro.futurevoice.daily_annual'      where id = 'light_annual';
update public.subscription_plans set apple_product_id = 'com.roro.futurevoice.unlimited_monthly' where id = 'plus_monthly';
update public.subscription_plans set apple_product_id = 'com.roro.futurevoice.unlimited_annual'  where id = 'plus_annual';

comment on column public.subscription_plans.apple_product_id is
  'The App Store Connect product id. Deliberately NOT equal to `id`: these '
  'four were registered under the pre-2026-08-20 tier names, and an Apple '
  'product id is permanent per app — it can never be renamed or reused. What '
  'the buyer sees is the localized Display Name in ASC, which is editable.';
