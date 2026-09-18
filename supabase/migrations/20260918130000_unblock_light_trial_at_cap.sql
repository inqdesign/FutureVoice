-- The one Light trial stopped at the trial cap (2026-09-18). One-off, by hand,
-- same lever and reasoning as 20260918120000 (the four Plus trials): the
-- invite-minutes balance is spent before the trial cap is checked, so this
-- unblocks exactly this account for exactly this many seconds.
--
--   4e4d6bf5  light_monthly  hit 09-18, trial ends 09-21, auto-renew ON
--
-- 35 min = one more trial's worth. Unlike Plus, Light talk keeps drawing on
-- the balance after the trial converts (only an uncapped plan skips it), so
-- whatever is left simply joins the month's 150 min as bonus time.
--
-- Skips the account if it is no longer trialing when this runs; the
-- idempotency key makes a second run a no-op.

do $$
declare
  r record;
begin
  for r in
    select s.user_id
      from public.user_subscriptions s
     where s.user_id = '4e4d6bf5-be9a-45cf-ac08-feb8b3ca5ade'
       and s.status = 'trialing'
       and s.plan_id like 'light_%'
  loop
    perform public.grant_credits(
      r.user_id, 2100, 'grant'::public.ledger_kind,
      'trial_cap_unblock', 'migration',
      'trial_cap_unblock:20260918:' || r.user_id::text,
      jsonb_build_object('reason', 'light trial walled at 35 min',
                         'migration', '20260918130000'));
  end loop;
end $$;
