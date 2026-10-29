-- A seat in the Core carries an engraving (2026-10-29, founder).
--
-- The cube a learner places in their seat has their NAME on one face and a
-- HOPE on another, a line about what they want to be able to do with the
-- language. Who reads what:
--   * the name: anyone who opens the Core page and taps the cell;
--   * the hope: other seated members of the same club only, and its owner.
-- The welcome screen says the second rule where the hope is written.
--
-- `core_membership` is readable by its owner alone (RLS "read own"), so the
-- only way another person's hope leaves the table is `core_seat_detail`,
-- which checks the reader's own seat first.

alter table public.core_membership
  add column if not exists engraved_name text,
  add column if not exists hope text;

alter table public.core_membership
  drop constraint if exists core_membership_engraved_name_len,
  add constraint core_membership_engraved_name_len
    check (engraved_name is null or char_length(engraved_name) <= 24),
  drop constraint if exists core_membership_hope_len,
  add constraint core_membership_hope_len
    check (hope is null or char_length(hope) <= 60);

-- The owner writes both at once. Trimmed and cut to length rather than
-- refused: the field on the phone holds the same limits, and a learner who
-- pasted a long line should get their words, shortened, not an error.
create or replace function public.core_set_engraving(
  p_language text,
  p_name text,
  p_hope text
) returns void
language sql
security definer
set search_path = public
as $$
  update public.core_membership
     set engraved_name = nullif(left(btrim(coalesce(p_name, '')), 24), ''),
         hope          = nullif(left(btrim(coalesce(p_hope, '')), 60), ''),
         updated_at    = now()
   where user_id = auth.uid()
     and language = lower(btrim(coalesce(p_language, '')));
$$;

revoke all on function public.core_set_engraving(text, text, text) from public, anon;
grant execute on function public.core_set_engraving(text, text, text) to authenticated;

-- One cell of the seat grid, by the same index `core_seat_map` draws it at.
-- The hope is filled in only for a reader who holds a seat in this club, or
-- for the cell's own owner; `can_read_hope` says which, so the app never has
-- to guess why a hope is missing.
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
    select m.user_id, m.theme, m.engraved_name, m.hope,
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
    'can_read_hope', v_member or v_mine,
    'hope', case when v_member or v_mine then r.hope end);
end;
$$;

revoke all on function public.core_seat_detail(text, integer) from public;
grant execute on function public.core_seat_detail(text, integer) to anon, authenticated;
