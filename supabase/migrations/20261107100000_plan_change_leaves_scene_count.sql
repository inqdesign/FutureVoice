-- ---------------------------------------------------------------------------
-- A plan change also ends scene COUNT billing (2026-11-07, founder).
--
-- `scene_count_billing` (20261019120000) keeps every account that had a
-- subscription row on 2026-10-19 on the old rule: Watch scenes are counted
-- against the plan's scene pool instead of costing five talk minutes. That
-- protected what those people had BOUGHT. A plan change is a purchase of
-- today's plan (20261104100000), so from that moment the account is treated
-- exactly like a new subscriber of the plan it now holds: the stamp is
-- cleared (already done by that trigger) and, with this file, the account
-- leaves `scene_count_billing`, so scenes are paid from the talk pool.
--
-- Raised for setia1115@ (00c6a881, Light on a launch code, 150 min nearly
-- spent): an upgrade to Plus should give them Plus as sold today, 450 min
-- with scenes inside it, not 450 min plus 30 counted scenes on top.
--
-- Same trigger, same edge: `plan_id` actually changing. Apple applies an
-- upgrade at once and a downgrade or crossgrade at renewal, and the webhook
-- writes the transaction's own product, so this fires when the new plan
-- starts. Monthly ↔ annual of the same tier is a plan change too and is
-- treated the same way. A removed row is never put back by anything; that is
-- the point of the rule.
--
-- SECURITY DEFINER because the writers (webhooks on the service role, hand
-- comps) are not all granted on `scene_count_billing`, which is revoked from
-- every client role.
-- ---------------------------------------------------------------------------

create or replace function public.clear_stamp_on_plan_change()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
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
    delete from public.scene_count_billing where user_id = new.user_id;
  end if;
  return new;
end;
$$;
