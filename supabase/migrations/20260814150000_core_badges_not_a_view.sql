-- ---------------------------------------------------------------------------
-- core_badges stops being a view.
--
-- `core_membership` is RLS-locked to the owner's own row, because
-- `last_left_on` / `days_total` are how you work out whose seat you took —
-- and departures are private (20260813120000, section 3). The badge facts a
-- STRANGER is allowed to see (seal + number) were published by wrapping the
-- table in a view and granting it to anon/authenticated.
--
-- That worked for exactly one reason: a Postgres view defaults to
-- `security_invoker = off`, so it runs as its OWNER and the table's RLS never
-- applies. Supabase's `security_definer_view` lint flags it, and the lint is
-- right about the mechanism even though the three published columns are
-- deliberate. Two things are actually wrong with it:
--
--   * `select * from core_badges` enumerates every member's auth uuid, to
--     anyone holding the anon key. The app never needs that — it asks about
--     the handful of persona owners on screen. Harvestable uuids are what
--     made the metering RPCs exploitable in 20260814140000; this was the
--     second place to harvest them.
--   * The RLS bypass is IMPLICIT. Add a column to core_membership, widen the
--     view to `select *`, and `last_left_on` goes public silently — the rule
--     the club is built on, broken by an edit that looks like a no-op.
--
-- The fix is not to remove the bypass (the badge has to outlive RLS by
-- design) but to make it explicit, column-pinned and non-enumerable: a
-- SECURITY DEFINER function that answers only about ids the caller already
-- names. Same three columns, same audience.
--
-- `security_invoker = on` + a broad read policy was considered and rejected:
-- a `using (true)` policy publishes last_left_on/days_total, and column-level
-- grants can't fix it because they are not row-aware — they would also block
-- a member reading their OWN days_total (CoreClubService.fetchMine).
-- ---------------------------------------------------------------------------

drop view if exists public.core_badges;

create or replace function public.core_badges_for(p_user_ids uuid[])
returns table (user_id uuid, join_number integer, seated boolean)
language sql
stable
security definer
set search_path = public
as $$
  -- Sliced, not LIMITed: a caller asking about too many people gets a
  -- deterministic prefix of what they asked for, never an arbitrary window
  -- onto the membership table. A screen of personas is ~50.
  select m.user_id, m.join_number, m.seated
    from public.core_membership m
   where m.user_id = any (p_user_ids[1:200]);
$$;

revoke all on function public.core_badges_for(uuid[]) from public;
-- Same audience the view had. The badge is public information; what changes
-- is that it can only be looked UP, never listed.
grant execute on function public.core_badges_for(uuid[]) to anon, authenticated;
