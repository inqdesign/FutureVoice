-- ---------------------------------------------------------------------------
-- Take back the invite minutes one person paid to themself
-- (2026-11-18, founder).
--
-- The Android phone of 20261118140000 made three accounts in 36 minutes; the
-- free minutes of the second and third were withheld (email, device). At
-- 15:37 UTC the third redeemed the second's invite code, and both got 1,800
-- seconds: more than the 1,200 that had just been withheld.
--
-- Each account loses what is left of its 1,800 (never below 0, nothing else
-- in the balance touched), only while it is still free (no subscription
-- row, not unlimited), and once (the ledger key). An ordinary balance
-- update, so the expiring-balance trigger keeps its rows in step. The
-- redemption row stays, so neither side can be paid for this invite again.
-- ---------------------------------------------------------------------------

with targets(id) as (
  values
    ('fee71d6c-c07b-40cd-8fa1-e52251f7e506'::uuid),  -- inviter (2nd account)
    ('71bcea67-2c50-4275-b460-b0719d0cc4d8'::uuid)   -- invitee (3rd account)
),
eligible as (
  select c.user_id, least(c.balance, 1800) as take
  from public.user_credits c
  join targets t on t.id = c.user_id
  where not coalesce(c.unlimited, false)
    and c.balance > 0
    and not exists (select 1 from public.user_subscriptions s where s.user_id = c.user_id)
    and not exists (select 1 from public.usage_ledger l
                     where l.idempotency_key = 'self_referral_takeback:' || c.user_id::text)
),
logged as (
  insert into public.usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  select user_id, 'debit', -take, 'referral_takeback', 'migration',
         'self_referral_takeback:' || user_id::text,
         jsonb_build_object('code', 'HSUJR7', 'reason', 'self_referral', 'seconds', take)
  from eligible
  on conflict (idempotency_key) do nothing
  returning user_id
)
update public.user_credits c
set balance = c.balance - e.take, updated_at = now()
from eligible e
where c.user_id = e.user_id;
