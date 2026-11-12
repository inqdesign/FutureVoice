-- A challenger pays when applying (2026-11-12, founder: it is prepaid), and the
-- application remembers who paid and what the challenge earned them.
--
--   user_id       the app account that bought the 100-day package; written by
--                 stripe-webhook from the checkout's application id. It is what
--                 ties an application to its daily talk time.
--   paid_at       when the package was paid
--   paid_plan     the package bought (light_challenge, …)
--   reward_months months given for the months kept (0–3), once, from the admin:
--                 each month kept is one free month
--   rewarded_at   when that was given

alter table public.creator_applications
  add column if not exists user_id uuid references auth.users(id) on delete set null,
  add column if not exists paid_at timestamptz,
  add column if not exists paid_plan text,
  add column if not exists reward_months integer check (reward_months between 0 and 3),
  add column if not exists rewarded_at timestamptz;

-- The day cohort 1 starts. Unknown while people already pay, so it lives where
-- both the webhook and the admin can read it: a package paid before this day
-- runs its 100 days from it (three months, and ten days on the house). Set
-- from the admin's creators page, which also moves the packages already paid.
alter table public.billing_config
  add column if not exists challenge_starts_at timestamptz;
