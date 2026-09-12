-- ---------------------------------------------------------------------------
-- The learner can see their own subscription, as Apple bills it.
--
-- Me → Talk time showed the plan name and a refill date and nothing else.
-- What a subscriber actually asks — since when, what it costs, when the next
-- charge is, whether the launch code's discount is still running — was all
-- on the server and shown nowhere. Managing the subscription (cancel, change)
-- stays Apple's, so the page only READS; but reading needs two things:
--
--   1. `subscription_transactions` readable by its owner (it never was —
--      only service_role), so the last charge and its currency can be shown.
--   2. The offer that priced a transaction. Apple's transaction carries
--      offerType (1 intro, 2 promotional, 3 offer code), offerDiscountType
--      (FREE_TRIAL / PAY_AS_YOU_GO / PAY_UP_FRONT) and offerPeriod (ISO 8601,
--      e.g. P1M); the webhook and apple-claim decoded them and threw them
--      away. Stored now, so "code discount running" is a fact from Apple's
--      receipt rather than a guess from the price.
-- ---------------------------------------------------------------------------

alter table public.subscription_transactions
  add column if not exists offer_type          smallint,
  add column if not exists offer_discount_type text,
  add column if not exists offer_period        text;

comment on column public.subscription_transactions.offer_type is
  'Apple offerType: 1 introductory, 2 promotional, 3 offer code. Null = full price.';

drop policy if exists "subscription_transactions: owner read" on public.subscription_transactions;
create policy "subscription_transactions: owner read"
  on public.subscription_transactions for select
  using (auth.uid() = user_id);

grant select on public.subscription_transactions to authenticated;
