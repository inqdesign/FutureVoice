-- The home ring's server sync, summed on the server (2026-10-28).
--
-- `TalkTimeLog.syncFromServer` (iOS + Android) downloaded every `talk_time`
-- row of the last 14 days on every Talk-tab appear and added them up on the
-- phone: ~80 rows a day for a heavy talker, ~500 KB a visit, and past
-- PostgREST's 1,000-row cap the rows cut were today's, so the ring walked
-- backwards. This answers the same sum in one row per (local day, language).
--
-- Bucketed by the LEARNER's time zone, which only the phone knows — the
-- server's own pools are UTC days and the ring belongs to the day the
-- learner is living in. Same exclusions as the client: the preflight second
-- (a wall check, never talk) and non-positive ticks. An unknown time zone
-- raises, and the client then falls back to reading the rows.

create or replace function public.talk_seconds_by_local_day(
  p_since timestamptz,
  p_tz    text
) returns table (day date, language text, seconds integer)
language sql
stable
security invoker
set search_path = public
as $$
  select (l.created_at at time zone p_tz)::date as day,
         nullif(lower(btrim(l.metadata->>'language')), '') as language,
         sum((l.metadata->>'seconds')::int)::integer as seconds
    from usage_ledger l
   where l.user_id = auth.uid()
     and l.action = 'talk_time'
     -- Never more than the log keeps, whatever the caller asks.
     and l.created_at >= greatest(p_since, now() - interval '46 days')
     and coalesce((l.metadata->>'seconds')::int, 0) > 0
     and coalesce(l.metadata->>'preflight', 'false') <> 'true'
     and coalesce(l.idempotency_key, '') not like '%:pre'
   group by 1, 2;
$$;

revoke all on function public.talk_seconds_by_local_day(timestamptz, text) from public, anon;
grant execute on function public.talk_seconds_by_local_day(timestamptz, text) to authenticated;
