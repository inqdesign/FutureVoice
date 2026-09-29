-- ---------------------------------------------------------------------------
-- The console's "누가 어느 날 말했나" heatmap reads the reader's day (2026-09-27).
--
-- The heatmap drew `admin_raw().cells`, which the database groups by UTC day,
-- while every other time on the page follows the zone picked in the header.
-- Measured over 9/12–9/27: 35.5% of all talk seconds fall on a different day
-- in Seoul than in UTC, 11.1% in Berlin — a Korean learner's morning call sat
-- on "yesterday", and the column labelled 오늘 was the UTC day. The page now
-- rebuilds the grid from `day_hours` (user × UTC day × UTC hour), which can be
-- re-bucketed into any whole-hour zone.
--
-- `day_hours` carries talk seconds, speech and ledger rows but not the TURN
-- count the tooltip prints, so this hands it over at the same grain. Same
-- rule as `admin_raw`'s `cells.turns`: one turn = one reply call, speculative
-- replies excluded. A function of its own rather than another copy of
-- `admin_raw`, like `admin_talk_cost`; the console treats it as optional and
-- simply omits the turn count until it exists. Service role only.
-- ---------------------------------------------------------------------------

create or replace function public.admin_turn_hours()
returns jsonb
language sql
security definer
set search_path to 'public'
stable
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', user_id::text, 'd', d::text, 'h', h, 'n', n)), '[]'::jsonb)
    from (select user_id,
                 (created_at at time zone 'UTC')::date                 as d,
                 extract(hour from created_at at time zone 'UTC')::int as h,
                 count(*)::int                                         as n
            from public.usage_ledger
           where created_at >= date '2026-09-11'   -- launch day, less a day for zones east of UTC
             and source_fn = 'gemini'
             and metadata->>'purpose' = 'turn'
             and coalesce(metadata->>'spec', 'false') <> 'true'
           group by 1, 2, 3) t;
$$;

revoke all on function public.admin_turn_hours() from public, anon, authenticated;
grant execute on function public.admin_turn_hours() to service_role;
