-- "Hear it in my voice": a Speech script read whole in the learner's own
-- cloned voice, paid for in TALK MINUTES (2026-10-14, founder decision).
--
-- The price is 3x the audio length, rounded UP to whole minutes:
--     charge_seconds = ceil(audio_seconds * 3 / 60) * 60
-- (60 s of audio -> 3 min, 40 s -> 2 min, 80 s -> 4 min). It is charged ONCE
-- per (user, voiceover key), where the app's key names the script text and the
-- voice — replaying, or shadowing from it, is free forever after.
--
-- The learner sees the price on the button BEFORE they tap (an estimate from
-- the script's length), and is never charged more than that number: the
-- reservation stores it (`quoted_seconds`) and the final charge is
--     least(charge_seconds(actual audio), quoted_seconds).
-- So a quote the app makes cannot be gamed down, the server puts a FLOOR under
-- it from the script's character count (`script_voiceover_quote_floor`) —
-- generous to the learner (a fast 25 characters a second), so an honest
-- estimate is never raised by it.
--
-- HOW IT FLOWS — reserve, synthesize, then charge:
--   1. `reserve_script_voiceover(key, quoted_seconds, chars)` (the app, before
--      a single character is synthesized). Refuses with the same error words
--      the 402s carry (`insufficient_credits` / `daily_cap_reached`) when the
--      pools can't cover the quote, so nobody synthesizes what they can't pay
--      for. Charges nothing.
--   2. Every line goes through `elevenlabs-tts` with
--      `purpose: "script-voiceover"` + `voiceover_key`. That purpose is NOT
--      metered per character; instead the function claims the line's
--      characters against the reservation (`claim_script_voiceover_chars`,
--      service role) and refuses the line without one — so the purpose can't
--      be used as free synthesis. After the line is made it records the
--      seconds upstream actually produced (`note_script_voiceover_seconds`),
--      which is the server's own measure of the audio.
--   3. `charge_script_voiceover(key, audio_seconds)` (the app, AFTER the whole
--      voiceover was made and saved). Charges least(price(audio), quote),
--      where audio = greatest(what the app measured, what the server
--      recorded) — the app can't under-report below the server's figure.
--      Idempotent: a second call returns the first charge.
--   A failed synthesis never reaches step 3, so it costs nothing.
--   `script_voiceover_can_pay(quoted_seconds)` is the same check as step 1
--   without a key, for the composer's "also make it in my voice", asked
--   before the script is written.
--
-- And the one hole step 3 leaves — a client that makes the audio and never
-- asks to be charged — is closed LAZILY: a reservation still open after two
-- hours is settled the next time that learner reserves anything. If the server
-- saw (nearly) all of its characters synthesized it is charged then, at the
-- same price; otherwise it was a failure and simply expires. No cron.
--
-- WHAT PAYS. The same pools a call spends, in the same order, through the
-- unchanged `consume_metered_seconds` (pool 'talk_seconds', action
-- 'script_voiceover', so the usage ledger keeps it apart from talk): invite
-- minutes / packs first when they cover the whole charge, then the plan's
-- period pool (Light, Plus and a trial all pay — a trial from its pro-rated
-- pool), and an account with no plan from its balance. One rule is added in
-- front of it here and nowhere else: the whole charge must be COVERED. The
-- talk meter takes "whatever is left" on a free account's last tick (so a
-- call lands exactly on zero); a voiceover is one purchase, and a purchase is
-- not sold for part of its price. A legacy uncapped Plus row records the
-- seconds (they count toward its fair-use line) and is never walled.
--
-- ADDITIVE ONLY: a new table and new functions. No existing function changes.

