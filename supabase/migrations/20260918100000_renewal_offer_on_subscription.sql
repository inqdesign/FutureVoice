-- What the NEXT charge will be — the half of Apple's answer we were throwing
-- away (2026-09-18).
--
-- An offer code does not price the period it is redeemed in. Apple gives a
-- new subscriber the intro trial first and applies the code from the first
-- renewal, so for the whole trial week every transaction says
-- `offer_type = 1 / FREE_TRIAL` and NOTHING on file says a code was ever
-- redeemed. The app reads the latest transaction, so "half price with your
-- launch code" stayed hidden and the learner saw the regular price beside a
-- plan they had just discounted — the first redeemer wrote in the day after
-- (docs/launch-billing.md §7), and every recipient of a launch code hits the
-- same week.
--
-- The answer was already arriving: `signedRenewalInfo` rides on every Apple
-- notification and carries the offer that will price the next period, its
-- price, and the product that renews. It was decoded for `autoRenewStatus`
-- and dropped. These columns keep it.
--
-- It belongs on the SUBSCRIPTION, not on `subscription_transactions`: it
-- describes a period that has not happened and has no transaction id, and it
-- is replaced — never accumulated — by the next notification.

alter table public.user_subscriptions
  add column if not exists renewal_offer_type       int,
  add column if not exists renewal_offer_id         text,
  add column if not exists renewal_price_milliunits int,
  add column if not exists renewal_currency         text,
  add column if not exists renewal_product_id       text;

comment on column public.user_subscriptions.renewal_offer_type is
  'Apple offerType pricing the NEXT period: 1 intro, 2 promotional, 3 offer code. Null = regular price.';
comment on column public.user_subscriptions.renewal_offer_id is
  'Apple offerIdentifier, e.g. "Beta50 Plus Monthly v2". Which code, for support and for counting redemptions.';
comment on column public.user_subscriptions.renewal_price_milliunits is
  'What the next renewal costs, in milliunits of renewal_currency, as Apple computes it — offer included. The only honest figure: no plan price column knows the storefront.';
comment on column public.user_subscriptions.renewal_currency is
  'Currency of renewal_price_milliunits (the Apple ID storefront, which need not match the learner''s language).';
comment on column public.user_subscriptions.renewal_product_id is
  'Apple autoRenewProductId — what renews, which differs from the current product after a plan change. Stored, not yet shown; surfacing it means naming the incoming plan, and that is a copy decision nobody has made.';

-- Owner read already covers these (policy "user_subscriptions: owner read"),
-- and nothing client-side may write the table.
