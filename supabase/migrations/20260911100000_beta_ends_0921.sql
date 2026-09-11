-- ---------------------------------------------------------------------------
-- The beta ends on 2026-09-21.
--
-- `20260910120000` filed the five hand-comped beta testers as STANDING comps
-- (`cancel_at_period_end = false`), which the nightly sweep rolls forever.
-- Decided 2026-09-11: the beta has an end, and it is the day those rows were
-- already pointing at — the period end of 2026-09-21 that every tester's
-- Talk-time page has been printing since August. So the same rows flip to
-- `cancel_at_period_end = true`: the sweep on 09-22 00:25 UTC expires them
-- instead of rolling them, the app's date label turns from "Refills on" to
-- "Ends on" by itself (`AccountStatus.cancelAtPeriodEnd`), and nothing else
-- changes until then.
--
-- What testers get AFTER the beta is not a comp — it is half price, which no
-- server row can express: the store sets the price. Apple offer codes and a
-- Stripe promotion code carry it (see the note in docs/launch-billing.md);
-- both land through the ordinary webhooks as paid rows.
--
-- The owner's Plus row stays standing — it is not a beta seat.
-- ---------------------------------------------------------------------------

with ended as (
  update user_subscriptions
     set cancel_at_period_end = true,
         updated_at = now()
   where source = 'comp'
     and status in ('active', 'trialing', 'grace')
     and cancel_at_period_end = false
     and plan_id like 'light_%'
     and current_period_end::date = date '2026-09-21'
  returning user_id, plan_id, current_period_end
)
insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
select user_id, 'grant', 0, 'comp_subscription', 'migration',
       'comp:beta-ends-2026-09-21:' || user_id::text,
       jsonb_build_object('plan_id', plan_id, 'standing', false,
                          'ends_at', current_period_end,
                          'note', 'beta ends 2026-09-21; comp no longer rolls')
  from ended
on conflict (idempotency_key) do nothing;
