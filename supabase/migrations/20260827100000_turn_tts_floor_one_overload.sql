-- Turn TTS stopped mid-call with a 500 once a day's fluent-self text passed
-- ~1,500 characters (2026-08-27, owner's account; one other balance-holding
-- account exposed). Two faults stacked, and both are fixed here.
--
-- 1. `charge_tts_pooled` existed TWICE. `20260814100000` added `p_pool` with a
--    default via `create or replace`, which in Postgres creates a NEW overload
--    beside the old six-argument one. `charge_turn_tts_floored` calls it with
--    six named arguments — which match both — so the moment the turn floor was
--    exceeded the call died with `function … is not unique` (42725) and the
--    edge function returned "charge failed". `charge_talk_seconds` has the
--    same pair (`20260816120000` added `p_language default null`); a client
--    that omits the language would fail the same way. One overload each.
--
-- 2. The floor never grew for anyone spending a BALANCE. `charge_turn_tts_floored`
--    read today's ticked seconds from `tts_char_pool.talk_seconds`, but since
--    `20260821100000` a tick covered by invite minutes (or any positive
--    balance) returns before that pool is written — deliberately, so the
--    month's pool figures keep describing the month. So for those accounts the
--    floor sat at its 2-minute base (1,500 chars/day), and every line after
--    that fell through to the paid pool — straight into fault 1. The floor now
--    sums today's `talk_time` rows in `usage_ledger`, which every metering path
--    writes (`metadata.seconds` is stamped by `talk-tick` on all of them).
--    The pool stays untouched, so allowances and the Core are unaffected.
--
-- Rollback: the dropped overloads' bodies are in `20260811160000` and
-- `20260811130000`; the previous floor body is in `20260811130000`.

drop function if exists public.charge_tts_pooled(uuid, integer, text, text, text, jsonb);
drop function if exists public.charge_talk_seconds(uuid, integer, text, text, jsonb);

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

  -- Every tick the meter accepted today, whichever pool paid for it. The
  -- ledger is the one place all three paths (plan, invite minutes, balance)
  -- write; `tts_char_pool.talk_seconds` sees only the plan's.
  select coalesce(sum(coalesce((metadata->>'seconds')::integer, 0)), 0)
    into v_talk_secs
    from usage_ledger
   where user_id = p_user_id
     and action = 'talk_time'
     and created_at >= current_date;
  v_allowed := 750 * (v_talk_secs / 60 + 2);

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

revoke all on function public.charge_turn_tts_floored(uuid, integer, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.charge_turn_tts_floored(uuid, integer, text, text, text, jsonb)
  to service_role;
