-- A FREE account's Watch scene costs five minutes of its free talk time,
-- like a subscriber's (founder, 2026-11-16: "무료 1개 이런 거 없이 무조건
-- 통화시간에서"). Replaces the one free sample scene of 20261019120000,
-- which met a learner with all 20 free minutes still in hand with the plans
-- on their second scene, with nothing on screen saying why.
--
--   * No plan: every NEW scene takes 300 s off `user_credits.balance` at the
--     claim (`charge_credits`, ledger action `scene_play`); lines after it
--     ride free (`scene_paid`), replays stay free. Under 300 s left, the
--     claim raises FREE_SCENE_CAP, which the `tts` edge function already
--     answers with the paywall (402 insufficient_credits). No edge deploy.
--   * Every build is charged this way, old ones included: the old free
--     sample is gone either way, and `scene_allowance` returns `free_cap`
--     null so no build gates a tap on it.
--   * Subscribers are untouched (count or minutes, as before).

CREATE OR REPLACE FUNCTION public.begin_scene_play(p_user_id uuid, p_scene_key text, p_talk boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cap        integer;
  v_talk_secs  integer;
  v_used       integer;
  v_start      date;
  v_fresh      boolean;
  v_unlimited  boolean;
  v_kept       boolean;
  v_balance    integer;
  c_scene_secs constant integer := 300;
begin
  if p_user_id is null or coalesce(p_scene_key, '') = '' then
    raise exception 'begin_scene_play: user and scene key required';
  end if;

  select case when s.status = 'trialing'
              then coalesce(s.monthly_scenes,
                            (select min(monthly_scenes) from subscription_plans
                              where tier = 'light'), p.monthly_scenes) * 7 / 30
              else coalesce(s.monthly_scenes, p.monthly_scenes) end,
         p.scene_talk_seconds
    into v_cap, v_talk_secs
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  -- Is this scene already one of theirs (any day)? Then it is never cut off
  -- and never charged again.
  v_fresh := not exists (
    select 1 from scene_plays
     where user_id = p_user_id and scene_key = p_scene_key);

  -- No entitlement: a scene costs FIVE MINUTES of the free talk minutes,
  -- like a subscriber's (2026-11-16). No free sample any more.
  if v_cap is null then
    select coalesce(c.unlimited, false), coalesce(c.balance, 0)
      into v_unlimited, v_balance
      from user_credits c where c.user_id = p_user_id;
    if coalesce(v_unlimited, false) then
      return jsonb_build_object('allowed', true, 'metered_by', 'balance',
                                'counted', false);
    end if;

    if v_fresh then
      -- Not a whole scene's worth left: the plans (the edge function answers
      -- FREE_SCENE_CAP with the paywall). Checked here, not left to
      -- charge_credits, whose INSUFFICIENT_CREDITS the edge reads as a 500.
      if coalesce(v_balance, 0) < c_scene_secs then
        raise exception 'FREE_SCENE_CAP' using errcode = 'P0007';
      end if;
      perform public.charge_credits(
        p_user_id         => p_user_id,
        p_credits         => c_scene_secs,
        p_action          => 'scene_play',
        p_source_fn       => 'begin_scene_play',
        p_idempotency_key => 'scene_play:' || p_user_id::text || ':' || p_scene_key,
        p_metadata        => jsonb_build_object('scene_key', p_scene_key,
                                                'scene_talk_seconds', c_scene_secs,
                                                'seconds', c_scene_secs,
                                                'pool', 'talk_seconds',
                                                'covered_by', 'balance'));
    end if;

    insert into scene_plays (user_id, day, scene_key)
    values (p_user_id, current_date, p_scene_key)
    on conflict do nothing;

    return jsonb_build_object('allowed', true, 'metered_by', 'talk',
                              'counted', false, 'paid', true,
                              'seconds', c_scene_secs, 'fresh', v_fresh);
  end if;

  v_kept := exists (select 1 from scene_count_billing where user_id = p_user_id);

  -- Five minutes of talk time, once per scene.
  if p_talk and not v_kept and v_talk_secs is not null then
    insert into scene_plays (user_id, day, scene_key)
    values (p_user_id, current_date, p_scene_key)
    on conflict do nothing;
    if v_fresh then
      -- Invite minutes and packs pay first, exactly like talking. When they
      -- hold less than a whole scene, they pay what they have and the plan
      -- the rest: the app shows ONE "minutes left" figure (plan + extra),
      -- and a scene that figure says fits must not be refused because the
      -- meter would only take it whole from one side.
      -- DAILY_CAP_REACHED (the month's minutes, or the trial's) raises out
      -- of here and rolls the whole claim back, both charges included.
      select coalesce(balance, 0) into v_balance from user_credits where user_id = p_user_id;
      if v_balance > 0 and v_balance < v_talk_secs then
        perform public.consume_metered_seconds(
          p_user_id         => p_user_id,
          p_seconds         => v_balance,
          p_pool            => 'talk_seconds',
          p_action          => 'scene_play',
          p_source_fn       => 'begin_scene_play',
          p_idempotency_key => 'scene_play:' || p_user_id::text || ':' || p_scene_key || ':extra',
          p_metadata        => jsonb_build_object('scene_key', p_scene_key,
                                                  'scene_talk_seconds', v_talk_secs));
        perform public.consume_metered_seconds(
          p_user_id         => p_user_id,
          p_seconds         => v_talk_secs - v_balance,
          p_pool            => 'talk_seconds',
          p_action          => 'scene_play',
          p_source_fn       => 'begin_scene_play',
          p_idempotency_key => 'scene_play:' || p_user_id::text || ':' || p_scene_key,
          p_metadata        => jsonb_build_object('scene_key', p_scene_key,
                                                  'scene_talk_seconds', v_talk_secs));
      else
        perform public.consume_metered_seconds(
          p_user_id         => p_user_id,
          p_seconds         => v_talk_secs,
          p_pool            => 'talk_seconds',
          p_action          => 'scene_play',
          p_source_fn       => 'begin_scene_play',
          p_idempotency_key => 'scene_play:' || p_user_id::text || ':' || p_scene_key,
          p_metadata        => jsonb_build_object('scene_key', p_scene_key,
                                                  'scene_talk_seconds', v_talk_secs));
      end if;
    end if;
    return jsonb_build_object('allowed', true, 'metered_by', 'talk',
                              'counted', false, 'paid', true,
                              'seconds', v_talk_secs, 'fresh', v_fresh);
  end if;

  -- The count, unchanged: accounts kept on it, and builds that don't know
  -- the minutes.
  insert into scene_plays (user_id, day, scene_key)
  values (p_user_id, current_date, p_scene_key)
  on conflict do nothing;
  v_fresh := found;

  v_start := public.billing_period_start(p_user_id);
  select count(*) into v_used
    from scene_plays
   where user_id = p_user_id
     and created_at >= public.billing_period_started_at(p_user_id);

  if v_fresh and v_used > v_cap then
    raise exception 'SCENE_CAP_REACHED' using errcode = 'P0006';
  end if;

  return jsonb_build_object('allowed', true, 'metered_by', 'scenes',
                            'counted', true,
                            'used', v_used, 'cap', v_cap, 'fresh', v_fresh);
