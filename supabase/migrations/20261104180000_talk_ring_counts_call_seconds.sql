-- The ring counts the time practiced, not the time charged (2026-11-04).
--
-- A pronunciation call costs half: the gateway charges half a second per
-- second of call, and every such tick carries the call's own length as
-- `metadata.call_seconds` beside the charged `seconds`. The home ring, the
-- routine and the streak count the time the learner practiced (founder:
-- "it should feel like a discount"), so the day's sum prefers
-- `call_seconds` where a row has it. Every other row is unchanged: charged
-- and called are the same second there, and no `call_seconds` is written.

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
         sum(coalesce((l.metadata->>'call_seconds')::int,
                      (l.metadata->>'seconds')::int))::integer as seconds
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
