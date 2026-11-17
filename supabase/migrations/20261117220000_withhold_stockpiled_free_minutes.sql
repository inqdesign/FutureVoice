-- ---------------------------------------------------------------------------
-- Take the free minutes off three stockpiled accounts (2026-11-17, founder).
--
-- The Veracruz learner of 20261115180000 made several Gmail accounts within
-- minutes on 2026-11-15, before the once-per-person check existed. That
-- check only withholds at signup or on a NEW account (under a day old) on a
-- known device, so accounts made that evening and left unused kept their
-- 20 minutes. Today one of them (belsonata22) was picked up on the same
-- phone and is in use; the founder keeps that one and zeroes the rest.
--
-- Only the free balance is touched, only on these three ids, and only while
-- the account is still free (no subscription row, not unlimited). Recorded
-- in free_grant_withheld as 'device' so free_recharge_reason answers
-- 'returning' and the one free recharge stays closed too.
-- ---------------------------------------------------------------------------

with targets(id) as (
  values
    ('9e7467e0-d935-4773-9073-97f59cd798e2'::uuid),  -- belenhuerta777
    ('1dc07a92-2482-4dc7-8178-932707375ea1'::uuid),  -- belymoon013
    ('346baa59-950c-4b7d-81c9-1572cb22f620'::uuid)   -- belenhuertacalleja777
),
eligible as (
  select c.user_id, c.balance
  from public.user_credits c
  join targets t on t.id = c.user_id
  where not c.unlimited
    and c.balance > 0
    and not exists (select 1 from public.user_subscriptions s where s.user_id = c.user_id)
),
logged as (
  insert into public.free_grant_withheld (user_id, reason, seconds)
  select user_id, 'device', balance from eligible
  on conflict (user_id) do nothing
  returning user_id
)
update public.user_credits c
set balance = 0, updated_at = now()
from eligible e
where c.user_id = e.user_id;
