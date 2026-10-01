-- A voice is never parked without being announced first (2026-10-01).
--
-- `park-idle-voices` used to delete a voice the hour it qualified, and the
-- learner found out by coming back to an app that could not speak. Now the
-- function runs in two steps over the same candidates:
--   1. two days before a voice would qualify, it is ANNOUNCED — a row here
--      (with the date it may go) and a push naming that date;
--   2. it is parked only once that date has passed and the announcement on
--      file is for the SAME idle stretch.
-- A learner who comes back in between moves `idle_since`, so the old row no
-- longer matches and nothing is parked; the next stretch is announced anew.
-- A learner with no push token still gets a row (and so is still parked on
-- time); the push is a courtesy, the row is the rule.

create table if not exists public.voice_park_notices (
  user_id     uuid        not null references auth.users(id) on delete cascade,
  idle_since  timestamptz not null,
  rule        text        not null,
  warned_at   timestamptz not null default now(),
  park_after  timestamptz not null,
  pushed      int         not null default 0,
  primary key (user_id, idle_since)
);

alter table public.voice_park_notices enable row level security;
-- No policies: service role only.

-- Every voice that could be parked, with the moment its idle stretch began,
-- WITHOUT the 7-day cutoff (the function applies the cutoffs itself, two of
-- them). Same facts and rules as `parkable_voice_owners`, which stays for
-- anything still calling it.
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
           (select max(l.created_at) from usage_ledger l
             where l.user_id = v.user_id and l.delta < 0) as last_spend,
           greatest(
             (select max(l.created_at) from usage_ledger l
               where l.user_id = v.user_id and l.delta <= 0),
             (select max(e.created_at) from client_events e
               where e.user_id = v.user_id)
           ) as last_seen,
           (select max(s.current_period_end) from user_subscriptions s
             where s.user_id = v.user_id) as sub_ended,
           v.cloned_at
      from v
      join auth.users u on u.id = v.user_id
      left join user_credits c on c.user_id = v.user_id
     where not coalesce(u.is_anonymous, false)
       and not public.voice_owner_is_entitled(v.user_id)
  ),
  ranked as (
    select f.user_id,
           case when f.balance <= 0 then 'spent' else 'idle' end as rule,
           f.balance,
           case when f.balance <= 0
                then greatest(f.last_spend, f.sub_ended, f.cloned_at)
                else greatest(f.last_seen, f.sub_ended, f.cloned_at) end as idle_since
      from facts f
  )
  select * from ranked
   where idle_since < now() - interval '1 day'
   order by idle_since
   limit greatest(least(p_limit, 2000), 1);
$$;

revoke all on function public.voice_parking_candidates(int) from public, anon, authenticated;
grant execute on function public.voice_parking_candidates(int) to service_role;
