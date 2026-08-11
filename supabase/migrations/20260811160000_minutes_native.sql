-- Minutes-native billing — credits stop existing as a unit.
--
-- The old model stored CREDITS and converted to minutes for display
-- (4.5 cr = 1 min). This migration makes the server speak the same unit the
-- user sees: SECONDS of synthesized talk. Table and function names stay the
-- same (every RPC signature survives, deployed clients keep working), but
-- `user_credits.balance` now holds seconds, and every charge path debits
-- seconds of audio.
--
-- Who pays what (docs/launch-billing.md, tiers section):
--   * Subscribers (trialing/active/grace) have NO balance. Their plan buys a
--     per-day allowance (`subscription_plans.daily_seconds`): Daily (pro_*)
--     = 300 s (5 min/day), Unlimited (premium_*) = 3600 s (60 min/day
--     fair-use ceiling, invisible in UI). Talk seconds and Watch scene
--     seconds accumulate in the SAME daily meter; past the cap the day is
--     over (DAILY_CAP_REACHED), resetting at midnight UTC. No cycle grants,
--     no rollover — a subscription is an allowance, not a wallet.
--   * Free users keep a one-time seconds pool: existing balances convert at
--     4.5 cr = 60 s (x 40/3), the signup grant becomes 3960 s (66 min).
--   * Admin (`unlimited` flag): unchanged mechanics — charged for real,
--     auto-reset before overdraw — with the reset value in seconds (6600 s
--     = 110 min, the old 500 cr).
--
-- What consumes seconds: Talk = wall-clock call time (charge_talk_seconds),
-- Watch scenes = playback length of their audio (~850 chars ≈ 60 s), plus
-- the abuse fall-throughs (turn-TTS past the chars-per-minute floor, review
-- TTS past the daily free pool) at the same chars→seconds rate. Everything
-- else (Gemini, review TTS, clones) is free, bounded by daily caps.

-- ---------------------------------------------------------------------------
-- 1) Plans: the per-day allowance. credits_per_cycle stays for old clients'
--    paywall display but nothing grants from it anymore.
-- ---------------------------------------------------------------------------

alter table public.subscription_plans
  add column if not exists daily_seconds integer;

update public.subscription_plans set daily_seconds = 300  where tier = 'pro';
update public.subscription_plans set daily_seconds = 3600 where tier = 'premium';

-- ---------------------------------------------------------------------------
-- 2) Convert stored balances: credits → seconds (4.5 cr = 60 s → x 40/3).
--    Ledger history keeps its credit-era deltas untouched — rows carry their
--    unit implicitly by date; sums across the boundary are meaningless
--    either way.
-- ---------------------------------------------------------------------------

-- ONE-TIME and guarded: running this file twice must not re-multiply
-- balances (it happened on 2026-08-11 — a second execution inflated every
-- balance ×13.3 and had to be hand-reverted). The marker ledger row makes
-- the conversion idempotent.
do $$
begin
  if not exists (
    select 1 from usage_ledger where idempotency_key = 'minutes_native_conversion'
  ) then
    update public.user_credits
       set balance     = round(balance * 40.0 / 3)::integer,
           cycle_grant = round(cycle_grant * 40.0 / 3)::integer,
           updated_at  = now();
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    select user_id, 'grant', 0, 'unit_conversion', 'migration',
           'minutes_native_conversion', '{"note": "credits->seconds x40/3"}'::jsonb
      from public.user_credits limit 1;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3) The one metering function. Accumulates seconds into the per-day pool,
--    then answers "who covers this?": an entitled subscription's daily
--    allowance (delta-0 ledger row), or the free user's seconds balance
--    (real debit via charge_credits, which also owns the admin auto-reset).
-- ---------------------------------------------------------------------------

