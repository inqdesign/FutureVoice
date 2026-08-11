-- Admin accounts: from "unlimited no-op" to a real 500-credit auto-reset cycle.
--
-- The unlimited flag used to make charge_credits a no-op (delta-0 ledger
-- rows), which meant admin usage never measured what it WOULD have billed —
-- sums over the ledger showed zero spend for exactly the traffic the owner
-- uses to gauge real costs. Now flagged accounts are charged for REAL: every
-- debit lands with its true delta, and only when a debit would overdraw does
-- the balance snap back to 500 first (its own 'grant' row, tagged
-- {"auto_reset": true}, so refills separate cleanly from spend in queries).
--
-- The account still never blocks — the flag's promise is "never hit the
-- credit wall", not "free". Flagging stays a manual one-liner (bottom).

create or replace function public.charge_credits(
  p_user_id uuid,
  p_credits integer,
  p_action text,
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_balance integer;
  v_unlimited boolean;
begin
  if p_credits < 0 then raise exception 'p_credits must be >= 0'; end if;

  -- Idempotency: if the same key has already been recorded, return the
  -- balance unchanged. Lets clients safely retry on transient failures.
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_new_balance from user_credits where user_id = p_user_id;
    return coalesce(v_new_balance, 0);
  end if;

  select unlimited, balance into v_unlimited, v_new_balance
    from user_credits where user_id = p_user_id;

  if v_new_balance is null then
    raise exception 'NO_CREDIT_ROW' using errcode = 'P0002';
  end if;

  -- Auto-reset (admin/test) account about to overdraw: refill to 500 BEFORE
  -- the debit, as its own ledger row. The debit below then proceeds exactly
  -- like any paying user's — same delta, same metadata — so admin traffic
  -- measures true spend. (Reset+debit share this transaction: both land or
  -- neither does.)
  if coalesce(v_unlimited, false) and (v_new_balance - p_credits) < 0 then
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'grant', 500 - v_new_balance, 'cycle_grant', p_source_fn,
            p_idempotency_key || ':auto-reset',
            '{"auto_reset": true}'::jsonb);
    update user_credits
       set balance = 500, updated_at = now()
     where user_id = p_user_id;
    v_new_balance := 500;
  end if;

  update user_credits
     set balance = balance - p_credits,
         updated_at = now()
   where user_id = p_user_id
   returning balance into v_new_balance;

  if v_new_balance < 0 then
    raise exception 'INSUFFICIENT_CREDITS' using errcode = 'P0001';
  end if;

  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (p_user_id, 'debit', -p_credits, p_action, p_source_fn, p_idempotency_key, p_metadata);

  return v_new_balance;
end;
$$;

-- Refunds work normally again for flagged accounts: they ARE debited now, so
-- an upstream failure legitimately restores what was taken. (The old guard
-- existed only because no-op debits made refunds pure inflation.)
create or replace function public.grant_credits(
  p_user_id uuid,
  p_credits integer,
  p_kind public.ledger_kind,
  p_action text,
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_balance integer;
begin
  if p_credits < 0 then raise exception 'p_credits must be >= 0'; end if;

  -- Idempotency
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_new_balance from user_credits where user_id = p_user_id;
    return coalesce(v_new_balance, 0);
  end if;

  insert into user_credits (user_id, balance, updated_at)
  values (p_user_id, p_credits, now())
  on conflict (user_id) do update
    set balance = user_credits.balance + excluded.balance,
        updated_at = now()
  returning balance into v_new_balance;

  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (p_user_id, p_kind, p_credits, p_action, p_source_fn, p_idempotency_key, p_metadata);

  return v_new_balance;
end;
$$;

-- Flagged accounts drop from the old cosmetic 999999 to a real starting
-- cycle. (Their ledger history keeps the delta-0 era; measurement starts
-- clean from here.)
update public.user_credits
   set balance = 500, updated_at = now()
 where unlimited;

-- To flag an account (run manually, never from app code):
--   update public.user_credits
--      set unlimited = true, balance = 500, updated_at = now()
--    where user_id = '<auth.users.id>';
