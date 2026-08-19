-- ---------------------------------------------------------------------------
-- The badge is current membership. Nothing else.
--
-- `core_badges_for` answered with every member row it was asked about, seated
-- or not, and the client drew a FILLED seal for a seated member and an
-- OUTLINED one for someone who had qualified and currently held no seat. The
-- intent was decent — the thirty days happened, and nobody takes them back —
-- but the seal's only audience is a stranger scrolling Find people, and there
-- a mark beside a name has to mean one thing on sight. Two states that differ
-- by fill weight, with no room on the row for a legend, means the reader
-- learns nothing from either.
--
-- So: the seal means they're in the Core today. Qualification stays permanent
-- where it does real work — queue order (`join_number`), and re-entry on the
-- keep bar rather than the full streak — it just isn't something worn.
--
-- Filtered HERE and not only in the app, because every build already in the
-- field asks this function and would keep drawing outlined seals from rows it
-- was handed. Filtering at the source retires the second state everywhere at
-- once.
--
-- The `seated` column stays in the result — always true now — so those older
-- builds keep decoding the shape they were compiled against. Dropping it would
-- fail their decode and take the badge off every name, including the members
-- who have one.
-- ---------------------------------------------------------------------------

create or replace function public.core_badges_for(
  p_user_ids uuid[],
  p_language text
) returns table(user_id uuid, seated boolean)
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
   where m.user_id = any (p_user_ids[1:200])
     and m.language = lower(trim(p_language))
     and m.seated;
$$;

revoke all on function public.core_badges_for(uuid[], text) from public, anon;
grant execute on function public.core_badges_for(uuid[], text) to authenticated;
