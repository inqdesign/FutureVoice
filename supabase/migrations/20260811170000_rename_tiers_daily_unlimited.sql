-- Tier names say what they ARE: pro → daily, premium → unlimited.
--
-- The old names ranked features ("pro", "premium"); the product sells
-- QUANTITY of talk time, and the tier names should be the same words the
-- UI shows (데일리 / Daily, 무제한 / Unlimited). Renamed everywhere — enum,
-- plan ids, apple product ids — while App Store Connect products don't
-- exist yet (launch checklist); once ASC products are created these ids
-- freeze.
--
-- Plan id is a PRIMARY KEY referenced by user_subscriptions.plan_id, so the
-- rename is insert-new → repoint-subs → delete-old.

-- 1) Enum values (guarded so a re-run is a no-op).
do $$
begin
  if exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
              where t.typname = 'subscription_tier' and e.enumlabel = 'pro') then
    alter type public.subscription_tier rename value 'pro' to 'daily';
  end if;
  if exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
              where t.typname = 'subscription_tier' and e.enumlabel = 'premium') then
    alter type public.subscription_tier rename value 'premium' to 'unlimited';
  end if;
end $$;

-- 2) Plan rows: new ids first (FK-safe), repoint subscriptions, drop old.
insert into public.subscription_plans
       (id, tier, period, credits_per_cycle, apple_product_id, is_active, daily_seconds)
select replace(replace(id, 'pro_', 'daily_'), 'premium_', 'unlimited_'),
       tier, period, credits_per_cycle,
       replace(replace(apple_product_id, 'pro_', 'daily_'), 'premium_', 'unlimited_'),
       is_active, daily_seconds
  from public.subscription_plans
 where id like 'pro\_%' or id like 'premium\_%'
on conflict (id) do nothing;

update public.user_subscriptions
   set plan_id = replace(replace(plan_id, 'pro_', 'daily_'), 'premium_', 'unlimited_')
 where plan_id like 'pro\_%' or plan_id like 'premium\_%';

delete from public.subscription_plans
 where id like 'pro\_%' or id like 'premium\_%';
