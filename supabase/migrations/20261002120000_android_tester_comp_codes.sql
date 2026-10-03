-- ---------------------------------------------------------------------------
-- Fifteen one-month comp codes for the Android closed test.
--
-- Play asks a new personal developer account for 12 testers opted in for 14
-- days before it will open production; fifteen leaves room for the ones who
-- never install. The Play subscriptions are not on sale yet (plan 7.1), so a
-- tester's only way past the 20 free minutes is a code — redeemed on the
-- paywall's "Have a code?" or Me → Invite, both of which call
-- `redeem_referral`.
--
-- Same shape as 20260913120000_tester_comp_codes: Plus, one person per code,
-- the CODE lapses in 30 days unused, the month counts from redemption and
-- ends (`cancel_at_period_end = true`). Fill in `note` as they go out — it is
-- the only record of who got which.
-- ---------------------------------------------------------------------------
insert into public.comp_codes (code, plan_id, months, max_redemptions, note, expires_at)
values
  ('HNL45RQJ', 'plus_monthly', 1, 1, 'android tester 1 (unassigned)', now() + interval '30 days'),
  ('3S6BADST', 'plus_monthly', 1, 1, 'android tester 2 (unassigned)', now() + interval '30 days'),
  ('SC64C6VZ', 'plus_monthly', 1, 1, 'android tester 3 (unassigned)', now() + interval '30 days'),
  ('JW7QAWC9', 'plus_monthly', 1, 1, 'android tester 4 (unassigned)', now() + interval '30 days'),
  ('YF4CYJDM', 'plus_monthly', 1, 1, 'android tester 5 (unassigned)', now() + interval '30 days'),
  ('BDLN6D9X', 'plus_monthly', 1, 1, 'android tester 6 (unassigned)', now() + interval '30 days'),
  ('FUVFVXRJ', 'plus_monthly', 1, 1, 'android tester 7 (unassigned)', now() + interval '30 days'),
  ('ZC8PLJ8P', 'plus_monthly', 1, 1, 'android tester 8 (unassigned)', now() + interval '30 days'),
  ('989ASFVB', 'plus_monthly', 1, 1, 'android tester 9 (unassigned)', now() + interval '30 days'),
  ('T6DAAY3A', 'plus_monthly', 1, 1, 'android tester 10 (unassigned)', now() + interval '30 days'),
  ('HDBVNHZS', 'plus_monthly', 1, 1, 'android tester 11 (unassigned)', now() + interval '30 days'),
  ('C5XMMNBC', 'plus_monthly', 1, 1, 'android tester 12 (unassigned)', now() + interval '30 days'),
  ('K5Y3XA7A', 'plus_monthly', 1, 1, 'android tester 13 (unassigned)', now() + interval '30 days'),
  ('EQW8662X', 'plus_monthly', 1, 1, 'android tester 14 (unassigned)', now() + interval '30 days'),
  ('3ACJJ2QZ', 'plus_monthly', 1, 1, 'android tester 15 (unassigned)', now() + interval '30 days')
on conflict (code) do nothing;
