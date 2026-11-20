-- ---------------------------------------------------------------------------
-- A replayed idempotency key counts against the daily cap
-- (2026-11-20, security review).
--
-- record_free_usage answered a key it had already seen with the current
-- count and counted nothing: right for a retry, and a way past every free
-- cap. The key is the client's, so one key sent in a loop was one use
-- forever — 24 accent previews a day became as many Cartesia syntheses as
-- the connection could carry (voice-remix has no hourly limit and takes an
-- anonymous session), and the same for pronunciation reads, speech
-- references, cover images and every `gemini` purpose.
--
-- Now a replay moves the counter and meets the cap like a first use; only
-- the ledger row is not written twice. An honest retry costs one count, and
-- the caps are abuse ceilings several times above real use (30 days to
-- 2026-11-20: the heaviest learner-day per purpose sits under its cap).
-- ---------------------------------------------------------------------------

create or replace function public.record_free_usage(
  p_user_id uuid, p_action text, p_purpose text, p_source_fn text,
  p_idempotency_key text, p_metadata jsonb default null::jsonb,
  p_daily_cap integer default 300)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_count  integer;
  v_replay boolean;
begin
  v_replay := p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key);

  insert into free_usage_daily (user_id, day, purpose, count)
  values (p_user_id, current_date, p_purpose, 1)
  on conflict (user_id, day, purpose) do update
    set count = free_usage_daily.count + 1,
        updated_at = now()
  returning count into v_count;

  if v_count > p_daily_cap then
    raise exception 'RATE_LIMITED' using errcode = 'P0004';
  end if;

  if not v_replay then
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('free', true, 'daily_count', v_count));
  end if;

  return v_count;
end;
$function$;
