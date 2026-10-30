-- A new Core member is NEWS for everyone learning that language
-- (2026-10-30, founder: "when someone becomes a Core member, tell the others
-- so they can cheer, every time, and a sheet that says: you try it too").
--
-- The news goes out when the new member FINISHES their welcome (colour, name,
-- hope, the cube placed), not when the seat is taken: until then there is no
-- cube to show and no name to cheer. Every build with the welcome ends it with
-- `core_set_engraving`, so the first call to it on a seated row is the moment;
-- later edits from the seat sheet are not news again (`welcomed_at`).
--
-- Who hears it: everyone learning the club's language — `profiles.target_language`
-- or a talk in that language in the last 60 days — except the member. The
-- push is sent by `owner-watch` (it already runs every minute and holds the
-- push secret) through `core_new_member_alerts_claim`; the sheet in the app
-- reads `core_new_member`.

alter table public.core_membership
  add column if not exists welcomed_at timestamptz;

alter table public.core_events drop constraint if exists core_events_kind_check;
alter table public.core_events add constraint core_events_kind_check
  check (kind in ('qualified', 'seated', 'left', 'club_full', 'welcomed'));

create or replace function public.core_set_engraving(
  p_language text,
  p_name text,
  p_hope text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lang text := lower(btrim(coalesce(p_language, '')));
  r      record;
begin
  update public.core_membership
     set engraved_name = nullif(left(btrim(coalesce(p_name, '')), 24), ''),
         hope          = nullif(left(btrim(coalesce(p_hope, '')), 60), ''),
         updated_at    = now()
   where user_id = auth.uid()
     and language = v_lang
  returning user_id, join_number, seated, welcomed_at into r;

  if r.user_id is null or not r.seated or r.welcomed_at is not null then
    return;
  end if;

  update public.core_membership set welcomed_at = now()
   where user_id = r.user_id and language = v_lang;
  insert into public.core_events (kind, user_id, join_number, club_size, language)
  values ('welcomed', r.user_id, r.join_number,
          (select count(*) from core_membership where seated and language = v_lang),
          v_lang);
end;
$$;

revoke all on function public.core_set_engraving(text, text, text) from public, anon;
grant execute on function public.core_set_engraving(text, text, text) to authenticated;

-- The newest new member in a club to tell this reader about: after `p_after`
-- (the last one this install showed), within a week, still seated, not the
-- reader. Its cell index is ordered like `core_seat_map`, so the cheers RPCs
-- take it as is. `viewer_seated` decides whether the sheet says "you try it".
create or replace function public.core_new_member(p_language text, p_after bigint default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_lang text := lower(btrim(coalesce(p_language, '')));
  e      record;
  v_idx  integer;
  v_name text;
  v_theme integer;
begin
  select ev.id, ev.user_id into e
    from core_events ev
    join core_membership m on m.user_id = ev.user_id and m.language = ev.language
   where ev.kind = 'welcomed' and ev.language = v_lang
     and ev.id > coalesce(p_after, 0)
     and ev.created_at > now() - interval '7 days'
     and m.seated
     and ev.user_id is distinct from v_uid
   order by ev.id desc
   limit 1;
  if e.id is null then
    return null;
  end if;

  with seated as (
    select m.user_id, m.theme, m.engraved_name,
           (row_number() over (order by m.join_number))::int - 1 as idx
      from core_membership m
     where m.seated and m.language = v_lang
     order by m.join_number
     limit (select seats from core_club_config where id)
  )
  select idx, engraved_name, theme into v_idx, v_name, v_theme
    from seated where user_id = e.user_id;
  if v_idx is null then
    return null;
  end if;

  return jsonb_build_object(
    'event_id', e.id,
    'index', v_idx,
    'name', v_name,
    'theme', v_theme,
    'viewer_seated', exists (select 1 from core_membership
                              where user_id = v_uid and language = v_lang and seated));
end;
$$;
revoke all on function public.core_new_member(text, bigint) from public, anon;
grant execute on function public.core_new_member(text, bigint) to authenticated;

-- Who learns that language: the target language they picked, or a talk in it
-- in the last 60 days. Called by `owner-watch` only.
create or replace function public.core_language_learners(p_language text, p_exclude uuid)
returns table (user_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select p.id from profiles p
   where lower(p.target_language) = lower(btrim(coalesce(p_language, '')))
  union
  select t.user_id from talk_seconds_by_language t
   where t.language = lower(btrim(coalesce(p_language, '')))
     and t.day > current_date - 60
  except
  select p_exclude;
$$;
revoke all on function public.core_language_learners(text, uuid) from public, anon, authenticated;

-- New members for `owner-watch`, claimed once in `owner_alerts` like the notes.
create or replace function public.core_new_member_alerts_claim(p_limit int default 20)
returns table (kind text, key text, payload jsonb)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with fresh as (
    select ev.* from core_events ev
     where ev.kind = 'welcomed'
       and ev.created_at > now() - interval '1 day'
       and not exists (select 1 from owner_alerts a
                        where a.kind = 'core_welcomed' and a.key = ev.id::text)
     order by ev.id
     limit p_limit
  ), claimed as (
    insert into owner_alerts (kind, key)
    select 'core_welcomed', id::text from fresh
    on conflict do nothing
    returning owner_alerts.key
  )
  select 'core_welcomed'::text, f.id::text,
         jsonb_build_object(
           'id', f.id,
           'user_id', f.user_id,
           'language', f.language,
           'number', (select count(*) from core_membership m2
                       where m2.seated and m2.language = f.language
                         and m2.join_number <= f.join_number),
           'name', (select m.engraved_name from core_membership m
                     where m.user_id = f.user_id and m.language = f.language))
    from fresh f
    join claimed c on c.key = f.id::text;
end;
$$;
revoke all on function public.core_new_member_alerts_claim(int) from public, anon, authenticated;
