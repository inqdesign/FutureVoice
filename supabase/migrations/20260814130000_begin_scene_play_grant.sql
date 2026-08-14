-- ---------------------------------------------------------------------------
-- begin_scene_play was revoked from every client role in 20260814100000 and
-- never granted back, so the very first line of a Watch scene died with
-- "permission denied for function begin_scene_play" and the app surfaced it
-- as an ElevenLabs 500.
--
-- The revoke was modelled on settle_core_club / core_bonus_seconds, which are
-- only ever reached from pg_cron or from inside another SECURITY DEFINER
-- function and therefore need no client grant. begin_scene_play is different:
-- elevenlabs-tts calls it over PostgREST with the client built by
-- requireUser() — anon key + the learner's JWT — so it runs as `authenticated`,
-- exactly like every other charge RPC (charge_tts_pooled,
-- consume_metered_seconds, …), all of which kept PostgreSQL's default PUBLIC
-- execute grant.
--
-- Granting it back brings p_user_id within reach of a caller who could pass
-- somebody else's uuid — burning a stranger's daily scene count — so the
-- function now pins the argument to auth.uid() when there is one. A
-- service_role call (auth.uid() null) is unaffected.
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
  v_uid   uuid := auth.uid();
begin
  if p_scene_key is null or length(p_scene_key) = 0 then
    raise exception 'p_scene_key required';
  end if;

  -- A logged-in caller may only claim scenes for themselves. auth.uid() is
  -- null for service_role and for calls nested inside other definer
  -- functions, which stay trusted.
  if v_uid is not null and v_uid <> p_user_id then
    raise exception 'not your account' using errcode = '42501';
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

revoke all on function public.begin_scene_play(uuid, text) from public, anon;
grant execute on function public.begin_scene_play(uuid, text) to authenticated, service_role;
