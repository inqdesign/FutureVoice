-- Public-safe counters for the waitlist admin screen.
--
-- The waitlist table blocks anon SELECT (emails stay private). This RPC runs as
-- the definer and returns ONLY aggregate counts — never any email — so a simple
-- status page can show totals with the anon key without exposing signups.

create or replace function public.waitlist_stats()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'total', (select count(*) from public.waitlist),
    'beta',  (select count(*) from public.waitlist where wants_beta),
    'today', (select count(*) from public.waitlist
              where created_at >= date_trunc('day', now() at time zone 'utc'))
  );
$$;

revoke all on function public.waitlist_stats() from public;
grant execute on function public.waitlist_stats() to anon, authenticated;
