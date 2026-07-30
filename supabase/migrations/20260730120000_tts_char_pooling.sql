-- TTS billing: pool characters per (user, day, action) instead of rounding
-- per call.
--
-- The old scheme charged ceil(chars/100) with a 1-credit minimum PER CALL,
-- so short lines were badly overcharged: a 10-char word cost a full credit,
-- and a Watch scene of ~12 short lines cost ~12 credits for ~800 chars of
-- audio (~8 credits' worth). Pooling accumulates the day's characters and
-- charges only when the running total crosses each 100-char boundary —
-- long-run price identical (1 credit / 100 chars; with-timestamps +25%),
-- per-line rounding gone. Client-transparent: same endpoints, same actions.

create table if not exists public.tts_char_pool (
  user_id    uuid not null references auth.users(id) on delete cascade,
  day        date not null,
  action     text not null,               -- 'tts' | 'tts_timestamps'
  chars      bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, day, action)
);
alter table public.tts_char_pool enable row level security;
-- No client policies on purpose: only the SECURITY DEFINER function below
-- ever touches this table.

-- Returns { "balance": <int>, "charged": <int> } — `charged` lets the edge
-- function refund exactly what this call debited if the upstream fails.
create or replace function public.charge_tts_pooled(
  p_user_id uuid,
  p_chars integer,
  p_action text,
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old     bigint;
  v_new     bigint;
  v_due     integer;
  v_balance integer;
  v_num     integer;   -- rate numerator: credits(x) = ceil(x * num / 10000)
begin
  if p_chars <= 0 then raise exception 'p_chars must be > 0'; end if;
  if p_action not in ('tts', 'tts_timestamps') then
    raise exception 'unsupported pooled action %', p_action;
  end if;

  -- Idempotency: a retried key must neither re-charge nor re-accumulate.
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0);
  end if;

  -- Mirrors the old priceFor(): tts = 100 chars/credit, timestamps +25%.
  v_num := case when p_action = 'tts_timestamps' then 125 else 100 end;

  -- Row-level lock on the conflict update serializes concurrent calls.
  insert into tts_char_pool (user_id, day, action, chars)
  values (p_user_id, current_date, p_action, p_chars)
  on conflict (user_id, day, action) do update
    set chars = tts_char_pool.chars + excluded.chars,
        updated_at = now()
  returning chars - p_chars, chars into v_old, v_new;

  v_due := ((v_new * v_num + 9999) / 10000) - ((v_old * v_num + 9999) / 10000);

  -- charge_credits stamps the ledger row (even at 0 credits) + the
  -- idempotency key. INSUFFICIENT_CREDITS raises → this whole transaction
  -- rolls back, INCLUDING the pool increment above.
  v_balance := public.charge_credits(
    p_user_id => p_user_id,
    p_credits => v_due,
    p_action  => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('pooled_chars', p_chars, 'pool_total', v_new)
  );

  return jsonb_build_object('balance', v_balance, 'charged', v_due);
end;
$$;
