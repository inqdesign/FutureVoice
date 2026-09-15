-- ---------------------------------------------------------------------------
-- Where learners are, and what they are doing right now — for the admin
-- console's 라이브 tab.
--
-- `user_geo` is ONE row per learner: the city Cloudflare resolves from the
-- connecting IP when they open a realtime call (gateway/src/session.ts). The IP
-- itself is never stored, coordinates are rounded to 0.1° (~10 km), and each
-- call overwrites the previous row — there is no location history, only
-- "last seen near". Disclosed in web/privacy*.html alongside this change.
--
-- Only a call writes it, so a learner who has never talked since this shipped
-- has no row; the page lists them as 위치 모름 instead of guessing.
--
-- `admin_live()` returns everyone with server activity in the last 24 h and
-- their last few actions. "Activity" is usage_ledger (every request the app
-- makes on a learner's behalf, including the gateway's 15 s talk ticks) plus
-- client_events — the same floor `admin_raw`'s hours use: a review done with
-- no server call is invisible here too.
-- ---------------------------------------------------------------------------

create table if not exists public.user_geo (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  city       text,
  region     text,
  country    text,
  lat        numeric(5,1),
  lon        numeric(5,1),
  timezone   text,
  seen_at    timestamptz not null default now()
);

alter table public.user_geo enable row level security;
-- No policies: the gateway writes with the service role, the admin reads
-- through admin_live(). No client can see or write a row.
revoke all on public.user_geo from anon, authenticated;

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
      'geo', case when g.user_id is null then null else jsonb_build_object(
               'city', g.city, 'region', g.region, 'country', g.country,
               'lat', g.lat, 'lon', g.lon, 'tz', g.timezone, 'at', g.seen_at) end,
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
    left join public.user_geo g on g.user_id = p.user_id
    left join lateral (select x.display_name from public.public_personas x
                        where x.owner_user_id = p.user_id and x.is_active
                        order by x.updated_at desc limit 1) pp on true
  ), '[]'::jsonb),
  -- Located learners who were NOT active in the last 24 h: the map's quiet
  -- dots, so the world reads as "where people are", not only "who is on".
  'placed', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g.user_id, 'email', u.email, 'name', pp.display_name,
      'city', g.city, 'country', g.country, 'lat', g.lat, 'lon', g.lon,
      'at', g.seen_at))
      from public.user_geo g
      join auth.users u on u.id = g.user_id
      left join lateral (select x.display_name from public.public_personas x
                          where x.owner_user_id = g.user_id and x.is_active
                          order by x.updated_at desc limit 1) pp on true
     where not exists (select 1 from people p where p.user_id = g.user_id)
  ), '[]'::jsonb)
);
$$;

revoke all on function public.admin_live() from public, anon, authenticated;
grant execute on function public.admin_live() to service_role;
