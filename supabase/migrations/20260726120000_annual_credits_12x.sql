-- Lock annual plan credits to exactly 12× monthly.
-- "2 months free" lives in the annual sticker price, not extra credits.
-- See docs/launch-billing.md §1.

update public.subscription_plans
   set credits_per_cycle = 6000
 where id = 'pro_annual';

update public.subscription_plans
   set credits_per_cycle = 18000
 where id = 'premium_annual';
