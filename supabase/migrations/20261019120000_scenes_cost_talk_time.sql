-- A Watch scene costs FIVE MINUTES of talk time, for everyone who subscribes
-- from today (founder decision, 2026-10-19).
--
-- Why: a scene is ~930 characters of synthesis (measured over the last 14
-- days: 46,615 chars for 50 scenes), and a talk minute carries ~300. So a
-- scene costs about three talk minutes upstream, and a separate scene COUNT
-- made every plan's "fully used" arithmetic a sum of two pools. Charged at
-- five minutes (above that cost, below the 3x the Speech voiceover is sold
-- at), any mix of talking and watching costs at most what the same minutes
-- all spent talking would, so a plan's margin is the talk minute's alone. It
-- is one pool, the one the learner already reads ("150 min"), in one unit.
--
-- Who it applies to, and who it does NOT:
--   * Every account that has EVER had a subscription row is left exactly as
--     it is, count and all (`scene_count_billing`, backfilled below: 37
--     accounts on 2026-10-19). The founder will ask them first; moving one is
--     `delete from scene_count_billing where user_id = ...`.
--   * An account with no plan gets ONE free sample scene, ever, and it takes
--     nothing off the free talk minutes (was two scenes, each also charged
--     ~40-65 s of the free pool by characters). Accounts already past one
--     scene are not given another.
--   * Everyone else who subscribes, a free account today included, pays five
--     minutes per scene out of the plan's talk pool (invite minutes and packs
--     first, exactly like talking).
--
-- Only a build that says it understands is charged in minutes:
-- `begin_scene_play(..., p_talk => true)`, which the edge function passes
-- when the app sends `scene_billing: "talk"`. A build already in the store
-- shows "10 scenes a month", so it keeps getting the plan's count: the
-- server must never charge in a unit the screen in front of the learner
-- doesn't name. A new account on an old build watches by count until it
-- updates, which is harmless.
--
-- A scene is charged ONCE, on the line that starts it (the claim), and every
-- line after it rides free (`charge_tts_pooled(p_pool => 'scene_paid')`,
-- which writes the line's characters to the ledger for cost measurement and
-- spends nothing). A scene whose script failed to write never reaches a line,
-- so it is never charged. A spent pool refuses the scene with the talk
-- meter's own DAILY_CAP_REACHED -> the spent-pool sheet, never a paywall.
--
-- DEPLOY ORDER: this migration first (the edge function will pass `p_talk`
-- and `scene_paid`, which nothing before this accepts), then the `tts` edge
-- function, then the app build.

-- 1. The accounts kept on the count.
create table if not exists public.scene_count_billing (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  added_at   timestamptz not null default now(),
  note       text
);
alter table public.scene_count_billing enable row level security;
revoke all on public.scene_count_billing from public, anon, authenticated;

insert into public.scene_count_billing (user_id, note)
select distinct s.user_id, 'had a subscription row on 2026-10-19'
  from public.user_subscriptions s
on conflict do nothing;

-- 2. What a scene costs, per plan. NULL = this plan meters scenes by count.
alter table public.subscription_plans
  add column if not exists scene_talk_seconds integer;
update public.subscription_plans set scene_talk_seconds = 300;

-- 3. The line meter learns a pool that spends nothing.
CREATE OR REPLACE FUNCTION public.charge_tts_pooled(p_user_id uuid, p_chars integer, p_action text, p_source_fn text, p_idempotency_key text, p_metadata jsonb DEFAULT NULL::jsonb, p_pool text DEFAULT 'scene_seconds'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_old      bigint;
  v_new      bigint;
  v_secs_due integer;
begin
  if p_chars <= 0 then raise exception 'p_chars must be > 0'; end if;
  if p_action not in ('tts', 'tts_timestamps', 'tts_scene') then
    raise exception 'unsupported pooled action %', p_action;
  end if;
  if p_pool not in ('scene_seconds', 'scene_counted', 'scene_paid') then
    raise exception 'unsupported pool %', p_pool;
  end if;

  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    if p_pool = 'scene_paid' then
      return jsonb_build_object('charged', 0, 'balance', -1);
    end if;
    return public.consume_metered_seconds(
      p_user_id => p_user_id, p_seconds => 0, p_pool => p_pool,
      p_action => p_action, p_source_fn => p_source_fn,
      p_idempotency_key => p_idempotency_key, p_metadata => p_metadata);
  end if;

  -- A line of a scene that was already paid for at its claim (five minutes,
  -- or the free sample). Recorded so the cost views still see its
  -- characters; nothing is spent, and `consume_metered_seconds` is not
  -- called: its step 1 would otherwise take invite minutes for the line.
  if p_pool = 'scene_paid' then
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('pool', 'scene_paid', 'covered_by', 'scene_claim',
                                    'seconds', 0));
    return jsonb_build_object('charged', 0, 'balance', -1, 'covered_by', 'scene_claim');
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
$function$;

