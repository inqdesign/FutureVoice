-- The Core — a 100-seat club of learners who actually speak every day.
--
-- WHY THIS SHAPE (read before changing any number):
--
-- The goal is to MAINTAIN a core, not to run a contest. A zero-sum
-- leaderboard would evict somebody every week by construction, which is the
-- opposite of maintenance. So membership is a BAR, not a rank, and the two
-- halves of it are deliberately asymmetric:
--
--   * QUALIFYING is hard and happens once — 28 of the last 30 days. It is a
--     filter, and the badge it grants is PERMANENT. Nobody ever takes it
--     back. `core_membership.qualified_at` + `join_number` are the stock.
--   * KEEPING A SEAT is loose and repeats weekly — 5 of the last 7 days.
--     Missing a day costs nothing; missing three in a week releases the
--     seat. A seat is never taken by a newcomer — it is only ever VACATED
--     by its holder. Newcomers wait for a vacancy (and if qualified people
--     pile up waiting, that is the signal to raise the keep bar, not to
--     evict anyone).
--
-- Badge (qualification) and seat (membership) are therefore separate facts,
-- and the UI shows both in one glyph: filled seal = seated, outlined seal =
-- qualified but currently without a seat. Losing a seat is dormancy, not a
-- scar.
--
-- THE DAILY BAR IS DELIBERATELY BELOW THE CHEAPEST PLAN'S ALLOWANCE.
-- Daily (`daily_*`) buys 300 s/day. If the bar were 300 s, only Unlimited
-- subscribers could ever clear it — the reward would be unreachable for
-- exactly the people it is worth something to — and there would be no slack:
-- a call that ends at 4 min 52 s would fail the day, and at 28/30 a couple of
-- near misses lose the month. Never raise `daily_bar_seconds` to or above the
-- Daily tier's `daily_seconds`.
--
-- The value itself moved to 240 s in 20260814110000, once Watch stopped
-- sharing the talk pool; read that file before touching this number, and note
-- that it is still derived from the plan's shape rather than from measured
-- behaviour.
--
-- THE REWARD IS A DAILY ALLOWANCE BUMP, NOT A BALANCE GRANT. Seated members
-- get `bonus_seconds` added to their per-day cap in `consume_metered_seconds`
-- for as long as they hold the seat. It does not accumulate, so there is no
-- growing liability and no bank of thousands of unspent minutes to be cashed
-- at once. Entitled subscribers only: crediting a non-subscriber's balance
-- would re-create the free tier the hard paywall (20260811180000) removed.
--
-- ROLLING WINDOWS, NOT STREAKS. A missed day pushes qualification back by a
-- day; it never resets progress to zero. That is what makes 28/30 humane.
--
-- Activity is measured from `tts_char_pool` rows tagged 'talk_seconds' (the
-- column is named `chars` for credit-era reasons; for this action it holds
-- SECONDS). Watch is excluded on purpose and stays excluded: scene playback
-- is listening, not speaking, and the Core is about speaking. Since
-- 20260814100000 scenes land in 'scene_seconds' (legacy clients) or
-- 'scene_counted' (current ones) — neither is read here, so no amount of
-- watching can move anyone toward a seat. Upgrade path: when the client starts reporting per-turn utterance
-- seconds, point `core_daily_activity` at that instead — nothing else here
-- needs to change.

-- ---------------------------------------------------------------------------
-- 1) Config — one row, so the bars can be tuned without a migration.
-- ---------------------------------------------------------------------------

create table if not exists public.core_club_config (
  id                     boolean primary key default true check (id),
  seats                  integer not null default 100,
  -- Daily bar: seconds of talk that make a day "met". Must stay below the
  -- Daily tier's daily_seconds (see header). Raised 180 → 240 in
  -- 20260814110000; kept in step here so a fresh database starts where
  -- production already is.
  daily_bar_seconds      integer not null default 240,
  -- Qualifying (once): met days required inside the entry window.
  entry_window_days      integer not null default 30,
  entry_required_days    integer not null default 28,
  -- Keeping a seat (weekly): met days required inside the keep window.
  keep_window_days       integer not null default 7,
  keep_required_days     integer not null default 5,
  -- A member who has been seatless this long must earn the month again.
  requalify_after_days   integer not null default 90,
  -- A recently-departed member outranks a first-timer for a vacancy.
  return_priority_days   integer not null default 14,
  -- Added to the seated member's daily cap. Expires with the day.
  bonus_seconds          integer not null default 180,
  updated_at             timestamptz not null default now()
);

