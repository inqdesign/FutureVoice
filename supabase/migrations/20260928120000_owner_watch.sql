-- The owner hears about the three moments that matter, while they happen.
--
-- `paywall-notify` (2026-09-24) already pings a subscribe TAP from the app.
-- Two weeks of it produced nothing at all, and neither half of that was a
-- bug: it only fires on the TAP (the ask was "when the paywall APPEARS"),
-- and it only exists in build 60+, which shipped on 09-27 — nobody on it had
-- tapped Subscribe yet. `client_events` has 88 `paywall_shown` rows over the
-- same period, so the fact was in the database the whole time with nothing
-- reading it.
--
-- So the watcher lives on the SERVER, over tables that are already written:
--   * a SIGNUP is a row in `auth.identities` — an anonymous user has none
--     (`stale_anonymous_users` rests on exactly that), so an identity is the
--     moment someone stopped being a session and became an account;
--   * a SUBSCRIPTION is an entitled `user_subscriptions` row, whoever wrote
--     it — apple-webhook, apple-claim, stripe-webhook or a comp;
--   * a PAYWALL is `client_events.paywall_shown`, which every build already
--     sends.
-- Nothing here needs an app release, and a purchase path added later is
-- watched the day it writes its first row.
--
-- Two rules, both borrowed from `push_sends`:
--   * The key is CLAIMED before the message is sent, so a Telegram failure
--     is not retried — an alert nobody can see twice is worth more than one
--     that arrives three times at 3am.
--   * A renewal is not an event. The subscription key carries plan + status
--     + `started_at`, none of which a renewal moves, so a monthly charge is
--     silent while a trial converting to paid is one message.

create table if not exists public.owner_alerts (
  kind       text not null,
  key        text not null,
  created_at timestamptz not null default now(),
  primary key (kind, key)
);

comment on table public.owner_alerts is
  'Claimed owner notifications. A row means "already sent, never again".';

alter table public.owner_alerts enable row level security;
-- No policy: service_role bypasses RLS and nothing else may read this.
revoke all on table public.owner_alerts from anon, authenticated;

-- How far back a run looks. It bounds the scan and it is the honest limit of
-- the promise: if Telegram or the cron is down longer than this, the moment
-- is missed rather than delivered stale. Paired with a once-a-minute
-- schedule, this is ~120 chances to deliver each alert's first attempt.
create or replace function public.owner_alerts_claim(p_limit int default 20)
returns table (kind text, key text, payload jsonb)
language plpgsql
security definer
set search_path = public, auth
as $$
-- The OUT parameters are called kind/key/payload and so are the columns
-- below; without this an unqualified reference is "ambiguous" and the
-- function refuses to run. Nothing here reads the OUT variables by name.
#variable_conflict use_column
begin
  return query
  with candidate as (
    -- 1. Someone became an account.
    select 'signup'::text as kind,
           i.id::text     as key,
           i.created_at   as at,
           jsonb_build_object(
             'user_id',  i.user_id,
             'email',    coalesce(u.email, i.email),
             'provider', i.provider,
             'at',       i.created_at
           ) as payload
      from auth.identities i
      join auth.users u on u.id = i.user_id
     where i.created_at > now() - interval '2 hours'

    union all

    -- 2. Money. The key is what a RENEWAL does not change.
    select 'subscription',
           s.user_id::text || ':' || s.plan_id || ':' || s.status || ':' ||
             coalesce(to_char(s.started_at, 'YYYYMMDDHH24MISS'), '-'),
           s.updated_at,
           jsonb_build_object(
             'user_id',       s.user_id,
             'email',         u.email,
             'plan',          s.plan_id,
             'status',        s.status,
             'source',        s.source,
             'trial_ends_at', s.trial_ends_at,
             'started_at',    s.started_at,
             'at',            s.updated_at
           )
      from public.user_subscriptions s
      join auth.users u on u.id = s.user_id
     where s.status in ('active', 'trialing')
       and s.updated_at > now() - interval '2 hours'

    union all

    -- 3. The paywall, ONCE per learner per day. Someone who meets it four
    -- times in an afternoon is one person deciding, not four events.
    select 'paywall',
           e.user_id::text || ':' || to_char(e.created_at at time zone 'UTC', 'YYYY-MM-DD'),
           min(e.created_at),
           jsonb_build_object(
             'user_id', e.user_id,
             'email',   max(u.email),
             'source',  min(e.properties->>'source'),
             'count',   count(*),
             'at',      min(e.created_at)
           )
      from public.client_events e
      join auth.users u on u.id = e.user_id
     where e.event = 'paywall_shown'
       and e.created_at > now() - interval '2 hours'
       and e.user_id is not null
     group by e.user_id, to_char(e.created_at at time zone 'UTC', 'YYYY-MM-DD')
  ),
  fresh as (
    select c.kind, c.key, c.at, c.payload
      from candidate c
     where not exists (
       select 1 from public.owner_alerts a
        where a.kind = c.kind and a.key = c.key
     )
     order by c.at
     limit greatest(least(p_limit, 50), 1)
  ),
  claimed as (
    insert into public.owner_alerts (kind, key)
    select f.kind, f.key from fresh f
    on conflict (kind, key) do nothing
    returning owner_alerts.kind, owner_alerts.key
  )
  select f.kind, f.key, f.payload
    from fresh f
    join claimed c on c.kind = f.kind and c.key = f.key
   order by f.at;
end $$;

revoke all on function public.owner_alerts_claim(int) from public, anon, authenticated;
grant execute on function public.owner_alerts_claim(int) to service_role;

-- Seed everything that already happened, so the first run is silent. The
-- window above is two hours; a day of margin costs nothing and covers a
-- migration applied long after it was written.
insert into public.owner_alerts (kind, key)
select 'signup', i.id::text
  from auth.identities i
 where i.created_at > now() - interval '1 day'
on conflict do nothing;

insert into public.owner_alerts (kind, key)
select 'subscription',
       s.user_id::text || ':' || s.plan_id || ':' || s.status || ':' ||
         coalesce(to_char(s.started_at, 'YYYYMMDDHH24MISS'), '-')
  from public.user_subscriptions s
 where s.updated_at > now() - interval '1 day'
on conflict do nothing;

insert into public.owner_alerts (kind, key)
select distinct 'paywall',
       e.user_id::text || ':' || to_char(e.created_at at time zone 'UTC', 'YYYY-MM-DD')
  from public.client_events e
 where e.event = 'paywall_shown'
   and e.user_id is not null
   and e.created_at > now() - interval '1 day'
on conflict do nothing;

-- Once a minute. Best-effort and vault-gated, the same shape as the voice
-- cleanup: the function stands on its own if pg_cron or the secrets are
-- absent, and nothing here is allowed to fail a migration.
do $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'owner watch: pg_cron/pg_net unavailable, not scheduled';
    return;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'cleanup_secret' limit 1;
  if v_url is null or v_secret is null then
    raise notice 'owner watch: vault secrets missing, not scheduled';
    return;
  end if;

  perform cron.unschedule('owner_watch')
    where exists (select 1 from cron.job where jobname = 'owner_watch');

  perform cron.schedule(
    'owner_watch', '* * * * *',
    format(
      $cron$select net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Cleanup-Secret', %L
        ),
        body := '{}'::jsonb
      );$cron$,
      v_url || '/functions/v1/owner-watch',
      v_secret
    )
  );
exception when others then
  raise notice 'owner watch scheduling skipped: %', sqlerrm;
end $$;
