-- Max annual, sold on the web only (2026-11-10, founder: try it on the web first).
--
-- There is no App Store or Play product for it: an App Store product id is
-- permanent, so the web goes first. Both apps list the catalog with
-- is_active = true and ask the store for every row's product (iOS decodes
-- apple_product_id as non-optional), so this row stays is_active = false and no
-- shipped paywall ever sees it. `sold_on_web` is what stripe-checkout reads for a
-- row that is off the stores' shelf but on the web's. Every meter joins a held
-- plan by id with no is_active filter, so the subscription works like any other.
--
-- Same pool as Max monthly (600 min a month, refilled monthly inside the year by
-- billing_period_started_at's monthly anchor). Price is "2 months free" on the
-- App Store-equivalent monthly, minus the web's 10%:
--   max_annual   $314.99   ₩405,000   €359.99   (price_1UaMEDEwYewqhSDOwYLaNZ7E)
-- apple_product_id is NOT NULL and unique; the value is the id the product would
-- take if it is ever made in App Store Connect. Nothing asks the store for it
-- while the row is inactive.

alter table subscription_plans
  add column if not exists sold_on_web boolean not null default false;

comment on column subscription_plans.sold_on_web is
  'Web checkout may sell this plan even when is_active is false (no store product). Read by stripe-checkout only.';

insert into subscription_plans
  (id, tier, period, credits_per_cycle, apple_product_id, is_active, stripe_price_id,
   daily_seconds, daily_scenes, monthly_seconds, monthly_scenes, talk_unlimited,
   abuse_seconds, google_product_id, scene_talk_seconds, sold_on_web)
select 'max_annual', tier, 'annual', credits_per_cycle * 12, 'com.roro.futurevoice.max_annual', false,
       'price_1UaMEDEwYewqhSDOwYLaNZ7E',
       daily_seconds, daily_scenes, monthly_seconds, monthly_scenes, talk_unlimited,
       abuse_seconds, null, scene_talk_seconds, true
  from subscription_plans
 where id = 'max_monthly'
on conflict (id) do nothing;
