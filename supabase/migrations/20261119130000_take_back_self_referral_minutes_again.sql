-- ---------------------------------------------------------------------------
-- The self-referral of 20261118150000, a fourth account (2026-11-19, founder:
-- "leave ten minutes, take the rest").
--
-- The inviter of that migration (fee71d6c, code HSUJR7) was open at 14:04 and
-- 14:07 UTC on 2026-11-19; a new Google account was made at 14:04 and
-- redeemed HSUJR7 at 14:10. It was not seen as the same person (free minutes
-- not withheld), so it held 1,200 free + 1,800 invite = 3,000 seconds.
--
-- The balance comes down to 600 seconds (never raised, nothing below 600
-- touched), only while the account is still free (no subscription row, not
-- unlimited), and once (the ledger key). An ordinary balance update, so the
-- expiring-balance trigger keeps its rows in step. The redemption row stays.
-- ---------------------------------------------------------------------------

with eligible as (
  select c.user_id, c.balance - 600 as take
  from public.user_credits c
  where c.user_id = 'a20f4b00-0660-4cdc-a3e6-343a81dca67f'::uuid
    and not coalesce(c.unlimited, false)
    and c.balance > 600
    and not exists (select 1 from public.user_subscriptions s where s.user_id = c.user_id)
    and not exists (select 1 from public.usage_ledger l
                     where l.idempotency_key = 'self_referral_takeback:' || c.user_id::text)
),
logged as (
  insert into public.usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  select user_id, 'debit', -take, 'referral_takeback', 'migration',
         'self_referral_takeback:' || user_id::text,
         jsonb_build_object('code', 'HSUJR7', 'reason', 'self_referral', 'seconds', take, 'left', 600)
  from eligible
  on conflict (idempotency_key) do nothing
  returning user_id
)
update public.user_credits c
set balance = c.balance - e.take, updated_at = now()
from eligible e
where c.user_id = e.user_id;
