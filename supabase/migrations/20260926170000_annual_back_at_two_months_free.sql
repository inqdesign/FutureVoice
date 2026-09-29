-- ---------------------------------------------------------------------------
-- Annual goes back on sale at "2 months free" (2026-09-26, founder's framing).
--
-- RUN THIS ONLY AFTER THE APP STORE CONNECT PRICES ARE CHANGED. Until they
-- are, the catalog row being active means the paywall sells the OLD 33–46%
-- discount, which is what `20260926160000` took off sale.
--
--   Light annual   $99.99   ₩150,000   €99.99     (= 10 × monthly)
--   Plus  annual  $199.99   ₩290,000  €229.99     (= 10 × monthly)
--
-- Why this shape: a year that costs ten months is a fact a buyer can check
-- in their head, and it is the same number in every storefront — which the
-- old table was not (33% in the US, 39% in Korea, 25% in the EU on Light;
-- 40/40/46% on Plus). The paywall badge now says "2 months free" whenever
-- the live prices divide that way (`PaywallView.annualSavingLabel`), so the
-- offer reads as it was designed instead of as an arithmetic result.
--
-- What it fixes and what it does not, at the pools set today (full-use cost
-- $5.70 and $21.60 a month):
--
--   Light annual   net $7.08/mo   +$1.38/mo   **+$17/yr**   (was −$0.4)
--   Plus  annual   net $14.17/mo  −$7.43/mo   **−$89/yr**   (was −$137)
--
-- Plus annual still loses at FULL USE, and no discount can fix that while
-- Plus monthly itself is −$4.61: even at no discount the year is −$55. It is
-- a bounded bet, and today's real Plus usage (108 talk minutes and 28 scenes
-- in the heaviest month) makes the same subscriber **+$91/yr**. Re-derive
-- Plus's price from real months, and the annual follows it automatically at
-- 10 ×.
--
-- Apple: raising an annual price is a price INCREASE, so pick "preserve the
-- current price for existing subscribers" — there is exactly one annual row
-- on the books (the German `plus_annual` converting 2026-09-27 at €149.99).
-- KRW and EUR are set BY HAND, as they always have been; USD is the base
-- storefront Apple generates the other 174 from.
-- ---------------------------------------------------------------------------

update public.subscription_plans
   set is_active = true
 where period = 'annual';