create or replace function public.consume_metered_seconds(
  p_user_id uuid,
  p_seconds integer,
  p_pool text,                  -- 'talk_seconds' | 'scene_seconds'
  p_action text,                -- ledger action tag ('talk_time', 'tts_scene', …)
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   bigint;
  v_cap     integer;
  v_balance integer;
begin
  if p_seconds < 0 or p_seconds > 3600 then
    raise exception 'p_seconds out of range';
  end if;
  if p_pool not in ('talk_seconds', 'scene_seconds') then
    raise exception 'unsupported pool %', p_pool;
  end if;

  -- Idempotency: a retried key must neither re-accumulate nor re-charge.
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_balance from user_credits where user_id = p_user_id;
    select coalesce(sum(chars), 0) into v_today from tts_char_pool
     where user_id = p_user_id and day = current_date
       and action in ('talk_seconds', 'scene_seconds');
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today);
  end if;

  if p_seconds > 0 then
    insert into tts_char_pool (user_id, day, action, chars)
    values (p_user_id, current_date, p_pool, p_seconds)
    on conflict (user_id, day, action) do update
      set chars = tts_char_pool.chars + excluded.chars,
          updated_at = now();
  end if;

  select coalesce(sum(chars), 0) into v_today from tts_char_pool
   where user_id = p_user_id and day = current_date
     and action in ('talk_seconds', 'scene_seconds');

  -- Entitled subscriber: the plan's daily allowance covers it, balance
  -- untouched. Past the cap → raise (rolls back this call's accumulation).
  select p.daily_seconds into v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  if v_cap is not null then
    if v_today > v_cap then
      raise exception 'DAILY_CAP_REACHED' using errcode = 'P0005';
    end if;
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                                    'covered_by', 'plan'));
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today, 'daily_cap', v_cap,
                              'covered_by', 'plan');
  end if;

  -- Free user (and the admin flag, which charge_credits handles): debit the
  -- seconds balance. INSUFFICIENT_CREDITS raises through, rolling back the
  -- accumulation above.
  v_balance := public.charge_credits(
    p_user_id => p_user_id,
    p_credits => p_seconds,
    p_action  => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                            'covered_by', 'balance'));
  return jsonb_build_object('balance', v_balance, 'charged', p_seconds,
                            'seconds_today', v_today, 'covered_by', 'balance');
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) Talk: wall-clock seconds, 1 s of call = 1 s of allowance/balance.
--    Same signature and response keys as before, so deployed clients' tick
--    loop keeps working (their minutes DISPLAY divides by 4.5 until they
--    update — display-only skew, bounded to the beta).
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
begin
  if p_seconds < 1 or p_seconds > 600 then
    raise exception 'p_seconds out of range';
  end if;
  return public.consume_metered_seconds(
    p_user_id => p_user_id,
    p_seconds => p_seconds,
    p_pool    => 'talk_seconds',
    p_action  => 'talk_time',
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => p_metadata);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) Char-priced paths now convert characters to SECONDS of speech at
--    850 chars ≈ 60 s (numerator 706/10000: 850 × 706 / 10000 = 60.01) and
--    consume those seconds. Applies to Watch scenes ('tts_scene') and to the
--    two abuse fall-throughs ('tts' / 'tts_timestamps' past their free
--    pools) — same audio, same conversion, one rate. The per-day char pool
--    keeps the crossing math exact across many small calls.
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
  v_old      bigint;
  v_new      bigint;
  v_secs_due integer;
begin
  if p_chars <= 0 then raise exception 'p_chars must be > 0'; end if;
  if p_action not in ('tts', 'tts_timestamps', 'tts_scene') then
    raise exception 'unsupported pooled action %', p_action;
  end if;

  -- Idempotency: a retried key must neither re-charge nor re-accumulate.
  -- (consume_metered_seconds checks again, but the char accumulation below
  -- must not repeat either.)
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    return public.consume_metered_seconds(
      p_user_id => p_user_id, p_seconds => 0, p_pool => 'scene_seconds',
      p_action => p_action, p_source_fn => p_source_fn,
      p_idempotency_key => p_idempotency_key, p_metadata => p_metadata);
  end if;

  -- Row-level lock on the conflict update serializes concurrent calls.
  insert into tts_char_pool (user_id, day, action, chars)
  values (p_user_id, current_date, p_action, p_chars)
  on conflict (user_id, day, action) do update
    set chars = tts_char_pool.chars + excluded.chars,
        updated_at = now()
  returning chars - p_chars, chars into v_old, v_new;

  -- Seconds due = crossings of chars × 706 / 10000 (850 chars ≈ 60 s).
  v_secs_due := ((v_new * 706 + 9999) / 10000) - ((v_old * 706 + 9999) / 10000);

  -- consume stamps the ledger row + idempotency key; DAILY_CAP_REACHED /
  -- INSUFFICIENT_CREDITS raise → this whole transaction rolls back,
  -- INCLUDING the char accumulation above.
  return public.consume_metered_seconds(
    p_user_id => p_user_id,
    p_seconds => v_secs_due,
    p_pool    => 'scene_seconds',
    p_action  => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('pooled_chars', p_chars, 'pool_total', v_new));
