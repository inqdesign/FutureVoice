-- nawana.app/community: who came, for the team.
--
-- One row per signed-in account: first visit, last visit, and how many
-- visits — a visit being a page open more than 30 minutes after the last one,
-- so a reload or a tab left open isn't counted twice. Signed-out visitors are
-- not recorded here at all (the page counts them through PostHog with no
-- cookie and no stored identifier).
--
-- Nobody reads this from a browser; the team reads it with the service role
-- (scripts/community.py visitors, the admin console).

create table if not exists public.community_visits (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  visits      int not null default 1
);

alter table public.community_visits enable row level security;
-- no policies: invisible to anon and authenticated alike

create or replace function public.community_touch_visit()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    return;
  end if;
  insert into community_visits (user_id) values (v_uid)
  on conflict (user_id) do update
    set visits = community_visits.visits
                 + case when community_visits.last_seen < now() - interval '30 minutes' then 1 else 0 end,
        last_seen = now();
end;
$$;

revoke all on function public.community_touch_visit() from public, anon;
grant execute on function public.community_touch_visit() to authenticated;
