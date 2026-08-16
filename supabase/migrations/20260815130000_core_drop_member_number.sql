-- ---------------------------------------------------------------------------
-- The member number stops being a fact about a person.
--
-- `join_number` was issued once, never reused, and shown everywhere: on the
-- club screen, in the Me row, in the arrival notification. Two things were
-- wrong with it, and the second only became visible once the screen started
-- drawing the hundred seats:
--
--   * **It outgrows the club.** Never reusing a number is the right call —
--     recycling #37 onto the person who took that seat would be grotesque —
--     but it means the numbers climb forever while the seats stay at a
--     hundred. A club of 100 with a member #137 in it is a contradiction the
--     learner has to be argued out of, next to a picture of exactly 100 cells.
--   * **It is a rank.** "Member #7" beside "Member #91" orders two people who
--     are, inside the club, equal — the exact hierarchy 20260813120000 spent
--     its design effort removing, reintroduced as a decoration.
--
-- So the number stops being READ. It is not dropped: the column is the
-- server's ordering key — seat order in `core_seat_map` (the grid is a
-- chronology, oldest first) and the promotion tie-break in
-- `settle_core_club`. Both need a stable total order over members and
-- `qualified_at` alone doesn't give one, since a whole settlement batch
-- qualifies at the same instant. Dropping it would also throw away the record
-- of who was here first, which is not ours to throw away.
--
-- What changes here is the one place a number reached a STRANGER.
-- ---------------------------------------------------------------------------

comment on column public.core_membership.join_number is
  'Internal ordering key only (seat order, promotion tie-break). Never '
  'returned to a client and never shown: see 20260815130000.';

-- `core_badges_for` is what draws the seal beside someone''s name in Find
-- people. It answered with the number too, which made a browsable list of
-- people quietly into a ranked one. Same audience, same lookup-only shape,
-- one fewer column.
drop function if exists public.core_badges_for(uuid[]);

create or replace function public.core_badges_for(p_user_ids uuid[])
returns table (user_id uuid, seated boolean)
language sql
stable
security definer
set search_path = public
as $$
  -- Sliced, not LIMITed: a caller asking about too many people gets a
  -- deterministic prefix of what they asked for, never an arbitrary window
  -- onto the membership table. A screen of personas is ~50.
  select m.user_id, m.seated
    from public.core_membership m
   where m.user_id = any (p_user_ids[1:200]);
$$;

revoke all on function public.core_badges_for(uuid[]) from public;
grant execute on function public.core_badges_for(uuid[]) to anon, authenticated;
