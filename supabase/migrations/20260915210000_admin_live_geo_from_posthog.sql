-- ---------------------------------------------------------------------------
-- Location comes from PostHog, not from a table of our own.
--
-- 20260915200000 added `user_geo`, written by the gateway from Cloudflare's
-- view of a call's IP. The gateway change was never deployed: PostHog already
-- attaches a GeoIP city to every app event (the iOS SDK's default), and it
-- covers everyone who opens the app, not only people who call. Keeping a
-- second copy of the same fact would be collection for its own sake.
--
-- The admin Worker now reads city + app-open state from PostHog and merges it
-- onto admin_live(), whose `placed` becomes the plain user directory the page
-- needs to name those dots.
-- ---------------------------------------------------------------------------

drop function if exists public.admin_live();
drop table if exists public.user_geo;

create or replace function public.admin_live()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
with act as (
  select l.user_id, l.created_at as at,
         l.action, l.metadata->>'purpose' as purpose,
         l.metadata->>'language' as language,
         coalesce((l.metadata->>'seconds')::int, 0) as secs
    from public.usage_ledger l
   where l.created_at > now() - interval '24 hours'
     and l.user_id is not null
     and l.source_fn is distinct from 'migration'
  union all
  select e.user_id, e.created_at, 'event:' || e.event, null,
         e.properties->>'language', 0
    from public.client_events e
   where e.created_at > now() - interval '24 hours'
     and e.user_id is not null
),
people as (
  select user_id,
         max(at) as last_at,
         min(at) filter (where at > now() - interval '30 minutes') as stint_from,
         sum(secs) filter (where action = 'talk_time') as talk_secs_24h
    from act group by user_id
)
select jsonb_build_object(
  'now', now(),
  'users', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.user_id,
      'email', u.email,
      'name', pp.display_name,
      'target', pr.target_language,
      'native', pr.native_language,
      'plan', s.plan_id,
      'sub', s.status,
      'last_at', p.last_at,
      'stint_from', p.stint_from,
      'talk_secs_24h', coalesce(p.talk_secs_24h, 0),
      'recent', (select coalesce(jsonb_agg(jsonb_build_object(
                          'at', r.at, 'action', r.action, 'purpose', r.purpose,
                          'language', r.language) order by r.at desc), '[]'::jsonb)
                   from (select * from act a
                          where a.user_id = p.user_id
                          order by a.at desc limit 12) r)
    ) order by p.last_at desc)
    from people p
    join auth.users u on u.id = p.user_id
    left join public.profiles pr on pr.id = p.user_id
    left join public.user_subscriptions s on s.user_id = p.user_id
    left join lateral (select x.display_name from public.public_personas x
                        where x.owner_user_id = p.user_id and x.is_active
                        order by x.updated_at desc limit 1) pp on true
  ), '[]'::jsonb),
  -- Everyone else, as a directory: PostHog knows where and whether the app is
  -- open for people who asked the server for nothing today, and the page
  -- needs a name to put on that dot.
  'placed', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', u.id, 'email', u.email, 'name', pp.display_name,
      'target', pr.target_language))
      from auth.users u
      left join public.profiles pr on pr.id = u.id
      left join lateral (select x.display_name from public.public_personas x
                          where x.owner_user_id = u.id and x.is_active
                          order by x.updated_at desc limit 1) pp on true
     where not exists (select 1 from people p where p.user_id = u.id)
  ), '[]'::jsonb)
);
$$;

revoke all on function public.admin_live() from public, anon, authenticated;
grant execute on function public.admin_live() to service_role;
