-- The seat's side face reads "SINCE <date> · DAY <n>" (2026-10-29,
-- founder), so `core_seat_detail` also returns `seated_since`, the UTC day
-- the seat was taken. Same function otherwise (20261029140000).

create or replace function public.core_seat_detail(p_language text, p_index integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_lang   text := nullif(lower(btrim(coalesce(p_language, ''))), '');
  v_seats  integer;
  v_member boolean;
  v_mine   boolean;
  r        record;
begin
  if v_lang is null then
    raise exception 'p_language required';
  end if;

  select seats into v_seats from core_club_config where id;

  with seated as (
    select m.user_id, m.theme, m.engraved_name, m.hope, m.seated_since,
           (row_number() over (order by m.join_number))::int - 1 as idx
      from core_membership m
     where m.seated and m.language = v_lang
     order by m.join_number
     limit v_seats
  )
  select * into r from seated where idx = p_index;

  if not found then
    return null;
  end if;

  v_member := v_uid is not null and exists (
    select 1 from core_membership
     where user_id = v_uid and language = v_lang and seated);
  v_mine := coalesce(r.user_id = v_uid, false);

  return jsonb_build_object(
    'index', p_index,
    'theme', r.theme,
    -- A seat engraved before this existed (or never engraved) falls back to
    -- the name its owner already shows strangers in Find people.
    'name', coalesce(r.engraved_name,
                     (select p.display_name from public_personas p
                       where p.owner_user_id = r.user_id
                       order by p.updated_at desc nulls last
                       limit 1)),
    'mine', v_mine,
    -- How long this seat has been held, counted from the day it was taken
    -- (UTC, like every Core day), so it moves on by itself each day.
    'days_held', greatest(1, (now() at time zone 'utc')::date - r.seated_since + 1),
    'seated_since', r.seated_since,
    'can_read_hope', v_member or v_mine,
    'hope', case when v_member or v_mine then r.hope end);
end;
$$;

