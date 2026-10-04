-- Max goes on sale with 1.1.4 (71): the build that draws the Max card is
-- submitted with `com.roro.futurevoice.max_monthly` attached, which is the
-- moment `20261002100000_max_tier` said to switch the row on. Builds already
-- in the store hard-code two cards and never show it.
update public.subscription_plans set is_active = true where id = 'max_monthly';
