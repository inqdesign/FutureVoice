-- Watch stops eating talk minutes.
--
-- WHY. Since the minutes pivot, talk seconds and Watch-scene seconds have
-- shared ONE daily pool against `subscription_plans.daily_seconds`. Real
-- usage says that is wrong: the one active Daily subscriber on 2026-08-13
-- spent 101/164/95 s a day on scenes — around a fifth of a 300 s allowance —
-- so someone who uses Watch as intended buys "5 minutes of talk" and gets
-- three. Worse, the erosion is invisible: nothing on screen says a scene
-- just took a minute off the call you were going to make. That is exactly
-- the taximeter-on-exploration mistake the minutes model was created to
-- delete (docs/launch-billing.md, 2026-08-11 revision) — it simply grew back
-- inside the new unit.
--
-- WHAT CHANGES. Talk is metered in seconds, alone, against `daily_seconds`.
-- Watch is metered by COUNT of scenes per day against a new
-- `subscription_plans.daily_scenes`. A count is also the honest unit for the
-- UI: "2 of today's scenes left" can be shown, whereas seconds quietly
-- draining behind a screen cannot.
--
-- WHY A COUNT AND NOT A BIGGER SECONDS POOL. Scene audio is synthesized with
-- `fidelityModelId` (eleven_multilingual_v2), which bills ~2x per character
-- upstream while our own price table is model-blind — so a scene second
-- costs us roughly twice a talk second. The shared pool was accidentally
-- acting as the cost ceiling for a Daily subscriber; removing it without a
-- replacement bound would put a heavy user above the €7.10 net the plan
-- earns. Two scenes a day matches observed behaviour and keeps the bound.
--
-- REPLAYS STAY FREE, FOR FREE. Scene lines are cached client-side in
-- `PhraseAudioStore` keyed by (voiceId, text), so replaying a scene makes no
-- request at all and therefore cannot consume a count. Nothing here had to
-- special-case that — it falls out of counting only what reaches the server,
-- and it keeps the standing promise that anything already generated replays
-- forever.
--
-- BACKWARD COMPATIBILITY. Deployed clients do not send a scene key. Those
-- requests keep the OLD behaviour exactly (scene seconds counted against
-- `daily_seconds`) by staying on the `scene_seconds` pool; only a request
-- that successfully registered a scene play moves to the new
-- `scene_counted` pool, which the cap ignores. So an un-updated app is
-- metered as it is today and can never get unlimited free scenes.

-- ---------------------------------------------------------------------------
-- 1) The allowance. Unlimited gets a fair-use number rather than infinity,
--    mirroring how its 3600 s/day talk ceiling is a fair-use bound with no
--    meter in the UI.
-- ---------------------------------------------------------------------------

alter table public.subscription_plans
  add column if not exists daily_scenes integer;

-- `tier` is the `subscription_tier` ENUM, and 20260811170000 renamed its
-- values — 'pro'/'premium' no longer parse, so there are no legacy rows to
-- defend against here.
update public.subscription_plans set daily_scenes = 2  where tier = 'daily';
update public.subscription_plans set daily_scenes = 20 where tier = 'unlimited';

-- ---------------------------------------------------------------------------
-- 2) One row per scene a user actually made the server synthesize today.
--    The key is supplied by the client and is stable across every line of
--    one scene, so a ten-line scene counts once.
-- ---------------------------------------------------------------------------

create table if not exists public.scene_plays (
  user_id    uuid not null references auth.users(id) on delete cascade,
  day        date not null,
  scene_key  text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, day, scene_key)
);

alter table public.scene_plays enable row level security;

-- Own rows only, so the app can show "1 of 2 scenes today". Writes are
-- SECURITY DEFINER territory.
drop policy if exists "scene_plays: read own" on public.scene_plays;
create policy "scene_plays: read own" on public.scene_plays
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 3) Register a scene play. Called once per TTS line; the first line of a
--    scene claims the day's slot and every later line finds it already
--    claimed, so a scene costs exactly one count however many lines it has.
-- ---------------------------------------------------------------------------

