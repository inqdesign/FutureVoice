-- A free account gets TWO Watch scenes, ever (founder decision, 2026-09-28).
--
-- Until now an account with no plan had no scene count at all: every line was
-- priced in seconds out of `user_credits.balance`, the same 1,200 free seconds
-- the first calls spend. At ~0.07 s per character a scene is ~40–65 s of that
-- pool, so a free account that only watched could play 18–30 scenes — more
-- than Light (10/month) or Plus (30/month) sells, on the tier that pays
-- nothing, and at ~$0.07–0.12 of upstream cost each.
--
-- Two scenes is a sample, not a pool: enough to see what Watch is, and the
-- third is the plans. The count is LIFETIME, because the free balance it sits
-- beside is one-time too; a lapsed subscriber who comes back with invite
-- minutes has already had their scenes. Seconds are still charged from the
-- balance exactly as before (`metered_by: 'balance'`, `counted: false`) — the
-- count is an additional ceiling, not a replacement meter.
--
-- The refusal is its own exception (FREE_SCENE_CAP) which `elevenlabs-tts`
-- answers with the insufficient_credits 402 — the free account's wall is the
-- paywall, never the subscriber's spent-pool sheet. DEPLOY ORDER: the edge
-- function first (it must know the new message, or the refusal is a 500),
-- then this migration.
--
-- Distinct scene_key, not rows: `scene_plays` is keyed (user, day, key), so a
-- scene that plays across midnight writes two rows for one scene.

CREATE OR REPLACE FUNCTION public.begin_scene_play(p_user_id uuid, p_scene_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cap        integer;
  v_used       integer;
  v_start      date;
  v_fresh      boolean;
  v_unlimited  boolean;
  v_free_cap   constant integer := 2;
begin
  if p_user_id is null or coalesce(p_scene_key, '') = '' then
    raise exception 'begin_scene_play: user and scene key required';
  end if;

  select case when s.status = 'trialing'
              then coalesce(s.monthly_scenes,
                            (select min(monthly_scenes) from subscription_plans
                              where tier = 'light'), p.monthly_scenes) * 7 / 30
              else coalesce(s.monthly_scenes, p.monthly_scenes) end
    into v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  -- No entitlement: seconds still come out of the balance (the caller must
  -- not claim a count), and the account has two scenes in all.
  if v_cap is null then
    select coalesce(c.unlimited, false) into v_unlimited
      from user_credits c where c.user_id = p_user_id;
    if coalesce(v_unlimited, false) then
      return jsonb_build_object('allowed', true, 'metered_by', 'balance',
                                'counted', false);
    end if;

    -- Is this scene already one of theirs? Then it is never cut off.
    v_fresh := not exists (
      select 1 from scene_plays
       where user_id = p_user_id and scene_key = p_scene_key);

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

    return jsonb_build_object('allowed', true, 'metered_by', 'balance',
                              'counted', false);
  end if;

  insert into scene_plays (user_id, day, scene_key)
  values (p_user_id, current_date, p_scene_key)
  on conflict do nothing;
  v_fresh := found;

  v_start := public.billing_period_start(p_user_id);
  select count(*) into v_used
    from scene_plays
   where user_id = p_user_id and day >= v_start;

  -- Only a NEWLY claimed slot can push past the cap; a line from a scene
  -- already in progress must never be cut off half way through.
  if v_fresh and v_used > v_cap then
    raise exception 'SCENE_CAP_REACHED' using errcode = 'P0006';
  end if;

  return jsonb_build_object('allowed', true, 'metered_by', 'scenes',
                            'counted', true,
                            'used', v_used, 'cap', v_cap, 'fresh', v_fresh);
end;
$function$;

revoke all on function public.begin_scene_play(uuid, text) from public, anon, authenticated;
grant execute on function public.begin_scene_play(uuid, text) to service_role;

-- What the app reads before a scene starts. A free account's answer keeps
-- `cap: null` (every shipped build reads a non-null cap as a PLAN's pool and
-- would draw "N of 2 this month") and adds `free_used` / `free_cap`, which
-- only a build that knows them reads.
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
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select case when s.status = 'trialing'
              then coalesce(s.monthly_scenes,
                            (select min(monthly_scenes) from subscription_plans
                              where tier = 'light'), p.monthly_scenes) * 7 / 30
              else coalesce(s.monthly_scenes, p.monthly_scenes) end,
         s.current_period_end::date
    into v_cap, v_end
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid
     and s.status in ('trialing', 'active', 'grace')
   order by s.current_period_start desc nulls last
   limit 1;

  if v_cap is null then
    select coalesce(c.unlimited, false) into v_unlimited
      from user_credits c where c.user_id = v_uid;
    select count(distinct scene_key) into v_used
      from scene_plays where user_id = v_uid;
    return jsonb_build_object('used', 0, 'cap', null, 'period_start', null,
                              'period_end', null, 'metered_by', 'balance',
                              'free_used', v_used,
                              'free_cap', case when coalesce(v_unlimited, false)
                                               then null else 2 end);
  end if;

  v_start := public.billing_period_start(v_uid);
  select count(*) into v_used from scene_plays
   where user_id = v_uid and day >= v_start;

  return jsonb_build_object('used', v_used, 'cap', v_cap,
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'scenes');
end;
$function$;