end;
$function$;

CREATE OR REPLACE FUNCTION public.scene_allowance()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_cap   integer;
  v_used  integer;
  v_start date;
  v_end   date;
  v_unlimited boolean;
  v_talk_secs integer;
  v_kept  boolean;
  v_billing text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_kept := exists (select 1 from scene_count_billing where user_id = v_uid);

  select case when s.status = 'trialing'
              then coalesce(s.monthly_scenes,
                            (select min(monthly_scenes) from subscription_plans
                              where tier = 'light'), p.monthly_scenes) * 7 / 30
              else coalesce(s.monthly_scenes, p.monthly_scenes) end,
         public.billing_period_ends_at(v_uid)::date,
         p.scene_talk_seconds
    into v_cap, v_end, v_talk_secs
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid
     and s.status in ('trialing', 'active', 'grace')
   order by s.current_period_start desc nulls last
   limit 1;

  if v_cap is null then
    -- With no plan a scene is five minutes of the free talk minutes, always
    -- (2026-11-16). `free_cap` is null, so no build gates on a free sample.
    select coalesce(c.unlimited, false) into v_unlimited
      from user_credits c where c.user_id = v_uid;
    select count(distinct scene_key) into v_used
      from scene_plays where user_id = v_uid;
    return jsonb_build_object('used', 0, 'cap', null, 'period_start', null,
                              'period_end', null, 'metered_by', 'balance',
                              'free_used', v_used,
                              'free_cap', null,
                              'scene_billing', 'talk',
                              'scene_talk_seconds',
                                case when coalesce(v_unlimited, false) then null else 300 end);
  end if;

  v_billing := case when v_kept or v_talk_secs is null then 'count' else 'talk' end;
  v_start := public.billing_period_start(v_uid);
  select count(*) into v_used from scene_plays
   where user_id = v_uid
     and created_at >= public.billing_period_started_at(v_uid);

  return jsonb_build_object('used', v_used, 'cap', v_cap,
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'scenes',
                            'scene_billing', v_billing,
                            'scene_talk_seconds',
                              case when v_billing = 'talk' then v_talk_secs end);
end;
$function$;
