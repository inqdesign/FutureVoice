-- Four Plus trials stopped at the trial cap (2026-09-18). One-off, by hand.
--
-- A trial is metered at the Light pool pro-rated 7/30 (35 min) whatever plan
-- it trials, so a week's sample can't be spent and cancelled. That rule stays.
-- These four reached it 1-4 days in, all with auto-renew ON, and have been
-- walled since — on the tier whose card says "No limit":
--
--   703341ce  plus_monthly  hit 09-16, trial ends 09-19
--   09101cc8  plus_monthly  hit 09-16, trial ends 09-20
--   2ba4ed7d  plus_annual   hit 09-17, trial ends 09-21
--   1f5c04ca  plus_monthly  hit 09-17, trial ends 09-23
--
-- The lever is the invite-minutes balance: `consume_metered_seconds` spends a
-- positive balance BEFORE it looks at the trial cap (the gateway's 1 s
-- preflight included), so a grant unblocks exactly these accounts for exactly
-- this many seconds and changes no rule for anyone else. It is bounded — a
-- use-then-cancel can take at most the grant. Once the trial converts, Plus
-- talk no longer draws on the balance (uncapped path), so what's left only
-- ever pays for Watch scenes or outlives a lapse.
--
-- Skips anyone no longer trialing when this runs; the idempotency key makes a
-- second run a no-op.

do $$
declare
  r record;
begin
  for r in
    select s.user_id
      from public.user_subscriptions s
     where s.user_id in ('703341ce-49b0-4e06-9ab8-b228605330c2',
                         '09101cc8-94f7-4bc1-b11e-52ba668eb18b',
                         '2ba4ed7d-9f92-4289-8970-0684aa362b71',
                         '1f5c04ca-e7e9-4b82-a962-99988b341ed1')
       and s.status = 'trialing'
       and s.plan_id like 'plus_%'
  loop
    perform public.grant_credits(
      r.user_id, 3600, 'grant'::public.ledger_kind,
      'trial_cap_unblock', 'migration',
      'trial_cap_unblock:20260918:' || r.user_id::text,
      jsonb_build_object('reason', 'plus trial walled at 35 min',
                         'migration', '20260918120000'));
  end loop;
end $$;
