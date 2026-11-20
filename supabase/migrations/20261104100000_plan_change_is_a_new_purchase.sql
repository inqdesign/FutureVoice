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

-- ---------------------------------------------------------------------------
-- 2026-11-04: this file was written as 20261012140000, the SAME version as
-- 20261012140000_people_have_their_own_voices, and only that one was ever
-- recorded in schema_migrations — so the trigger above never existed in
-- production and `db push` thought it was done. Renamed to its own version.
--
-- The one row that changed plan while the trigger was missing: b989b404 went
-- plus_monthly → light_annual at the 2026-11-02 renewal and kept the Plus
-- stamp from 20261027120000 (36000 s + 30 scenes), so Usage read 600 min on a
-- Light plan. It follows light_annual from here (150 min + 10 scenes a month;
-- ~13 min spent this period, so nothing they have done is refused).
-- ---------------------------------------------------------------------------

update public.user_subscriptions
   set monthly_seconds = null,
       monthly_scenes  = null,
       talk_unlimited  = null
 where user_id = 'b989b404-4d76-4176-82e1-6d7b2ce84eb6'
   and plan_id = 'light_annual';