insert into public.core_club_config (id) values (true) on conflict (id) do nothing;

alter table public.core_club_config enable row level security;
drop policy if exists "core_club_config: read" on public.core_club_config;
create policy "core_club_config: read" on public.core_club_config
  for select using (true);

-- ---------------------------------------------------------------------------
-- 2) Membership. join_number is issued once and NEVER reused — it is the
--    person's number, not the seat's index. #3 stays #3 forever, and the
--    next arrival takes the next number, not the vacated one. Low numbers
--    are the founding story; no separate "founding" flag is needed.
-- ---------------------------------------------------------------------------

create sequence if not exists public.core_join_number_seq as integer start 1;

create table if not exists public.core_membership (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  join_number   integer not null unique,
  -- The badge. Permanent, never revoked.
  qualified_at  timestamptz not null default now(),
  seated        boolean not null default false,
  seated_since  date,
  last_left_on  date,
  -- Cumulative days seated, across every stint. Survives losing the seat.
  days_total    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists core_membership_seated_idx
  on public.core_membership(seated) where seated;

alter table public.core_membership enable row level security;

-- Own row only: last_left_on / days_total are nobody else's business.
-- The badge facts other learners need are exposed by core_badges below.
drop policy if exists "core_membership: read own" on public.core_membership;
create policy "core_membership: read own" on public.core_membership
  for select using (auth.uid() = user_id);

-- What strangers see next to a name in Find people: the seal and the number.
-- Nothing about lapses, nothing about how much anyone talks.
create or replace view public.core_badges as
  select user_id, join_number, seated
    from public.core_membership;

grant select on public.core_badges to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Arrivals worth announcing. The club counter is the emotional payload,
--    so every event carries it. Read by everyone: watching the roster fill
--    is the point.
-- ---------------------------------------------------------------------------

create table if not exists public.core_events (
  id          bigserial primary key,
  kind        text not null check (kind in ('qualified', 'seated', 'left', 'club_full')),
  user_id     uuid references auth.users(id) on delete set null,
  join_number integer,
  club_size   integer not null,
  -- 'seated' only: true when this is the person's first ever seat. A first
  -- arrival is announced; a returning member slipping back in is not.
  first_time  boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists core_events_created_idx
  on public.core_events(created_at desc);

alter table public.core_events enable row level security;
drop policy if exists "core_events: read" on public.core_events;
drop policy if exists "core_events: read arrivals" on public.core_events;
-- Arrivals are public; DEPARTURES ARE NOT. Nobody gets to see who lost a
-- seat, and nobody gets to work out whose seat they took — that is how a
-- club turns into a scoreboard people resent. 'left' rows exist only so the
-- settlement is auditable by the service role.
create policy "core_events: read arrivals" on public.core_events
  for select using (kind <> 'left');

-- ---------------------------------------------------------------------------
-- 4) Activity. `chars` holds seconds for the 'talk_seconds' action.
-- ---------------------------------------------------------------------------

create or replace view public.core_daily_activity as
  select user_id, day, sum(chars)::bigint as talk_seconds
    from public.tts_char_pool
   where action = 'talk_seconds'
   group by user_id, day;

-- tts_char_pool is RLS-locked with no policies, but a view runs as its owner
-- and Supabase's default privileges hand new objects in `public` to anon and
-- authenticated. Without this revoke, every learner's daily talk time would
-- be readable by any client. Settlement reaches it through SECURITY DEFINER.
revoke all on public.core_daily_activity from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) Settlement log — one row per settled day, so a re-run is a no-op and
--    days_total can never be double-counted.
-- ---------------------------------------------------------------------------

create table if not exists public.core_settlement_log (
  day          date primary key,
  qualified    integer not null default 0,
  promoted     integer not null default 0,
  released     integer not null default 0,
  seated_after integer not null default 0,
  settled_at   timestamptz not null default now()
);

