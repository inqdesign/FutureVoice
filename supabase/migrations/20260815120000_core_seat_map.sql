-- ---------------------------------------------------------------------------
-- The 100 seats, drawn.
--
-- Until now the club screen could say "37 / 100" and nothing else: `club_size`
-- is a COUNT, and the membership list is deliberately unreadable
-- (20260814150000). A number is not a picture of a room. The screen has to
-- show the hundred seats themselves — filled ones in the colour that member's
-- own app wears, empty ones empty — because that is the only version of
-- "one of a hundred" a person can feel rather than parse.
--
-- What that costs, and what it deliberately does NOT cost:
--
--   * A seat carries ONE fact: a theme index. No uuid, no name, no join
--     number, no talk time. The array is not joinable to a person; it is the
--     room's colours. `core_badges_for` stays the only way to tie a seal to
--     someone, and it still only answers about ids the caller already names.
--   * Order is by `join_number` ascending, which is a deliberate choice and
--     not a free one. It makes the grid a chronology — the top-left corner is
--     the club's oldest member and a learner can see where they sit in it —
--     at the price that a seat going empty is visible AT A POSITION. Someone
--     watching daily could infer that the person who sat 12th from the front
--     left, which is a softer version of the departure privacy in
--     20260813120000 §3: they learn a seat's rank, never a name, and there is
--     nothing to look the rank up in. Shuffling would have closed even that,
--     and would have cost the chronology, which is the whole reason to draw a
--     grid instead of a progress bar.
--
-- The theme is the palette the member picked in Me (`futureselfTheme`), not a
-- colour we assign. It is the one colour in the app that is already theirs by
-- choice, so a wall of them is a wall of people rather than a generated
-- palette. It lives on `core_membership` because that row is exactly as
-- long-lived as a seat is.
-- ---------------------------------------------------------------------------

alter table public.core_membership
  add column if not exists theme smallint not null default 0;

comment on column public.core_membership.theme is
  'FutureselfTheme rawValue the member''s app wears. Published by the client '
  'via core_set_theme; the only per-member fact core_seat_map exposes.';

-- ---------------------------------------------------------------------------
-- 1. Publishing your own colour
--
-- `core_membership` is RLS-locked to a self READ; there is no write policy and
-- there must not be one, since every other column on the row (seated,
-- days_total, last_left_on) is the settlement's to decide. So the one writable
-- column gets its own definer function, pinned to that column and to the
-- caller's own row.
--
-- A non-member calling this updates zero rows and gets no error: the client
-- fires it on launch without first asking whether it's in the club, and a
-- 404-shaped failure there would be noise on a path nobody is waiting for.
-- ---------------------------------------------------------------------------

create or replace function public.core_set_theme(p_theme integer)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  -- Clamped, not validated: the client is the only writer and an out-of-range
  -- value means a future theme this server hasn't heard of. Storing it lets a
  -- newer app draw it correctly while older readers fall back — rejecting it
  -- would strand the member on someone else's colour.
  update public.core_membership
     set theme = greatest(0, least(p_theme, 255))
   where user_id = auth.uid();
$$;

revoke all on function public.core_set_theme(integer) from public, anon;
grant execute on function public.core_set_theme(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The room
--
-- Returns exactly `seats` entries — the taken ones first in join order, then
-- nulls — so the client draws a fixed grid and never has to know the seat
-- count to lay it out. `mine` is the index of the caller's own seat, or null;
-- resolving it here rather than client-side means the caller's uuid never has
-- to appear in the payload for them to find themselves.
-- ---------------------------------------------------------------------------

create or replace function public.core_seat_map()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_seats  integer;
  v_themes jsonb;
  v_mine   integer;
  v_taken  integer;
begin
  select seats into v_seats from core_club_config where id;

  -- Ordered once, into an array, so the position a member holds in `themes`
  -- and the position reported as `mine` can never disagree.
  with seated as (
    select m.user_id, m.theme,
           (row_number() over (order by m.join_number))::int - 1 as idx
      from core_membership m
     where m.seated
     order by m.join_number
     limit v_seats
  )
  select jsonb_agg(theme order by idx),
         count(*)::int,
         max(idx) filter (where user_id = v_uid)
    into v_themes, v_taken, v_mine
    from seated;

  return jsonb_build_object(
    'seats',  v_seats,
    'taken',  coalesce(v_taken, 0),
    'themes', coalesce(v_themes, '[]'::jsonb),
    'mine',   v_mine);
end;
$$;

revoke all on function public.core_seat_map() from public, anon;
-- Signed-in only. The colours are anonymous, but the room is the club's, and
-- the anon key is handed to anyone who downloads the app.
grant execute on function public.core_seat_map() to authenticated;