create table if not exists public.script_voiceovers (
  user_id               uuid not null references auth.users(id) on delete cascade,
  key                   text not null check (length(key) between 8 and 200),
  status                text not null default 'reserved'
                          check (status in ('reserved', 'charged', 'expired', 'unpaid')),
  quoted_seconds        integer not null check (quoted_seconds between 60 and 3600),
  -- Characters of the script this reservation covers. Lines may claim up to
  -- twice that (one full retry of a failed run) plus a little slack.
  max_chars             integer not null check (max_chars between 1 and 40000),
  chars_used            integer not null default 0,
  server_audio_seconds  numeric not null default 0,
  charged_seconds       integer,
  created_at            timestamptz not null default now(),
  settled_at            timestamptz,
  primary key (user_id, key)
);

-- Read and written only through the functions below.
alter table public.script_voiceovers enable row level security;

-- The price, in seconds of talk time. The app's `ScriptVoiceover.chargeSeconds`
-- is the same formula; keep the two the same.
create or replace function public.script_voiceover_price(p_audio_seconds numeric)
 returns integer
 language sql
 immutable
as $$
  select (ceil(greatest(p_audio_seconds, 0) * 3 / 60.0) * 60)::integer;
$$;

-- The least a quote may be for a script of p_chars characters: as if it were
-- read at a fast 25 characters a second (English at ~15/s, Korean ~8/s,
-- Japanese ~7/s), with a minimum of one minute.
create or replace function public.script_voiceover_quote_floor(p_chars integer)
 returns integer
 language sql
 immutable
as $$
  select greatest(60, public.script_voiceover_price(greatest(p_chars, 0) / 25.0));
$$;

-- NULL when the account can pay p_seconds of talk time in full right now,
-- otherwise the 402 word the app already knows. Mirrors the order
-- `consume_metered_seconds` spends in, so a yes here is a yes there.
create or replace function public.script_voiceover_wall(p_user_id uuid, p_seconds integer)
 returns text
 language plpgsql
 stable security definer
 set search_path to 'public'
as $$
declare
  v_entitled  boolean := false;
  v_unlimited boolean := false;
  v_cap       integer;
  v_balance   integer;
begin
  select true,
         s.status <> 'trialing' and coalesce(s.talk_unlimited, p.talk_unlimited, false),
         case when s.status = 'trialing'
              then coalesce(s.monthly_seconds,
                            (select min(monthly_seconds) from subscription_plans
                              where tier = 'light'), p.monthly_seconds) * 7 / 30
              else coalesce(s.monthly_seconds, p.monthly_seconds) end
    into v_entitled, v_unlimited, v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  select balance into v_balance from user_credits where user_id = p_user_id;

  if v_entitled is true and v_unlimited is true then
    return null;
  end if;
  if coalesce(v_balance, 0) >= p_seconds then
    return null;
  end if;
  if v_entitled is true and v_cap is not null then
    if public.plan_period_seconds(p_user_id) + p_seconds <= v_cap then
      return null;
    end if;
    return 'daily_cap_reached';
  end if;
  return 'insufficient_credits';
end;
$$;

-- Charges one reservation (internal). Returns the jsonb the app reads.
create or replace function public.script_voiceover_settle(p_user_id uuid, p_key text,
                                                          p_audio_seconds numeric)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $$
declare
  v_row    script_voiceovers%rowtype;
  v_audio  numeric;
  v_charge integer;
  v_wall   text;
  v_result jsonb;