alter table public.core_settlement_log enable row level security;
-- Service role only; no client policies on purpose.

-- ---------------------------------------------------------------------------
-- 6) Settlement. Runs once a day at 00:00 UTC — the SAME clock the daily
--    allowance resets on (20260811160000). Two clocks would mean two
--    different "todays" and an unanswerable support question.
--
--    Order matters: qualify → release → promote. Releasing before promoting
--    is what guarantees a newcomer never displaces a sitting member; they
--    can only ever fill a seat its holder already vacated.
-- ---------------------------------------------------------------------------

create or replace function public.settle_core_club(
  p_as_of date default (now() at time zone 'utc')::date
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c           core_club_config%rowtype;
  v_qualified integer := 0;
  v_promoted  integer := 0;
  v_released  integer := 0;
  v_seated    integer := 0;
  v_free      integer := 0;
begin
  -- Idempotent per day: a re-run must not double-count days_total.
  if exists (select 1 from core_settlement_log where day = p_as_of) then
    return jsonb_build_object('day', p_as_of, 'skipped', true);
  end if;

  select * into c from core_club_config where id;

  drop table if exists _core_stats;
  create temporary table _core_stats on commit drop as
  with act as (
    select user_id, day, talk_seconds
      from core_daily_activity
     where day > p_as_of - c.entry_window_days
       and day <= p_as_of
  )
  select u.user_id,
         count(*) filter (
           where a.talk_seconds >= c.daily_bar_seconds
         )::int as met_entry,
         count(*) filter (
           where a.talk_seconds >= c.daily_bar_seconds
             and a.day > p_as_of - c.keep_window_days
         )::int as met_keep
    from (select user_id from act
          union
          select user_id from core_membership) u
    left join act a on a.user_id = u.user_id
   group by u.user_id;

  -- (a) Qualify. The badge is granted the moment the month is done — it is
  --     never held back waiting for a seat or for the club to fill. Numbers
  --     come off a sequence and are never reused.
  drop table if exists _core_new;
  create temporary table _core_new on commit drop as
  with fresh as (
    select s.user_id
      from _core_stats s
     where s.met_entry >= c.entry_required_days
       and not exists (select 1 from core_membership m where m.user_id = s.user_id)
     order by s.met_entry desc, s.met_keep desc, s.user_id
  ), issued as (
    insert into core_membership (user_id, join_number)
    select user_id, nextval('core_join_number_seq') from fresh
    returning user_id, join_number
  )
  select * from issued;

  select count(*) into v_qualified from _core_new;

  -- (b) Release. Below the keep bar → the seat is vacated. This is the ONLY
  --     way a seat opens.
  drop table if exists _core_out;
  create temporary table _core_out on commit drop as
  with released as (
    update core_membership m
       set seated = false,
           seated_since = null,
           last_left_on = p_as_of,
           updated_at = now()
      from _core_stats s
     where s.user_id = m.user_id
       and m.seated
       and s.met_keep < c.keep_required_days
    returning m.user_id, m.join_number
  )
  select * from released;

  select count(*) into v_released from _core_out;

  -- (c) Promote into whatever is now free. Recently departed members outrank
  --     first-timers (the door back must be easier than the door in), then
  --     recent consistency, then seniority by join number.
  select count(*) into v_seated from core_membership where seated;
  v_free := greatest(c.seats - v_seated, 0);

  drop table if exists _core_in;
  create temporary table _core_in on commit drop as
  with eligible as (
    -- Never seated before → this will be their first seat.
    select m.user_id, (m.last_left_on is null) as first_time
      from core_membership m
      join _core_stats s on s.user_id = m.user_id
     where not m.seated
       and case
             when m.last_left_on is null
               or p_as_of - m.last_left_on <= c.requalify_after_days
             then s.met_keep >= c.keep_required_days
             -- Gone long enough that the month has to be earned again.
             else s.met_entry >= c.entry_required_days
           end
     order by (m.last_left_on is not null
               and p_as_of - m.last_left_on <= c.return_priority_days) desc,
              s.met_keep desc, s.met_entry desc, m.join_number asc
     limit v_free
  ), promoted as (
    update core_membership m
       set seated = true,
           seated_since = p_as_of,
           updated_at = now()
      from eligible e
     where e.user_id = m.user_id
    returning m.user_id, m.join_number, e.first_time
  )
  select * from promoted;

  select count(*) into v_promoted from _core_in;

  -- (d) Tenure. Counted after promotion, so a seat taken today counts today.
  --     days_total is stock: it survives every later departure.
  update core_membership set days_total = days_total + 1 where seated;

  select count(*) into v_seated from core_membership where seated;

  -- (e) Events, all stamped with the FINAL club size — the counter is the
  --     emotional payload of the announcement, so it must be the number a
  --     member would see if they opened the app right then.
  insert into core_events (kind, user_id, join_number, club_size)
  select 'left', user_id, join_number, v_seated from _core_out;

  insert into core_events (kind, user_id, join_number, club_size)
  select 'qualified', user_id, join_number, v_seated from _core_new;

  insert into core_events (kind, user_id, join_number, club_size, first_time)
  select 'seated', user_id, join_number, v_seated, first_time from _core_in;

  -- Fires once, ever.
  if v_seated >= c.seats
     and not exists (select 1 from core_events where kind = 'club_full') then
    insert into core_events (kind, club_size) values ('club_full', v_seated);
  end if;

  insert into core_settlement_log (day, qualified, promoted, released, seated_after)
  values (p_as_of, v_qualified, v_promoted, v_released, v_seated);

  return jsonb_build_object(
    'day', p_as_of, 'skipped', false,
    'qualified', v_qualified, 'promoted', v_promoted,
    'released', v_released, 'seated', v_seated, 'seats', c.seats);
end;
$$;

revoke all on function public.settle_core_club(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7) The reward: extra seconds on TODAY's cap, for as long as the seat is
--    held. Never written to a balance — see the header.
-- ---------------------------------------------------------------------------

create or replace function public.core_bonus_seconds(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select c.bonus_seconds
       from core_membership m
       join core_club_config c on c.id
      where m.user_id = p_user_id and m.seated),
    0);
