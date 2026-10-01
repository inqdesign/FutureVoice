-- One parking rule: no plan, and the app not opened for 7 days (2026-10-01,
-- founder decision). Replaces the two rules of 20260928140000, which judged a
-- learner with nothing left to spend by when they last SPENT — so someone who
-- kept opening the app, looking, was parked as if they had left — and judged a
-- learner with free minutes by ledger rows and client events, which a plain
-- app open writes neither of.
--
-- "Opened the app" is read off the auth tables: the client refreshes its
-- access token on any launch more than an hour after the last, which writes
-- `auth.refresh_tokens` and stamps `auth.sessions.refreshed_at`. Checked
-- against PostHog's `Application Opened` for one returning learner: every
-- open day but one has a refresh. It needs no app change and covers every
-- build already installed. Ledger debits, client events, the end of a
-- subscription and the clone itself still count as activity on top.
--
-- `rule` survives only as the push's title ("spent" = nothing to spend →
-- "subscribe to keep it"; "idle" = minutes left → "open the app to keep it").
-- Same signature as before, so `park-idle-voices` needs no change to use it.

create or replace function public.voice_parking_candidates(p_limit int default 500)
returns table (user_id uuid, rule text, balance numeric, idle_since timestamptz)
language sql
stable
security definer
set search_path = public, auth
as $$
  with v as (
    select vc.user_id, max(vc.created_at) as cloned_at
      from voice_clones vc
     where vc.is_active and vc.parked_at is null
     group by vc.user_id
  ),
  facts as (
    select v.user_id,
           coalesce(c.balance, 0) as balance,
           greatest(
             (select max(coalesce(s.refreshed_at, s.updated_at, s.created_at))
                from auth.sessions s where s.user_id = v.user_id),
             (select max(t.created_at)
                from auth.refresh_tokens t where t.user_id = v.user_id::text),
             (select max(l.created_at) from usage_ledger l
               where l.user_id = v.user_id and l.delta <= 0),
             (select max(e.created_at) from client_events e
               where e.user_id = v.user_id),
             (select max(s.current_period_end) from user_subscriptions s
               where s.user_id = v.user_id),
             v.cloned_at
           ) as last_open
      from v
      join auth.users u on u.id = v.user_id
      left join user_credits c on c.user_id = v.user_id
     where not coalesce(u.is_anonymous, false)
       and not public.voice_owner_is_entitled(v.user_id)
  )
  select f.user_id,
         case when f.balance <= 0 then 'spent' else 'idle' end,
         f.balance,
         f.last_open
    from facts f
   where f.last_open < now() - interval '1 day'
   order by f.last_open
   limit greatest(least(p_limit, 2000), 1);
$$;

revoke all on function public.voice_parking_candidates(int) from public, anon, authenticated;
grant execute on function public.voice_parking_candidates(int) to service_role;
