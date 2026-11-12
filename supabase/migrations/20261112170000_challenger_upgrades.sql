-- A challenger who moved up a size, and minutes the founder gave on top
-- (2026-11-12: everyone starts on Light; more is paid for as the difference,
-- or given by hand). Kept on the application so the desk shows what happened.
--
--   upgraded_at / upgrade_amount / upgrade_currency
--       the last paid move up (stripe-webhook, from the checkout made by the
--       challenge-upgrade function); amount in the currency's minor unit
--   extra_seconds
--       talk time given by hand from the desk, added up
alter table public.creator_applications
  add column if not exists upgraded_at timestamptz,
  add column if not exists upgrade_amount integer,
  add column if not exists upgrade_currency text,
  add column if not exists extra_seconds integer not null default 0;
