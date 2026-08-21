-- ---------------------------------------------------------------------------
-- The rolling week starts when the subscription does.
--
-- `20260820140000_talk_weekly_window` computes today's ceiling as
-- `7 × daily − Σ used over the preceding 6 days`. A day with no usage row
-- contributes nothing to that sum, which is right for a day the learner
-- skipped and wrong for a day they did not yet have: on the FIRST day of a
-- subscription all six preceding days are empty, so the very first session
-- opened with the whole week's 35 minutes available.
--
-- What people expect — and what they should get — is an allowance that fills
-- up: 5 minutes on day one, 10 if day one goes unused, and so on to 35. That
-- is the same window with its start clamped to the day the plan began:
--
--     days = LEAST(window_days, days since the subscription started + 1)
--     cap  = days × daily_seconds − Σ used over the preceding (days - 1) days
--
-- Day 1 → 1 × 5 = 5. Day 5 idle → 25. Day 7+ → 35, the steady state. Spend
-- 2 minutes on the 25-minute day and the next day is 6 × 5 − 2 = 28, and that
-- 2 falls out of the window a week later on its own. Once an account is a
-- week old the clamp never binds again, so this changes nothing for anyone
-- except during their first week.
--
-- `started_at` is a new column rather than `current_period_start`, which
-- moves to the renewal date every cycle and would re-clamp a two-year
-- subscriber's window down to one day every month. Existing rows are
-- backfilled to their current period start — the only date on file, and past
-- the clamp's reach for anyone who has been subscribed longer than a week.
-- ---------------------------------------------------------------------------

alter table public.user_subscriptions
  add column if not exists started_at timestamptz not null default now();

comment on column public.user_subscriptions.started_at is
  'When this subscription first began (never moved by a renewal). Clamps the '
  'rolling talk window during the first week — see talk_window_cap.';

update public.user_subscriptions
   set started_at = coalesce(current_period_start, updated_at, now())
 where started_at > coalesce(current_period_start, updated_at, now());

-- ---------------------------------------------------------------------------
-- Today's ceiling, with the window clamped to the age of the subscription.
--
-- The lookup is done here rather than passed in because every caller already
-- has to hand over the user id, and a start date that two call sites resolve
-- differently is the same drift the window model exists to avoid.
-- ---------------------------------------------------------------------------
create or replace function public.talk_window_cap(
  p_user_id uuid,
  p_daily   integer,
  p_days    integer
) returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_window integer := greatest(1, coalesce(p_days, 1));
  v_start  date;
  v_age    integer;
  v_used   bigint;
begin
  -- Oldest entitling subscription on file. Nil (no row) leaves the window at
  -- its full width, which is what a caller passing a plan's own number means.
  select min(started_at)::date into v_start
    from user_subscriptions
   where user_id = p_user_id
     and status in ('trialing', 'active', 'grace');

  if v_start is not null then
    v_age := greatest(1, (current_date - v_start) + 1);
    v_window := least(v_window, v_age);
  end if;

  select coalesce(sum(t.chars), 0) into v_used
    from tts_char_pool t
   where t.user_id = p_user_id
     -- Strictly BEFORE today: today's own usage is what this ceiling is
     -- compared against, not part of it.
     and t.day >= current_date - (v_window - 1)
     and t.day <  current_date
     -- The same two pools the cap is measured against, so a day counts as
     -- used by exactly what was billed to it.
     and t.action in ('talk_seconds', 'scene_seconds');

  return greatest(0, v_window * p_daily - v_used)::integer;
end;
$$;

revoke all on function public.talk_window_cap(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.talk_window_cap(uuid, integer, integer)
  to service_role;