begin
  select * into v_row from script_voiceovers
   where user_id = p_user_id and key = p_key
   for update;
  if not found then
    return jsonb_build_object('error', 'not_reserved');
  end if;
  if v_row.status = 'charged' then
    return jsonb_build_object('status', 'charged', 'charged_seconds', v_row.charged_seconds,
                              'already', true);
  end if;

  v_audio := greatest(coalesce(p_audio_seconds, 0), v_row.server_audio_seconds);
  v_charge := least(public.script_voiceover_price(v_audio), v_row.quoted_seconds);
  v_charge := greatest(v_charge, 60);

  v_wall := public.script_voiceover_wall(p_user_id, v_charge);
  if v_wall is not null then
    return jsonb_build_object('error', v_wall);
  end if;

  begin
    v_result := public.consume_metered_seconds(
      p_user_id         => p_user_id,
      p_seconds         => v_charge,
      p_pool            => 'talk_seconds',
      p_action          => 'script_voiceover',
      p_source_fn       => 'script-voiceover',
      p_idempotency_key => 'script_voiceover:' || p_user_id::text || ':' || p_key,
      p_metadata        => jsonb_build_object('voiceover_key', p_key,
                                              'audio_seconds', round(v_audio, 1),
                                              'quoted_seconds', v_row.quoted_seconds));
  exception
    when others then
      if sqlerrm like '%DAILY_CAP_REACHED%' then return jsonb_build_object('error', 'daily_cap_reached'); end if;
      if sqlerrm like '%FAIR_USE_LIMIT%' then return jsonb_build_object('error', 'fair_use_limit'); end if;
      if sqlerrm like '%INSUFFICIENT_CREDITS%' or sqlerrm like '%NO_CREDIT_ROW%' then
        return jsonb_build_object('error', 'insufficient_credits');
      end if;
      raise;
  end;

  update script_voiceovers
     set status = 'charged', charged_seconds = v_charge, settled_at = now()
   where user_id = p_user_id and key = p_key;

  return jsonb_build_object('status', 'charged', 'charged_seconds', v_charge,
                            'balance', v_result->'balance');
end;
$$;

