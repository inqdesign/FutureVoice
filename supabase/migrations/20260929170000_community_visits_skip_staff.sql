-- The team's own visits are not visitors. Same rule as the app's analytics
-- (the owner's accounts are excluded there too): a staff account's page open
-- is neither counted as a view nor recorded as a visit, and the staff totals
-- leave staff accounts out.

create or replace function public.community_count_view()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_signed int := case when v_uid is not null
                        and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
                       then 1 else 0 end;
begin
  if v_uid is not null and exists (select 1 from community_staff where user_id = v_uid) then
    return;
  end if;
  insert into community_page_views (day, views, signed_in)
  values ((now() at time zone 'utc')::date, 1, v_signed)
  on conflict (day) do update
    set views = community_page_views.views + 1,
        signed_in = community_page_views.signed_in + v_signed;
end;
$$;

create or replace function public.community_touch_visit()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
     or exists (select 1 from community_staff where user_id = v_uid) then
    return;
  end if;
  insert into community_visits (user_id) values (v_uid)
  on conflict (user_id) do update
    set visits = community_visits.visits
                 + case when community_visits.last_seen < now() - interval '30 minutes' then 1 else 0 end,
        last_seen = now();
end;
$$;

-- totals exclude staff rows even if one was recorded before this change
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
    'accounts_total',  (select count(*) from community_visits v
                         where not exists (select 1 from community_staff s where s.user_id = v.user_id)),
    'accounts_today',  (select count(*) from community_visits v
                         where v.last_seen >= v_today
                           and not exists (select 1 from community_staff s where s.user_id = v.user_id)),
    'messages_total',  (select count(*) from community_messages where not hidden)
  );
end;
$$;

-- The rows the team's own visits already wrote.
delete from public.community_visits v
 where exists (select 1 from public.community_staff s where s.user_id = v.user_id);
