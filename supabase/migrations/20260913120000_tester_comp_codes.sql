-- ---------------------------------------------------------------------------
-- Five one-month comp codes, for testers asked to try the app by hand.
--
-- `plus_monthly` on purpose: a test must not end because the tester ran out of
-- minutes, and Plus is the tier with no talk ceiling (20260821120000). Scenes
-- are still counted (120), which is the one real limit they can meet.
--
-- One code per person (`max_redemptions = 1`) — a shared string is a coupon
-- for whoever it leaks to. The CODE lapses in 30 days if nobody uses it; the
-- month itself is counted from redemption, and the nightly sweep
-- (`expire_comp_subscriptions`) ends it because a coded comp is written
-- `cancel_at_period_end = true`.
--
-- Fill in the `note` as they are handed out — it is the only record of who
-- got which code.
-- ---------------------------------------------------------------------------
insert into public.comp_codes (code, plan_id, months, max_redemptions, note, expires_at)
values
  ('MMRXRVDL', 'plus_monthly', 1, 1, 'tester 1 (unassigned)', now() + interval '30 days'),
  ('6ZR8HEQR', 'plus_monthly', 1, 1, 'tester 2 (unassigned)', now() + interval '30 days'),
  ('LA9YXWG8', 'plus_monthly', 1, 1, 'tester 3 (unassigned)', now() + interval '30 days'),
  ('RZYWS632', 'plus_monthly', 1, 1, 'tester 4 (unassigned)', now() + interval '30 days'),
  ('BMDMWQ2P', 'plus_monthly', 1, 1, 'tester 5 (unassigned)', now() + interval '30 days')
on conflict (code) do nothing;