-- Step 1. Before anything is synthesized.
create or replace function public.reserve_script_voiceover(p_key text, p_quoted_seconds integer,
                                                           p_chars integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $$
declare
  v_uid    uuid := auth.uid();
  v_quote  integer;
  v_row    script_voiceovers%rowtype;
  v_stale  record;
  v_open   integer;
  v_wall   text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_key is null or length(p_key) not between 8 and 200 then raise exception 'bad key'; end if;
  if p_chars is null or p_chars < 1 or p_chars > 20000 then raise exception 'bad chars'; end if;
  if p_quoted_seconds is null or p_quoted_seconds < 60 or p_quoted_seconds > 3600
     or p_quoted_seconds % 60 <> 0 then
    raise exception 'bad quote';
  end if;
  v_quote := least(3600, greatest(p_quoted_seconds, public.script_voiceover_quote_floor(p_chars)));

  select * into v_row from script_voiceovers where user_id = v_uid and key = p_key;
  if found and v_row.status = 'charged' then
    return jsonb_build_object('status', 'charged', 'charged_seconds', v_row.charged_seconds);
  end if;

  -- Settle what was left open (see the header): finished runs are charged at
  -- their own quote, failed ones expire.
  for v_stale in
    select key, max_chars, chars_used, server_audio_seconds from script_voiceovers
     where user_id = v_uid and status = 'reserved' and key <> p_key
       and created_at < now() - interval '2 hours'
  loop
    if v_stale.chars_used >= v_stale.max_chars * 0.9 then
      if (public.script_voiceover_settle(v_uid, v_stale.key, v_stale.server_audio_seconds)) ? 'error' then
        update script_voiceovers set status = 'unpaid', settled_at = now()
         where user_id = v_uid and key = v_stale.key;
      end if;
    else
      update script_voiceovers set status = 'expired', settled_at = now()
       where user_id = v_uid and key = v_stale.key;
    end if;
  end loop;

  select count(*) into v_open from script_voiceovers
   where user_id = v_uid and status = 'reserved' and key <> p_key;
  if v_open >= 3 then
    return jsonb_build_object('error', 'too_many_open');
  end if;

  v_wall := public.script_voiceover_wall(v_uid, v_quote);
  if v_wall is not null then
    return jsonb_build_object('error', v_wall);
  end if;

  insert into script_voiceovers (user_id, key, quoted_seconds, max_chars)
  values (v_uid, p_key, v_quote, p_chars)
  on conflict (user_id, key) do update
    set status = 'reserved',
        quoted_seconds = excluded.quoted_seconds,
        max_chars = greatest(script_voiceovers.max_chars, excluded.max_chars),
        -- An expired run being tried again starts a fresh two hours.
        created_at = case when script_voiceovers.status = 'reserved'
                          then script_voiceovers.created_at else now() end,
        chars_used = case when script_voiceovers.status = 'reserved'
                          then script_voiceovers.chars_used else 0 end,
        server_audio_seconds = case when script_voiceovers.status = 'reserved'
                                    then script_voiceovers.server_audio_seconds else 0 end
    where script_voiceovers.status <> 'charged';

  return jsonb_build_object('status', 'reserved', 'quoted_seconds', v_quote);
end;
$$;

-- Step 2a (elevenlabs-tts, service role): may this line be synthesized under
-- the reservation? Counts its characters. A charged key may still claim
-- within the same allowance, so a lost file can be made again once.
create or replace function public.claim_script_voiceover_chars(p_user_id uuid, p_key text,
                                                               p_chars integer)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $$
declare
  v_ok boolean;
begin
  update script_voiceovers
     set chars_used = chars_used + greatest(p_chars, 0)
   where user_id = p_user_id and key = p_key
     and ((status = 'reserved' and created_at > now() - interval '2 hours')
          or status = 'charged')
     and chars_used + greatest(p_chars, 0) <= max_chars * 2 + 500
  returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;

-- Step 2b (elevenlabs-tts, service role): the seconds upstream produced.
create or replace function public.note_script_voiceover_seconds(p_user_id uuid, p_key text,
                                                                p_seconds numeric)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $$
  update script_voiceovers
     set server_audio_seconds = server_audio_seconds + least(greatest(p_seconds, 0), 600)
   where user_id = p_user_id and key = p_key and status in ('reserved', 'charged');
$$;

-- Step 3. After the voiceover was made.
create or replace function public.charge_script_voiceover(p_key text, p_audio_seconds integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_audio_seconds is null or p_audio_seconds < 0 or p_audio_seconds > 3600 then
    raise exception 'bad seconds';
  end if;
  return public.script_voiceover_settle(v_uid, p_key, p_audio_seconds);
end;
$$;

-- The app's question BEFORE it writes a script with "also make it in my
-- voice" on: could this account pay that quote right now? Nothing is held —
-- the reservation is made once the script exists (its key names the text).
create or replace function public.script_voiceover_can_pay(p_quoted_seconds integer)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $$
declare
  v_uid  uuid := auth.uid();
  v_wall text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  v_wall := public.script_voiceover_wall(v_uid, least(3600, greatest(60, coalesce(p_quoted_seconds, 60))));
  if v_wall is null then return jsonb_build_object('ok', true); end if;
  return jsonb_build_object('error', v_wall);
end;
$$;

revoke all on function public.script_voiceover_wall(uuid, integer) from public, anon, authenticated;
revoke all on function public.script_voiceover_settle(uuid, text, numeric) from public, anon, authenticated;
revoke all on function public.claim_script_voiceover_chars(uuid, text, integer) from public, anon, authenticated;
revoke all on function public.note_script_voiceover_seconds(uuid, text, numeric) from public, anon, authenticated;
grant execute on function public.claim_script_voiceover_chars(uuid, text, integer) to service_role;
grant execute on function public.note_script_voiceover_seconds(uuid, text, numeric) to service_role;

revoke all on function public.reserve_script_voiceover(text, integer, integer) from public, anon;
revoke all on function public.charge_script_voiceover(text, integer) from public, anon;
grant execute on function public.reserve_script_voiceover(text, integer, integer) to authenticated;
grant execute on function public.charge_script_voiceover(text, integer) to authenticated;
revoke all on function public.script_voiceover_can_pay(integer) from public, anon;
grant execute on function public.script_voiceover_can_pay(integer) to authenticated;