-- 4. The claim. Replaces the two-argument version: `create or replace` with
-- a new argument would leave both, and a call naming two arguments would
-- then be ambiguous ("is not unique" -> a 500 on every scene line).
drop function if exists public.begin_scene_play(uuid, text);

CREATE OR REPLACE FUNCTION public.begin_scene_play(p_user_id uuid, p_scene_key text,
                                                   p_talk boolean DEFAULT false)
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
  v_free_cap   constant integer := 1;
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

  -- No entitlement: one free sample scene, ever, and it costs no minutes.
  if v_cap is null then
    select coalesce(c.unlimited, false) into v_unlimited
      from user_credits c where c.user_id = p_user_id;
    if coalesce(v_unlimited, false) then
      return jsonb_build_object('allowed', true, 'metered_by', 'balance',
                                'counted', false);
    end if;

    if v_fresh then
      select count(distinct scene_key) into v_used
        from scene_plays where user_id = p_user_id;
      if v_used >= v_free_cap then
        raise exception 'FREE_SCENE_CAP' using errcode = 'P0007';
      end if;
    end if;

    insert into scene_plays (user_id, day, scene_key)
    values (p_user_id, current_date, p_scene_key)
    on conflict do nothing;

    return jsonb_build_object('allowed', true, 'metered_by', 'free_sample',
                              'counted', false, 'paid', true);
  end if;

  v_kept := exists (select 1 from scene_count_billing where user_id = p_user_id);

  -- Five minutes of talk time, once per scene.
  if p_talk and not v_kept and v_talk_secs is not null then
    insert into scene_plays (user_id, day, scene_key)
    values (p_user_id, current_date, p_scene_key)
    on conflict do nothing;
    if v_fresh then
      -- DAILY_CAP_REACHED (the month's minutes, or the trial's) raises out
      -- of here and rolls the claim back with it.
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

revoke all on function public.begin_scene_play(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.begin_scene_play(uuid, text, boolean) to service_role;

-- 5. What the app reads. Every field an older build reads keeps its meaning
-- (an old build is charged by count, so it must keep seeing the count).
-- Two new fields, read only by a build that sends `scene_billing: "talk"`:
--   scene_billing       'talk' | 'count': how THIS account's scenes are
--                       charged, or, with no plan, how they WOULD be after a
--                       purchase (the paywall draws its card from it)
--   scene_talk_seconds  what one scene costs in talk time when 'talk'
-- `free_cap` is 1 now.
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
    -- With no plan: what a purchase would bring, from the catalog.
    select max(scene_talk_seconds) into v_talk_secs
      from subscription_plans where is_active;
    v_billing := case when v_kept or v_talk_secs is null then 'count' else 'talk' end;
    select coalesce(c.unlimited, false) into v_unlimited
      from user_credits c where c.user_id = v_uid;
    select count(distinct scene_key) into v_used
      from scene_plays where user_id = v_uid;
    return jsonb_build_object('used', 0, 'cap', null, 'period_start', null,
                              'period_end', null, 'metered_by', 'balance',
                              'free_used', v_used,
                              'free_cap', case when coalesce(v_unlimited, false)
                                               then null else 1 end,
                              'scene_billing', v_billing,
                              'scene_talk_seconds',
                                case when v_billing = 'talk' then v_talk_secs end);
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
