-- Google Play billing scaffold (Android launch, roadmap §1.11). ADDITIVE ONLY:
-- two columns, no behaviour change for iOS. NOT YET APPLIED to production —
-- push together with the owner's Play Console setup (products + RTDN topic +
-- service account); the google-webhook function reads these.
--
-- google_product_id mirrors apple_product_id: "what Google calls this plan",
-- never "what this plan is". Filled in once the four Play subscription
-- products exist (mirroring the ASC ones).

alter table public.subscription_plans
  add column if not exists google_product_id text unique;

-- The stable purchase identity on Google's side (the twin of
-- apple_original_tx_id). One row per user either way — a user subscribed on
-- both stores keeps ONE row; entitlement is the max of active purchases and
-- the client refuses a second purchase when an entitled row exists
-- (the two-store policy, decided before Play launch).
alter table public.user_subscriptions
  add column if not exists google_purchase_token text;
