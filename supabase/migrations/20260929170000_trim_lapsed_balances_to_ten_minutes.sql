-- ---------------------------------------------------------------------------
-- Five lapsed accounts down to 10 minutes of talk (2026-09-29, founder decision).
--
-- Each had a subscription that has since EXPIRED and still carried a one-time
-- balance of 35 min to 1 h 39 min, which `consume_metered_seconds` keeps
-- spending with no plan behind it. The admin heatmap's new 남은 통화 column
-- made it visible.
--
--   64a84428-ac2e-4852-8fa4-50db527836c8  holly       5960 s
--   e8e660dc-5a31-41ce-81d5-598bc19dd560  Emma        2240 s
--   703341ce-49b0-4e06-9ab8-b228605330c2  Mark        3600 s
--   4e4d6bf5-be9a-45cf-ac08-feb8b3ca5ade  (피오나)     2100 s
--   2ba4ed7d-9f92-4289-8970-0684aa362b71  msoul0404   2833 s
--   (balances as read 2026-09-29 morning)
--
-- Reads the balance AT RUN TIME and only ever LOWERS it to 600 s — someone
-- who has already talked below 10 min is left alone. One `debit` ledger row
-- per account records exactly what was removed; the idempotency key makes a
-- second run a no-op.
-- ---------------------------------------------------------------------------
with target(user_id) as (values
  ('64a84428-ac2e-4852-8fa4-50db527836c8'::uuid),
  ('e8e660dc-5a31-41ce-81d5-598bc19dd560'::uuid),
  ('703341ce-49b0-4e06-9ab8-b228605330c2'::uuid),
  ('4e4d6bf5-be9a-45cf-ac08-feb8b3ca5ade'::uuid),
  ('2ba4ed7d-9f92-4289-8970-0684aa362b71'::uuid)
),
cut as (
  select c.user_id, c.balance as was
    from public.user_credits c
    join target t using (user_id)
   where c.balance > 600
     and not exists (select 1 from public.usage_ledger l
                      where l.idempotency_key = 'trim_to_10min_20260929:' || c.user_id)
     for update of c
),
upd as (
  update public.user_credits c
     set balance = 600, updated_at = now()
    from cut
   where c.user_id = cut.user_id
  returning c.user_id
)
insert into public.usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
select cut.user_id, 'debit'::public.ledger_kind, 600 - cut.was, 'balance_trim', 'migration',
       'trim_to_10min_20260929:' || cut.user_id,
       jsonb_build_object('reason', 'lapsed subscription, balance trimmed to 10 min',
                          'was', cut.was, 'now', 600, 'migration', '20260929170000')
  from cut join upd using (user_id);
