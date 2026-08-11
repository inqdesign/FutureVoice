-- Talk-time metering — phase 2 of the minutes model (see docs/launch-billing.md).
--
-- The meter moves to the ONE place users already expect one: the in-call
-- timer. The app ticks wall-clock seconds during an active call
-- (`talk-tick` Edge Function → charge_talk_seconds), debiting the existing
-- credit balance at 4.5 credits/minute — the same effective rate the old
-- per-turn charges averaged, so plan allowances keep their meaning
-- (300 cr ≈ 66 min). In exchange, turn/opener TTS stops being char-priced:
-- it's covered by the ticking minutes, with a chars-per-minute FLOOR so a
-- client that under-reports call time (or never ticks) still pays.
--
-- Scene (Watch) audio meters by its playback length instead of raw chars:
-- ~850 chars ≈ 1 minute of synthesized speech ≈ 4.5 credits, so "a scene
-- costs about a minute" is literally true on the same scale as talking.

-- ---------------------------------------------------------------------------
-- 1) Wall-clock talk seconds → credits. Seconds pool per (user, day) in
--    tts_char_pool (the `chars` column holds seconds under the
--    'talk_seconds' action key — it's a generic per-day counter). Credits
--    debit on running-total boundary crossings: 4.5 cr / 60 s = 75/1000 per
--    second, long-run exact, integer debits along the way.
-- ---------------------------------------------------------------------------

create or replace function public.charge_talk_seconds(
  p_user_id uuid,
  p_seconds integer,
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
begin
  if p_seconds < 1 or p_seconds > 600 then
    raise exception 'p_seconds out of range';
  end if;

  -- Idempotency: a retried tick must neither re-charge nor re-accumulate.
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_balance from user_credits where user_id = p_user_id;
    select chars into v_new from tts_char_pool
     where user_id = p_user_id and day = current_date and action = 'talk_seconds';
    return jsonb_build_object('balance', coalesce(v_balance, 0),
                              'charged', 0,
                              'seconds_today', coalesce(v_new, 0));
  end if;

  insert into tts_char_pool (user_id, day, action, chars)
  values (p_user_id, current_date, 'talk_seconds', p_seconds)
  on conflict (user_id, day, action) do update
    set chars = tts_char_pool.chars + excluded.chars,
        updated_at = now()
  returning chars - p_seconds, chars into v_old, v_new;

  -- ceil(x * 75 / 1000) crossings — 60 s of new talk ≈ 4.5 credits.
  v_due := ((v_new * 75 + 999) / 1000) - ((v_old * 75 + 999) / 1000);

  -- charge_credits stamps the ledger row + idempotency key, honors the
  -- admin `unlimited` flag, and raises INSUFFICIENT_CREDITS (rolling back
  -- the pool increment above) when the balance is spent.
  v_balance := public.charge_credits(
    p_user_id => p_user_id,
    p_credits => v_due,
    p_action  => 'talk_time',
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_new)
  );

  return jsonb_build_object('balance', v_balance, 'charged', v_due,
                            'seconds_today', v_new);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Turn/opener TTS: free while the day's chars stay under a
--    chars-per-talk-minute FLOOR (750 chars × (talk minutes + 2 min grace)).
--    750 chars/min is a ceiling no real conversation reaches (the fluent
--    self speaks roughly half the call at ~850 chars per SPOKEN minute);
--    the grace covers the greeting prewarm and the opener, which synthesize
--    before any seconds have ticked. Past the floor — i.e. a client feeding
--    text through the TTS while under-reporting call time — the whole call
--    falls through to the normal paid char pool.
-- ---------------------------------------------------------------------------

create or replace function public.charge_turn_tts_floored(
  p_user_id uuid,
  p_chars integer,
  p_action text,                 -- 'tts' | 'tts_timestamps' (fall-through pricing)
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_talk_secs bigint;
  v_old       bigint;
  v_new       bigint;
  v_allowed   bigint;
  v_balance   integer;
begin
  if p_chars <= 0 then raise exception 'p_chars must be > 0'; end if;
  if p_action not in ('tts', 'tts_timestamps') then
    raise exception 'unsupported floored action %', p_action;
  end if;

  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0),
                              'charged', 0, 'free', true);
  end if;

  select chars into v_talk_secs from tts_char_pool
   where user_id = p_user_id and day = current_date and action = 'talk_seconds';
  v_allowed := 750 * (coalesce(v_talk_secs, 0) / 60 + 2);

  insert into tts_char_pool (user_id, day, action, chars)
  values (p_user_id, current_date, 'turn_chars', p_chars)
  on conflict (user_id, day, action) do update
    set chars = tts_char_pool.chars + excluded.chars,
        updated_at = now()
  returning chars - p_chars, chars into v_old, v_new;

  if v_new <= v_allowed then
    -- Covered by ticking minutes: 0-delta ledger row (via charge_credits so
    -- idempotency + the admin unlimited flag behave identically everywhere).
    v_balance := public.charge_credits(
      p_user_id => p_user_id,
      p_credits => 0,
      p_action  => p_action,
      p_source_fn => p_source_fn,
      p_idempotency_key => p_idempotency_key,
      p_metadata => coalesce(p_metadata, '{}'::jsonb)
        || jsonb_build_object('free', true, 'turn_chars_today', v_new)
    );
    return jsonb_build_object('balance', v_balance, 'charged', 0, 'free', true);
  end if;

  -- Floor exceeded: revert this call's accumulation and charge the whole
  -- line through the paid pool. INSUFFICIENT_CREDITS raises and rolls back
  -- everything, including the revert (correct — a failed call shouldn't
  -- move the floor either).
  update tts_char_pool
     set chars = v_old, updated_at = now()
   where user_id = p_user_id and day = current_date and action = 'turn_chars';

  return public.charge_tts_pooled(
    p_user_id => p_user_id,
    p_chars => p_chars,
    p_action => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('turn_floor_exceeded', true)
  ) || jsonb_build_object('free', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) Scene audio priced by playback time: 'tts_scene' pools at 53/10000
--    (0.53 cr / 100 chars → ~850 chars ≈ 4.5 cr ≈ 1 minute of speech).
--    Same function, one new action key; 'tts'/'tts_timestamps' unchanged.
-- ---------------------------------------------------------------------------

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
  if p_action not in ('tts', 'tts_timestamps', 'tts_scene') then
    raise exception 'unsupported pooled action %', p_action;
  end if;

  -- Idempotency: a retried key must neither re-charge nor re-accumulate.
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0);
  end if;

  -- tts = 100 chars/credit, timestamps +25%, scene = playback-time rate.
  v_num := case p_action
    when 'tts_timestamps' then 125
    when 'tts_scene'      then 53
    else 100
  end;

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
