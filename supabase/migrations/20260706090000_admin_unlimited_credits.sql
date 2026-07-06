-- Admin / unlimited credit accounts.
--
-- Testing burns real credits; the dev account kept running dry. Instead of
-- repeatedly topping up, `user_credits.unlimited = true` makes charge_credits
-- a no-op for that account: the balance never moves, but a delta-0 ledger row
-- is still written so usage analytics keep seeing admin traffic (tagged
-- {"unlimited": true} so it can be excluded from revenue math).
--
-- Refunds are guarded the same way — otherwise a failed upstream call would
-- ADD credits to an account that was never debited, inflating the balance.
--
-- Flagging an account stays a manual one-liner (see bottom) — no signup path
-- ever sets this.

alter table public.user_credits
  add column if not exists unlimited boolean not null default false;

-- Recreate charge_credits with the unlimited short-circuit. Same signature,
-- so the Edge Functions don't change at all.
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

  -- Unlimited (admin/test) account: record the usage for analytics, but
  -- never touch the balance.
  if coalesce(v_unlimited, false) then
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb) || '{"unlimited": true}'::jsonb);
    return v_new_balance;
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

-- Refund guard: an unlimited account was never debited, so refunding an
-- upstream failure must not add credits. Grants/topups stay allowed.
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
  v_unlimited boolean;
begin
  if p_credits < 0 then raise exception 'p_credits must be >= 0'; end if;

  -- Idempotency
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_new_balance from user_credits where user_id = p_user_id;
    return coalesce(v_new_balance, 0);
  end if;

  if p_kind = 'refund' then
    select unlimited into v_unlimited from user_credits where user_id = p_user_id;
    if coalesce(v_unlimited, false) then
      insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
      values (p_user_id, 'refund', 0, p_action, p_source_fn, p_idempotency_key,
              coalesce(p_metadata, '{}'::jsonb) || '{"unlimited": true}'::jsonb);
      select balance into v_new_balance from user_credits where user_id = p_user_id;
      return coalesce(v_new_balance, 0);
    end if;
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

-- To flag an account (run manually, never from app code):
--   update public.user_credits
--      set unlimited = true, balance = 999999, updated_at = now()
--    where user_id = '<auth.users.id>';
