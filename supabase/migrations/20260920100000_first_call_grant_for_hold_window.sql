-- ---------------------------------------------------------------------------
-- Accounts created while the first-call grant was held get it now.
--
-- 20260919120000 set new accounts to 0 until 1.0.6 was on the store, and
-- 20260920090000 turned the grant back on — but only for accounts created
-- AFTER it, so anyone who signed up in between still meets the paywall on
-- their first tap. Same selection and same idempotency key as the
-- 20260918100000 backfill: still at zero, nothing bought, never a second of
-- talk. The key means nobody who already got a first-call grant gets another.
-- ---------------------------------------------------------------------------

do $$
declare
  r record;
begin
  for r in
    select c.user_id
      from public.user_credits c
      join auth.users u on u.id = c.user_id
     where u.created_at >= '2026-09-19'
       and c.balance = 0
       and not coalesce(c.unlimited, false)
       and not exists (select 1 from public.user_subscriptions s
                        where s.user_id = c.user_id
                          and s.status in ('active', 'trialing'))
       and not exists (select 1 from public.usage_ledger l
                        where l.user_id = c.user_id
                          and l.action = 'talk_time')
  loop
    perform public.grant_credits(
      r.user_id, 300, 'grant'::public.ledger_kind,
      'first_call_grant', 'migration',
      'first_call_grant:' || r.user_id::text,
      jsonb_build_object('reason', 'first call is free (hold window)',
                         'migration', '20260920100000'));
  end loop;
end $$;