$$;

revoke all on function public.core_bonus_seconds(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8) Metering, re-stated from 20260811180000 with ONE change: a seated core
--    member's daily cap is raised by core_bonus_seconds for the day. Nothing
--    is written to user_credits.balance, so the bonus cannot accumulate into
--    a liability and cannot be spent by a non-subscriber (the hard paywall
--    stays hard). Everything else in this function is unchanged — if you
--    edit the metering rules, edit this copy.
-- ---------------------------------------------------------------------------

create or replace function public.consume_metered_seconds(
  p_user_id uuid,
  p_seconds integer,
  p_pool text,                  -- 'talk_seconds' | 'scene_seconds'
  p_action text,                -- ledger action tag ('talk_time', 'tts_scene', …)
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   bigint;
  v_cap     integer;
  v_bonus   integer := 0;
  v_trial   boolean := false;
  v_balance integer;
begin
  if p_seconds < 0 or p_seconds > 3600 then
    raise exception 'p_seconds out of range';
  end if;
  if p_pool not in ('talk_seconds', 'scene_seconds') then
    raise exception 'unsupported pool %', p_pool;
  end if;

  -- Idempotency: a retried key must neither re-accumulate nor re-charge.
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_balance from user_credits where user_id = p_user_id;
    select coalesce(sum(chars), 0) into v_today from tts_char_pool
     where user_id = p_user_id and day = current_date
       and action in ('talk_seconds', 'scene_seconds');
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today);
  end if;

  if p_seconds > 0 then
    insert into tts_char_pool (user_id, day, action, chars)
    values (p_user_id, current_date, p_pool, p_seconds)
    on conflict (user_id, day, action) do update
      set chars = tts_char_pool.chars + excluded.chars,
          updated_at = now();
  end if;

  select coalesce(sum(chars), 0) into v_today from tts_char_pool
   where user_id = p_user_id and day = current_date
     and action in ('talk_seconds', 'scene_seconds');

  -- Entitled subscriber: the plan's daily allowance covers it, balance
  -- untouched. A TRIAL is metered at the Daily tier's allowance regardless of
  -- which plan is being trialed. Past the cap → raise (rolls back this call's
  -- accumulation).
  select s.status = 'trialing',
         case when s.status = 'trialing'
              then coalesce((select min(daily_seconds) from subscription_plans
                              where tier = 'daily'), p.daily_seconds)
              else p.daily_seconds end
    into v_trial, v_cap
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = p_user_id
     and s.status in ('trialing', 'active', 'grace');

  if v_cap is not null then
    -- The Core's reward, spendable today and only today.
    v_bonus := public.core_bonus_seconds(p_user_id);
    v_cap := v_cap + v_bonus;

    if v_today > v_cap then
      raise exception 'DAILY_CAP_REACHED' using errcode = 'P0005';
    end if;
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (p_user_id, 'debit', 0, p_action, p_source_fn, p_idempotency_key,
            coalesce(p_metadata, '{}'::jsonb)
              || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                                    'core_bonus', v_bonus,
                                    'covered_by', case when v_trial then 'trial' else 'plan' end));
    select balance into v_balance from user_credits where user_id = p_user_id;
    return jsonb_build_object('balance', coalesce(v_balance, 0), 'charged', 0,
                              'seconds_today', v_today, 'daily_cap', v_cap,
                              'core_bonus', v_bonus,
                              'covered_by', case when v_trial then 'trial' else 'plan' end);
  end if;

  -- No entitlement: debit the seconds balance. For a new signup that balance
  -- is 0, so this raises INSUFFICIENT_CREDITS → 402 → paywall. The core bonus
  -- deliberately does NOT apply here.
  v_balance := public.charge_credits(
    p_user_id => p_user_id,
    p_credits => p_seconds,
    p_action  => p_action,
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('seconds', p_seconds, 'seconds_today', v_today,
                            'covered_by', 'balance'));
  return jsonb_build_object('balance', v_balance, 'charged', p_seconds,
                            'seconds_today', v_today, 'covered_by', 'balance');
