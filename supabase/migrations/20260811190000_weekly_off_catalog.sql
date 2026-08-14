-- Weekly SKUs leave the sellable catalog.
--
-- They were never priced: `docs/launch-billing.md` locked monthly + annual
-- only, and the credits-era rationale for weekly ("a quarter of a month's
-- credits") died with the minutes-native model — `daily_weekly` and
-- `daily_monthly` now buy the SAME 300 s/day, differing only in commitment
-- length. Pricing that needs re-deriving, so it isn't a launch SKU.
--
-- Turned OFF in the catalog rather than deleted: the rows are referenced by
-- nothing today, but keeping them means re-enabling weekly later is one flag
-- plus the App Store Connect products — no migration, no code change. The
-- paywall reads `subscription_plans` with `is_active = true` and its period
-- picker only offers periods that have a purchasable product
-- (`PaywallView.availablePeriods`), so this alone removes the weekly tab.

update public.subscription_plans
   set is_active = false
 where period = 'weekly';
