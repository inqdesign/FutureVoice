-- Stripe web billing alongside Apple StoreKit.
--
-- The marketing site sells the SAME plans via Stripe Checkout. Entitlements
-- keep a single source of truth: user_subscriptions + user_credits, written
-- only by webhooks (Apple's when it ships, Stripe's stripe-webhook function).
-- The app never needs to know which store billed the user.
--
-- One row per user still holds: `source` records which store currently owns
-- the subscription. Buying on the web while an Apple sub is active is a user
-- error we surface in UI copy, not in schema.

alter table public.subscription_plans
  add column if not exists stripe_price_id text unique;   -- Stripe Price ID ('price_...'), filled from the Stripe dashboard

alter table public.user_subscriptions
  add column if not exists source text not null default 'apple'
    constraint user_subscriptions_source_check check (source in ('apple', 'stripe')),
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text;

create index if not exists user_subscriptions_stripe_customer_idx
  on public.user_subscriptions(stripe_customer_id);
