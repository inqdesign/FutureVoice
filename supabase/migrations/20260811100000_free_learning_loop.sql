-- Free the learning loop: Gemini calls and review TTS stop costing credits.
--
-- Beta feedback was unanimous: per-click credit anxiety ("복습만 해도 6~10씩
-- 사라져서 쉽게 안 하게 되네요") was killing exploration and daily review —
-- the exact behaviours the app is built around. The new billing model meters
-- ONE thing (talk/scene minutes, i.e. new audio in your voice) and makes
-- everything else free, defended by invisible daily caps instead of prices:
--
--   * Gemini calls: real upstream cost is ~$0.002/call vs the 1 credit
--     (~$0.04) we charged — the charge was 95% margin and 100% of the click
--     fear. Now 0 credits, guarded by a per-purpose daily request cap.
--   * Review TTS (drill / library / shadow / previews / voicemail): short
--     lines, cached forever in PhraseAudioStore after first synthesis, and
--     review material only exists as the OUTPUT of metered activities — so
--     free review is structurally bounded. Guarded by a daily free-char pool;
--     chars past the pool fall through to the normal paid path (so a client
--     spoofing `purpose: "drill"` to smuggle conversation audio gains at most
--     the pool, not a faucet).
--
-- Ledger rows keep being written at delta 0 so per-feature cost attribution
-- and abuse detection survive the price change.

-- ---------------------------------------------------------------------------
-- 1) Daily counters for free (0-credit) usage, per purpose.
-- ---------------------------------------------------------------------------

create table if not exists public.free_usage_daily (
  user_id    uuid not null references auth.users(id) on delete cascade,
  day        date not null,
  purpose    text not null,               -- client purpose tag ("turn", "topics", …)
  count      integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, day, purpose)
);
alter table public.free_usage_daily enable row level security;
-- No client policies on purpose: only the SECURITY DEFINER functions below
-- ever touch this table.

-- Record one free call: bump the daily counter, stamp a 0-delta ledger row
-- (idempotent), and raise RATE_LIMITED past the cap. The raise rolls back
-- the increment, so a capped user retrying doesn't inflate the counter.
create or replace function public.record_free_usage(
  p_user_id uuid,
  p_action text,
  p_purpose text,
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null,
  p_daily_cap integer default 300
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  -- Idempotency: a retried key must not double-count against the cap.
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select count into v_count from free_usage_daily
     where user_id = p_user_id and day = current_date and purpose = p_purpose;
    return coalesce(v_count, 0);
  end if;

  insert into free_usage_daily (user_id, day, purpose, count)
  values (p_user_id, current_date, p_purpose, 1)
  on conflict (user_id, day, purpose) do update
    set count = free_usage_daily.count + 1,
        updated_at = now()
  returning count into v_count;

  if v_count > p_daily_cap then
    raise exception 'RATE_LIMITED' using errcode = 'P0004';
  end if;

  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
          coalesce(p_metadata, '{}'::jsonb)
            || jsonb_build_object('free', true, 'daily_count', v_count));

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Free TTS char pool: review synthesis is free up to a daily char budget;
--    past it, the SAME call falls through to the normal paid pooled charge.
-- ---------------------------------------------------------------------------

-- Returns { "balance": int, "charged": int, "free": bool }.
-- `charged` is what THIS call debited (0 while inside the free pool) —
-- refundable by the edge function exactly like charge_tts_pooled's result.
create or replace function public.charge_tts_free_pooled(
  p_user_id uuid,
  p_chars integer,
  p_action text,                 -- 'tts' | 'tts_timestamps' (paid fall-through pricing)
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null,
  p_free_chars_per_day integer default 12000
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old     bigint;
  v_new     bigint;
  v_balance integer;
begin
  if p_chars <= 0 then raise exception 'p_chars must be > 0'; end if;
  if p_action not in ('tts', 'tts_timestamps') then
    raise exception 'unsupported pooled action %', p_action;
  end if;

  -- Idempotency: a retried key must neither re-accumulate nor re-charge.
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0),
                              'charged', 0, 'free', true);
  end if;

  -- Free pool rows live beside the paid ones, under their own action key.
  insert into tts_char_pool (user_id, day, action, chars)
  values (p_user_id, current_date, 'free_tts', p_chars)
  on conflict (user_id, day, action) do update
    set chars = tts_char_pool.chars + excluded.chars,
        updated_at = now()
  returning chars - p_chars, chars into v_old, v_new;

  if v_new <= p_free_chars_per_day then
    select balance into v_balance from user_credits where user_id = p_user_id;
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('free', true, 'free_pool_total', v_new));
    return jsonb_build_object('balance', coalesce(v_balance, 0),
                              'charged', 0, 'free', true);
  end if;

  -- Over the daily free budget: undo this call's free accumulation and charge
  -- the whole line through the normal paid pool. charge_tts_pooled stamps the
  -- ledger row + idempotency key; INSUFFICIENT_CREDITS raises and rolls back
  -- everything, including the revert above (which is correct — a failed call
  -- shouldn't consume free budget either).
  update tts_char_pool
     set chars = v_old, updated_at = now()
   where user_id = p_user_id and day = current_date and action = 'free_tts';

  return public.charge_tts_pooled(
    p_user_id => p_user_id,
    p_chars => p_chars,
    p_action => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('free_pool_exhausted', true)
  ) || jsonb_build_object('free', false);
end;
$$;