end;
$$;

-- charge_turn_tts_floored and charge_tts_free_pooled are unchanged: their
-- free branches stamp delta-0 rows, and their paid fall-throughs delegate to
-- charge_tts_pooled — which now consumes seconds.

-- ---------------------------------------------------------------------------
-- 6) Admin auto-reset: same mechanics as 20260809120000, value now in
--    seconds (6600 s = 110 min ≈ the old 500 cr tank).
-- ---------------------------------------------------------------------------

create or replace function public.charge_credits(
  p_user_id uuid,
  p_credits integer,             -- SECONDS since this migration (name kept
                                 -- so every caller survives unchanged)
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

  -- Auto-reset (admin/test) account about to overdraw: refill BEFORE the
  -- debit, as its own ledger row, so admin traffic measures true spend.
  if coalesce(v_unlimited, false) and (v_new_balance - p_credits) < 0 then
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'grant', 6600 - v_new_balance, 'cycle_grant', p_source_fn,
            p_idempotency_key || ':auto-reset',
            '{"auto_reset": true}'::jsonb);
    update user_credits
       set balance = 6600, updated_at = now()
     where user_id = p_user_id;
    v_new_balance := 6600;
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

-- ---------------------------------------------------------------------------
-- 7) Grants in seconds: signup 3960 s (66 min, the old 300 cr), referral
--    3960 s both sides. Past grants keep their credit-era rows; the balance
--    conversion above already translated them.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
begin
  perform public.grant_credits(
    p_user_id => new.id,
    p_credits => 3960,            -- seconds: 66 min one-time pool
    p_kind => 'grant',
    p_action => 'beta_signup_grant',
    p_source_fn => 'auth_trigger',
    p_idempotency_key => 'min66:' || new.id::text,
    p_metadata => jsonb_build_object('reason', 'signup grant, 66 talk minutes')
  );
  return new;
end;
$$;

create or replace function public.redeem_referral(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitee uuid := auth.uid();
  v_inviter uuid;
  v_code text := upper(trim(p_code));
  v_invite_count int;
  v_balance int;
  v_inviter_rewarded boolean := false;
begin
  if v_invitee is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if v_code is null or length(v_code) = 0 then raise exception 'INVALID_CODE'; end if;

  select user_id into v_inviter from referral_codes where code = v_code;
  if v_inviter is null then raise exception 'INVALID_CODE'; end if;
  if v_inviter = v_invitee then raise exception 'SELF_REFERRAL'; end if;
  if exists (select 1 from referral_redemptions where invitee_id = v_invitee) then
    raise exception 'ALREADY_REDEEMED';
  end if;

  insert into referral_redemptions(invitee_id, inviter_id, code)
  values (v_invitee, v_inviter, v_code);

  -- Invitee bonus (one-time), in seconds: 66 min, same as the signup grant.
  v_balance := public.grant_credits(
    p_user_id => v_invitee, p_credits => 3960, p_kind => 'grant',
    p_action => 'referral_invitee', p_source_fn => 'redeem_referral',
    p_idempotency_key => 'ref_invitee:' || v_invitee::text,
    p_metadata => jsonb_build_object('code', v_code, 'inviter', v_inviter)
  );

  -- Inviter bonus, capped at the first 10 successful invites.
  select count(*) into v_invite_count
    from referral_redemptions where inviter_id = v_inviter;
  if v_invite_count <= 10 then
    perform public.grant_credits(
      p_user_id => v_inviter, p_credits => 3960, p_kind => 'grant',
      p_action => 'referral_inviter', p_source_fn => 'redeem_referral',
      p_idempotency_key => 'ref_inviter:' || v_invitee::text,
      p_metadata => jsonb_build_object('code', v_code, 'invitee', v_invitee)
    );
    v_inviter_rewarded := true;
  end if;

  return jsonb_build_object(
    'balance', v_balance,
    'invitee_bonus', 3960,
    'inviter_rewarded', v_inviter_rewarded
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 8) Let the app READ today's metered seconds (the Me tab / home ring shows
--    "N of 5 min today" for Daily-plan users). Writes still happen only
--    through the SECURITY DEFINER functions.
-- ---------------------------------------------------------------------------

alter table public.tts_char_pool enable row level security;
drop policy if exists "tts_char_pool: owner read" on public.tts_char_pool;
create policy "tts_char_pool: owner read" on public.tts_char_pool
  for select using (auth.uid() = user_id);
