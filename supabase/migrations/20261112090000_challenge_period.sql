-- A period for the 100-day challenge package (20261112100000). Its own
-- migration: a new enum value cannot be used in the batch that adds it.
alter type public.subscription_period add value if not exists 'challenge';