end;
$$;

-- ---------------------------------------------------------------------------
-- 9) Schedule. pg_cron if the extension is available; otherwise call
--    settle_core_club() from a scheduled edge function. Either way the
--    function is idempotent per day, so a double trigger is harmless.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule('settle_core_club')
      where exists (select 1 from cron.job where jobname = 'settle_core_club');
    perform cron.schedule('settle_core_club', '5 0 * * *',
                          $cron$select public.settle_core_club();$cron$);
  end if;
exception when others then
  -- Scheduling is best-effort; the settlement function stands on its own.
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 10) The caller's own progress, in one round trip.
--
--     core_daily_activity is revoked from clients (it would expose everyone's
--     talk time), so this is the only way in — and it only ever reads
--     auth.uid()'s own rows.
--
--     It returns a DISTANCE, never a verdict. "6 days to go" is the entire
--     point of the challenger screen: a rolling window means a missed day
--     defers entry by a day instead of resetting a streak to zero, and a
--     learner can only feel that if the number in front of them moves by one.
--     The projection assumes every remaining day is met — it is the best
--     case, which is the only honest thing to promise.
-- ---------------------------------------------------------------------------

create or replace function public.core_my_progress()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c           core_club_config%rowtype;
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'utc')::date;
  v_days      jsonb;
  v_flags     boolean[];
  v_met_entry integer := 0;
  v_met_keep  integer := 0;
  v_member    jsonb;
  v_qualified boolean := false;
  v_seated    boolean := false;
  v_last_left date;
  v_club      integer;
  v_to_entry  integer;
  v_to_return integer;
  v_requal    boolean := false;
  v_len       integer;
  v_past      integer;
  v_remain    integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into c from core_club_config where id;

  -- Every day in the entry window, gaps filled with zero, so the client can
  -- draw the whole month without inventing dates.
  -- Integer offsets, not generate_series over dates: the date arguments
  -- would resolve to the timestamptz overload and cast back through the
  -- session timezone, which can land a day either side of the UTC day the
  -- settlement uses.
  with span as (
    select v_today - g as day
      from generate_series(0, c.entry_window_days - 1) g
  ), joined as (
    select s.day,
           coalesce(a.talk_seconds, 0)::bigint as seconds,
           coalesce(a.talk_seconds, 0) >= c.daily_bar_seconds as met
      from span s
      left join core_daily_activity a
        on a.user_id = v_uid and a.day = s.day
  )
  select jsonb_agg(jsonb_build_object('day', day, 'seconds', seconds, 'met', met)
                   order by day),
         count(*) filter (where met)::int,
         count(*) filter (where met and day > v_today - c.keep_window_days)::int,
         array_agg(met order by day)
    into v_days, v_met_entry, v_met_keep, v_flags
    from joined;

  select true, m.seated, m.last_left_on,
         jsonb_build_object('join_number', m.join_number,
                            'seated', m.seated,
                            'days_total', m.days_total,
                            'qualified_at', m.qualified_at)
    into v_qualified, v_seated, v_last_left, v_member
    from core_membership m
   where m.user_id = v_uid;

  -- SELECT INTO with no matching row sets its targets to NULL, not to their
  -- initialisers — so a learner who hasn't qualified leaves v_qualified NULL,
  -- `not v_qualified` evaluates to NULL, and the challenger countdown below
  -- silently never runs. Pin them back to booleans.
  v_qualified := coalesce(v_qualified, false);
  v_seated    := coalesce(v_seated, false);

  select count(*) into v_club from core_membership where seated;

  v_len := coalesce(array_length(v_flags, 1), 0);

  -- Days until the entry bar, assuming every day from here is met. Met days
  -- already banked stay banked only while they sit inside the rolling
  -- window, which is why the count shrinks as `k` grows.
  if not v_qualified then
    for k in 0..c.entry_window_days loop
      v_remain := c.entry_window_days - k;
      v_past := 0;
      if v_remain > 0 and v_len > 0 then
        select count(*) into v_past
          from unnest(v_flags[greatest(v_len - v_remain + 1, 1):v_len]) f
         where f;
      end if;
      if v_past + k >= c.entry_required_days then
        v_to_entry := k;
        exit;
      end if;
    end loop;
  end if;

  -- Days until a seatless member is eligible again. A short absence is
  -- measured against the KEEP bar — the month is asked of a first-timer, not
  -- of someone who already proved it. Past requalify_after_days it is the
  -- month again.
  if v_qualified and not v_seated then
    v_requal := v_last_left is not null
                and (v_today - v_last_left) > c.requalify_after_days;
    if v_requal then
      v_to_return := v_to_entry;
      for k in 0..c.entry_window_days loop
        v_remain := c.entry_window_days - k;
        v_past := 0;
        if v_remain > 0 and v_len > 0 then
          select count(*) into v_past
            from unnest(v_flags[greatest(v_len - v_remain + 1, 1):v_len]) f
           where f;
        end if;
        if v_past + k >= c.entry_required_days then
          v_to_return := k;
          exit;
        end if;
      end loop;
    else
      for k in 0..c.keep_window_days loop
        v_remain := c.keep_window_days - k;
        v_past := 0;
        if v_remain > 0 and v_len > 0 then
          select count(*) into v_past
            from unnest(v_flags[greatest(v_len - v_remain + 1, 1):v_len]) f
           where f;
        end if;
        if v_past + k >= c.keep_required_days then
          v_to_return := k;
          exit;
        end if;
      end loop;
    end if;
  end if;

  return jsonb_build_object(
    'bar_seconds',    c.daily_bar_seconds,
    'bonus_seconds',  c.bonus_seconds,
    'seats',          c.seats,
    'club_size',      v_club,
    'member',         v_member,
    'days',           coalesce(v_days, '[]'::jsonb),
    'met_entry',      v_met_entry,
    'entry_required', c.entry_required_days,
    'entry_window',   c.entry_window_days,
    'met_keep',       v_met_keep,
    'keep_required',  c.keep_required_days,
    'keep_window',    c.keep_window_days,
    'days_to_entry',  v_to_entry,
    'days_to_return', v_to_return,
    'requalifying',   v_requal,
    -- Bar cleared, badge held, nothing to do but wait for someone to vacate.
    'waiting_for_seat', v_qualified and not v_seated
                        and coalesce(v_to_return, -1) = 0 and v_club >= c.seats);
end;
$$;

grant execute on function public.core_my_progress() to authenticated;