create or replace function public.begin_scene_play(
  p_user_id uuid,
  p_scene_key text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cap   integer;
  v_used  integer;
  v_fresh boolean := false;
begin
  if p_scene_key is null or length(p_scene_key) = 0 then
    raise exception 'p_scene_key required';
  end if;

  -- A TRIAL gets the Daily tier's scene allowance whatever plan it trials,
  -- for the same reason its talk is metered at the Daily rate: a 7-day
  -- trial of Unlimited must not hand out Unlimited's volume.
  select case when s.status = 'trialing'
              then coalesce((select min(daily_scenes) from subscription_plans
                              where tier = 'daily'), p.daily_scenes)
              else p.daily_scenes end
    into v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  -- No entitlement: there is no plan to draw a count from, so scenes stay
  -- priced in seconds out of the balance exactly as before.
  if v_cap is null then
    return jsonb_build_object('allowed', true, 'metered_by', 'balance');
  end if;

  insert into scene_plays (user_id, day, scene_key)
  values (p_user_id, current_date, p_scene_key)
  on conflict do nothing;
  v_fresh := found;

  select count(*) into v_used
    from scene_plays
   where user_id = p_user_id and day = current_date;

  -- Only a NEWLY claimed slot can push past the cap; a line from a scene
  -- already in progress must never be cut off half way through.
  if v_fresh and v_used > v_cap then
    raise exception 'SCENE_CAP_REACHED' using errcode = 'P0006';
  end if;

  return jsonb_build_object('allowed', true, 'metered_by', 'scenes',
                            'used', v_used, 'cap', v_cap, 'fresh', v_fresh);
end;
$$;

revoke all on function public.begin_scene_play(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) Metering. Restated from 20260813120000 with two changes:
--      * a new 'scene_counted' pool, which accumulates for attribution but
--        is EXCLUDED from the daily-seconds cap (it was already counted as
--        one scene by begin_scene_play);
--      * the returned payload separates talk from scene seconds, so the app
--        can stop showing a talk allowance that Watch silently drained.
--    Everything else — trial metering, the Core bonus, the hard paywall
--    fall-through — is unchanged.
-- ---------------------------------------------------------------------------

create or replace function public.consume_metered_seconds(
  p_user_id uuid,
  p_seconds integer,
  p_pool text,                  -- 'talk_seconds' | 'scene_seconds' | 'scene_counted'
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
  v_today   bigint;
  v_scenes  bigint;
  v_cap     integer;
  v_bonus   integer := 0;
  v_trial   boolean := false;
  v_balance integer;
begin
  if p_seconds < 0 or p_seconds > 3600 then
    raise exception 'p_seconds out of range';
  end if;
  if p_pool not in ('talk_seconds', 'scene_seconds', 'scene_counted') then
    raise exception 'unsupported pool %', p_pool;
  end if;

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

  -- The capped meter. 'scene_counted' is deliberately absent: those seconds
  -- were paid for with a scene count. 'scene_seconds' stays in so that an
  -- un-updated client keeps today's economics.
  select coalesce(sum(chars), 0) into v_today from tts_char_pool
   where user_id = p_user_id and day = current_date
     and action in ('talk_seconds', 'scene_seconds');

  select coalesce(sum(chars), 0) into v_scenes from tts_char_pool
   where user_id = p_user_id and day = current_date
     and action in ('scene_seconds', 'scene_counted');

  select s.status = 'trialing',
         case when s.status = 'trialing'
              then coalesce((select min(daily_seconds) from subscription_plans
                              where tier = 'daily'), p.daily_seconds)
              else p.daily_seconds end
    into v_trial, v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  if v_cap is not null then
    v_bonus := public.core_bonus_seconds(p_user_id);
    v_cap := v_cap + v_bonus;

    if v_today > v_cap then
      raise exception 'DAILY_CAP_REACHED' using errcode = 'P0005';
    end if;
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                                    'scene_seconds_today', v_scenes,
                                    'core_bonus', v_bonus, 'pool', p_pool,
                                    'covered_by', case when v_trial then 'trial' else 'plan' end));
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today, 'daily_cap', v_cap,
                              'scene_seconds_today', v_scenes,
                              'core_bonus', v_bonus,
                              'covered_by', case when v_trial then 'trial' else 'plan' end);
  end if;

  v_balance := public.charge_credits(
    p_user_id => p_user_id,
    p_credits => p_seconds,
    p_action  => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                            'pool', p_pool, 'covered_by', 'balance'));
  return jsonb_build_object('balance', v_balance, 'charged', p_seconds,
                            'seconds_today', v_today,
                            'scene_seconds_today', v_scenes,
                            'covered_by', 'balance');
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) charge_tts_pooled gains a pool argument so the edge function can say
--    "this scene was already counted". Defaulted, so every existing caller
--    and every deployed edge function keeps working unchanged.
-- ---------------------------------------------------------------------------

create or replace function public.charge_tts_pooled(
  p_user_id uuid,
  p_chars integer,
  p_action text,
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null,
  p_pool text default 'scene_seconds'
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
  if p_pool not in ('scene_seconds', 'scene_counted') then
    raise exception 'unsupported pool %', p_pool;
  end if;

  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    return public.consume_metered_seconds(
      p_user_id => p_user_id, p_seconds => 0, p_pool => p_pool,
      p_action => p_action, p_source_fn => p_source_fn,
      p_idempotency_key => p_idempotency_key, p_metadata => p_metadata);
  end if;

  insert into tts_char_pool (user_id, day, action, chars)
  values (p_user_id, current_date, p_action, p_chars)
  on conflict (user_id, day, action) do update
    set chars = tts_char_pool.chars + excluded.chars,
        updated_at = now()
  returning chars - p_chars, chars into v_old, v_new;

  v_secs_due := ((v_new * 706 + 9999) / 10000) - ((v_old * 706 + 9999) / 10000);

  return public.consume_metered_seconds(
    p_user_id => p_user_id,
    p_seconds => v_secs_due,
    p_pool    => p_pool,
    p_action  => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('chars_today', v_new));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) How much of today's Watch allowance is left. Read by the app to show
--    the count before a scene starts, so the limit is never a surprise
--    delivered mid-playback.
-- ---------------------------------------------------------------------------

create or replace function public.scene_allowance()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_cap  integer;
  v_used integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select case when s.status = 'trialing'
              then coalesce((select min(daily_scenes) from subscription_plans
                              where tier = 'daily'), p.daily_scenes)
              else p.daily_scenes end
    into v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid
     and s.status in ('trialing', 'active', 'grace');

  select count(*) into v_used
    from scene_plays
   where user_id = v_uid and day = current_date;

  return jsonb_build_object('used', coalesce(v_used, 0), 'cap', v_cap,
                            'metered_by', case when v_cap is null
                                               then 'balance' else 'scenes' end);
end;
$$;

grant execute on function public.scene_allowance() to authenticated;
