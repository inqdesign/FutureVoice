-- ---------------------------------------------------------------------------
-- A plan CHANGE is a purchase of today's plan (2026-10-12).
--
-- `user_subscriptions.monthly_seconds` / `.talk_unlimited` / `.monthly_scenes`
-- stamp what a row was SOLD (20260925140000, 20260926110000), and every meter
-- reads the stamp before the plan. Nothing that writes the row touches those
-- columns — `apple-webhook`, `apple-claim` and the Stripe webhook upsert
-- `plan_id` and leave the stamp alone — so the stamp survived a plan change:
--
--   · Light → Plus (an Apple upgrade applies and charges at once): the row
--     reads `plus_monthly` and is metered at the LIGHT stamp. Found on
--     2026-10-12 for setia1115@ (Light, launch code, stamped 9000 s + 60
--     scenes): upgrading would have charged Plus's full price for 150 min.
--   · Plus → Light: a legacy Plus row (900 min, 20260926140000) would carry
--     900 minutes onto a $9.99 plan — the case CLAUDE.md flagged as
--     "unfixed with three rows, watch it".
--
-- The rule: when `plan_id` changes, the stamp is cleared, so the row follows
-- the plan it now holds (NULL = follow `subscription_plans`, the state of
-- every row bought since the stamps were introduced). A writer that sets the
-- stamp in the SAME statement (a migration re-stamping by hand) wins: only a
-- stamp carried over unchanged is cleared.
--
-- Done as a trigger, not in each function, because there are three writers
-- (two Apple, one Stripe) plus hand-written comps, and the bug was exactly a
-- writer that didn't know about the stamp. `INSERT … ON CONFLICT DO UPDATE`
-- runs BEFORE UPDATE triggers on the conflict path, which is how every
-- webhook writes.
--
-- Apple applies a downgrade or crossgrade at RENEWAL, and the webhook takes
-- `plan_id` from the transaction's own product, so the stamp is cleared when
-- the new plan actually starts, never when it is merely scheduled.
-- ---------------------------------------------------------------------------

create or replace function public.clear_stamp_on_plan_change()
 returns trigger
 language plpgsql
as $$
begin
  if new.plan_id is distinct from old.plan_id then
    if new.monthly_seconds is not distinct from old.monthly_seconds then
      new.monthly_seconds := null;
    end if;
    if new.talk_unlimited is not distinct from old.talk_unlimited then
      new.talk_unlimited := null;
    end if;
    if new.monthly_scenes is not distinct from old.monthly_scenes then
      new.monthly_scenes := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists user_subscriptions_clear_stamp_on_plan_change
  on public.user_subscriptions;

create trigger user_subscriptions_clear_stamp_on_plan_change
  before update of plan_id on public.user_subscriptions
  for each row
  execute function public.clear_stamp_on_plan_change();
