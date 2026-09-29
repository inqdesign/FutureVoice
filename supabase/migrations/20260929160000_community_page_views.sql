-- nawana.app/community: a running total of page opens, for the team's eyes.
--
-- The page stores nothing in the browser (no cookie, no id), so a signed-out
-- visitor can't be told apart from a returning one: what can be counted
-- honestly is OPENS, per day, and — through community_visits — the number of
-- distinct signed-in accounts. Both come back only to staff, through
-- community_staff_stats(); a learner's browser can add an open but never read
-- the totals.

create table if not exists public.community_page_views (
  day        date primary key,
  views      int not null default 0,
  signed_in  int not null default 0
);
alter table public.community_page_views enable row level security;
-- no policies: written by the function below, read by the staff function

create or replace function public.community_count_view()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_signed int := case when auth.uid() is not null
                        and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
                       then 1 else 0 end;
begin
  insert into community_page_views (day, views, signed_in)
  values ((now() at time zone 'utc')::date, 1, v_signed)
  on conflict (day) do update
    set views = community_page_views.views + 1,
        signed_in = community_page_views.signed_in + v_signed;
end;
$$;

create or replace function public.community_staff_stats()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
begin
  if not exists (select 1 from community_staff where user_id = auth.uid()) then
    return null;
  end if;
  return json_build_object(
    'views_total',     coalesce((select sum(views) from community_page_views), 0),
    'views_today',     coalesce((select views from community_page_views where day = v_today), 0),
    'accounts_total',  (select count(*) from community_visits),
    'accounts_today',  (select count(*) from community_visits where last_seen >= v_today),
    'messages_total',  (select count(*) from community_messages where not hidden)
  );
end;
$$;

revoke all on function public.community_count_view() from public;
grant execute on function public.community_count_view() to anon, authenticated;
revoke all on function public.community_staff_stats() from public, anon;
grant execute on function public.community_staff_stats() to authenticated;
