-- The Core stops counting days and starts counting a STREAK.
--
-- WHAT CHANGES. Qualifying was "28 of the last 30 days" — a rolling window
-- with two absences built in. It is now "30 days in a row". Keeping a seat was
-- the same bar (20260815140000); it is now "don't break the streak, except one
-- missed day a month is forgiven".
--
-- WHY, given that 20260813120000 argues at length for rolling windows. That
-- argument was about FAILURE FEELING FINAL, and it is still right about that —
-- but it solved it in the arithmetic, where the learner cannot see it. What
-- actually reached the screen was "Days met 3 / 28" over thirty dots, and no
-- reading of that picture tells you what to do today. Two of the dots were
-- forgiven, which nothing on screen could say without teaching the window; the
-- rest were a scoreboard of a month the learner had mostly already spent. A
-- rolling window is a rule you have to be taught. A streak is a rule you
-- already know, and its instruction is the whole product's instruction: talk
-- today.
--
-- The humane part does not come from the arithmetic any more, it comes from
-- the two halves being asymmetric in a way a person can hold in their head:
--
--   * GETTING IN is unforgiving and happens once — 30 consecutive days. Break
--     it and the count restarts at zero. It is meant to be a real thing to
--     have done; that is the entire value of the badge, and softening it by
--     two days bought nothing that anyone could perceive.
--   * KEEPING A SEAT forgives one missed day per rolling 30. A cold, a
--     flight, a bad week — one of them is free. Two inside a month vacates
--     the seat, and the badge still survives it.
--
-- FINISHING THIRTY DAYS DOES NOT SEAT YOU. It never did — qualification puts
-- you in the queue and `settle_core_club_language` promotes in join_number
-- order into seats their holders vacated — but the old screen let "0 / 28"
-- read as a progress bar into the room. The payload now carries `queue_ahead`
-- so the client can say the true thing: you are in line, and this is how many
-- people are ahead of you.
--
-- ONE DEFINITION OF THE STREAK, called from both sides. `core_streak` is used
-- by the settlement AND by `core_my_progress`, so the number on the screen is
-- the number the promotion decision was made from. The club is small enough
-- that a per-user function call inside settlement costs nothing, and a
-- set-based copy of the same logic drifting from the client's copy is the one
-- bug in this feature nobody would ever report — they would just quietly stop
-- believing the screen.
--
-- The streak is anchored to TODAY IF TODAY IS ALREADY MET, otherwise to
-- yesterday: a streak is alive until the day it belongs to is over. Without
-- that, every learner's streak would read 0 every morning, and the nightly
-- settlement (00:05 UTC, `p_as_of` = the new day) would see nobody as
-- qualified at all.
--
-- NOBODY IS EVICTED BY THIS. `core_membership` was empty when it shipped, so
-- there is no grandfathering here and no phase-in. If it were not empty, this
-- migration would need one: members admitted under 28/30 have not been asked
-- for a streak and must not be released for failing a rule that did not exist
-- when they qualified.

-- ---------------------------------------------------------------------------
-- 1) Config. The old window columns stay — nothing reads them for a decision
--    any more, but deployed clients still decode `entry_required` /
--    `keep_required` from the payload, and dropping the columns would make
--    every one of them show a zero.
-- ---------------------------------------------------------------------------

alter table public.core_club_config
  add column if not exists entry_streak_days integer not null default 30,
  add column if not exists keep_grace_days   integer not null default 1;

update public.core_club_config
   set entry_streak_days = 30,
       keep_grace_days   = 1,
       -- The window the forgiveness is measured over: "one missed day a
       -- month". Held equal to the entry streak so the two numbers a learner
       -- reads are the same thirty.
       keep_window_days  = 30,
       -- Kept in step so an older client's "x / 30" still describes this rule
       -- rather than the one it was built against.
       entry_required_days = 30,
       keep_required_days  = 29,
       updated_at = now()
 where id;

comment on column public.core_club_config.entry_streak_days is
  'Consecutive days over the daily bar required to qualify. Breaking the '
  'streak restarts it at zero — there is no forgiveness on the way in.';
comment on column public.core_club_config.keep_grace_days is
  'Missed days forgiven inside keep_window_days for a SEATED member. Exceeding '
  'it vacates the seat; the badge is never revoked.';
comment on column public.core_club_config.entry_required_days is
  'Legacy. Superseded by entry_streak_days in 20260817140000; still emitted in '
  'core_my_progress so deployed clients decode something truthful.';
comment on column public.core_club_config.keep_required_days is
  'Legacy. Superseded by keep_grace_days in 20260817140000.';

-- ---------------------------------------------------------------------------
-- 2) The two measurements, as functions, so the screen and the settlement can
--    never disagree.
-- ---------------------------------------------------------------------------

-- Consecutive days over the daily bar, ending today (if today is already met)
-- or yesterday. Unbounded: a 200-day streak counts as 200, because a member
-- is shown this number and truncating it would be a lie in the one direction
-- that costs the most.
create or replace function public.core_streak(
  p_user_id  uuid,
  p_language text,
  p_as_of    date default (now() at time zone 'utc')::date
) returns integer
language sql
stable
security definer
set search_path = public
as $$
  with c as (
    select daily_bar_seconds from core_club_config where id
  ), anchor as (
    -- Alive until the day is over.
    select case when exists (
                  select 1 from core_daily_activity a, c
                   where a.user_id = p_user_id
                     and a.language = p_language
                     and a.day = p_as_of
                     and a.talk_seconds >= c.daily_bar_seconds)
                then p_as_of else p_as_of - 1
           end as day
  ), met as (
    select a.day,
           row_number() over (order by a.day desc) as rn
      from core_daily_activity a, c, anchor
     where a.user_id = p_user_id
       and a.language = p_language
       and a.talk_seconds >= c.daily_bar_seconds
       and a.day <= anchor.day
  )
  -- day = anchor - (rn - 1) holds for exactly the unbroken run at the top:
  -- once a gap is crossed every later row falls permanently behind its rank,
  -- and gaps only accumulate, so the equality can never come back.
  select coalesce(count(*), 0)::int
    from met, anchor
   where met.day = anchor.day - (met.rn - 1)::int;
$$;

revoke all on function public.core_streak(uuid, text, date) from public, anon, authenticated;

-- Missed days inside the keep window, counting only days that are OVER. Today
-- is not a missed day until midnight — otherwise every seated member would
-- spend each morning one row away from losing their seat.
create or replace function public.core_missed_recent(
  p_user_id  uuid,
  p_language text,
  p_as_of    date default (now() at time zone 'utc')::date
) returns integer
language sql
stable
security definer
set search_path = public
as $$
  select greatest(
    (select keep_window_days from core_club_config where id)
    - (select count(*)::int
         from core_daily_activity a
        where a.user_id = p_user_id
          and a.language = p_language
          and a.talk_seconds >= (select daily_bar_seconds from core_club_config where id)
          and a.day <  p_as_of
          and a.day >= p_as_of - (select keep_window_days from core_club_config where id)),
    0);
$$;

revoke all on function public.core_missed_recent(uuid, text, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Settlement, on the new bars.
--
--    The ORDER — qualify, release, promote — is reproduced exactly from
--    20260816120000 and must not be touched: releasing strictly before
--    promoting is what guarantees an arrival never displaces a sitting
--    member. Only the two predicates changed.
-- ---------------------------------------------------------------------------

create or replace function public.settle_core_club_language(
  p_as_of date,
  p_language text
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
  if p_language is null or p_language = '' then
    raise exception 'p_language required';
  end if;

  if exists (select 1 from core_settlement_log
              where day = p_as_of and language = p_language) then
    return jsonb_build_object('day', p_as_of, 'language', p_language,
                              'skipped', true);
  end if;

  select * into c from core_club_config where id;

  -- Candidates: anyone who talked recently enough to matter, plus every
  -- member (who must be judged even on a day they did nothing).
  drop table if exists _core_stats;
  create temporary table _core_stats on commit drop as
  select u.user_id,
         public.core_streak(u.user_id, p_language, p_as_of)         as streak,
         public.core_missed_recent(u.user_id, p_language, p_as_of)  as missed
    from (
      select user_id from core_daily_activity
       where language = p_language
         and day >  p_as_of - (c.entry_streak_days + 1)
         and day <= p_as_of
      union
      select user_id from core_membership where language = p_language
    ) u;

  -- (a) Qualify: thirty in a row. The badge is granted the moment it is done
  --     and never held back for a seat — the queue is a separate fact.
  drop table if exists _core_new;
  create temporary table _core_new on commit drop as
  with fresh as (
    select s.user_id
      from _core_stats s
     where s.streak >= c.entry_streak_days
       and not exists (select 1 from core_membership m
                        where m.user_id = s.user_id
                          and m.language = p_language)
     -- Same bar, same day: no honest way to rank them.
     order by s.user_id
  ), issued as (
    insert into core_membership (user_id, language, join_number)
    select user_id, p_language, nextval('core_join_number_seq') from fresh
    returning user_id, join_number
  )
  select * from issued;

  select count(*) into v_qualified from _core_new;

  -- (b) Release: more than the forgiven number of missed days. Still the ONLY
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
       and m.language = p_language
       and m.seated
       and s.missed > c.keep_grace_days
    returning m.user_id, m.join_number
  )
  select * from released;

  select count(*) into v_released from _core_out;

  -- (c) Promote, oldest qualification first, into whatever is now free.
  select count(*) into v_seated
    from core_membership where seated and language = p_language;
  v_free := greatest(c.seats - v_seated, 0);

  drop table if exists _core_in;
  create temporary table _core_in on commit drop as
  with eligible as (
    select m.user_id, (m.last_left_on is null) as first_time
      from core_membership m
      join _core_stats s on s.user_id = m.user_id
     where m.language = p_language
       and not m.seated
       and case
             when m.last_left_on is null
               or p_as_of - m.last_left_on <= c.requalify_after_days
             -- Waiting or recently away: hold the KEEP bar, which is what
             -- someone who just qualified holds by construction.
             then s.missed <= c.keep_grace_days
             -- Gone long enough that the month is asked for again.
             else s.streak >= c.entry_streak_days
           end
     order by m.join_number asc
     limit v_free
  ), promoted as (
    update core_membership m
       set seated = true,
           seated_since = p_as_of,
           updated_at = now()
      from eligible e
     where e.user_id = m.user_id
       and m.language = p_language
    returning m.user_id, m.join_number, e.first_time
  )
  select * from promoted;

  select count(*) into v_promoted from _core_in;

  -- (d) Tenure, after promotion, so a seat taken today counts today.
  update core_membership set days_total = days_total + 1
   where seated and language = p_language;

  select count(*) into v_seated
    from core_membership where seated and language = p_language;

  insert into core_events (kind, user_id, join_number, club_size, language)
  select 'left', user_id, join_number, v_seated, p_language from _core_out;

  insert into core_events (kind, user_id, join_number, club_size, language)
  select 'qualified', user_id, join_number, v_seated, p_language from _core_new;

  insert into core_events (kind, user_id, join_number, club_size, first_time, language)
  select 'seated', user_id, join_number, v_seated, first_time, p_language from _core_in;

  if v_seated >= c.seats
     and not exists (select 1 from core_events
                      where kind = 'club_full' and language = p_language) then
    insert into core_events (kind, club_size, language)
    values ('club_full', v_seated, p_language);
  end if;

  insert into core_settlement_log (day, language, qualified, promoted, released, seated_after)
  values (p_as_of, p_language, v_qualified, v_promoted, v_released, v_seated);

  return jsonb_build_object(
    'day', p_as_of, 'language', p_language, 'skipped', false,
    'qualified', v_qualified, 'promoted', v_promoted,
    'released', v_released, 'seated', v_seated, 'seats', c.seats);
end;
$$;

revoke all on function public.settle_core_club_language(date, text) from public, anon, authenticated;

-- The nightly entry point is unchanged except for the window it sweeps for
-- languages, which now follows the streak length.
create or replace function public.settle_core_club(
  p_as_of date default (now() at time zone 'utc')::date
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c        core_club_config%rowtype;
  v_lang   text;
  v_result jsonb;
  v_all    jsonb := '[]'::jsonb;
begin
  select * into c from core_club_config where id;

  for v_lang in
    select language from core_daily_activity
     where day > p_as_of - (c.entry_streak_days + 1) and day <= p_as_of
    union
    select language from core_membership
    order by 1
  loop
    v_result := public.settle_core_club_language(p_as_of, v_lang);
    v_all := v_all || jsonb_build_array(v_result);
  end loop;

  return jsonb_build_object('day', p_as_of, 'languages', v_all);
end;
$$;

revoke all on function public.settle_core_club(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) What the screen reads.
--
--    Two thirds of the old body was a search for "how many more days until a
--    rolling count clears its bar", which a streak answers by subtraction. The
--    per-day array survives ONLY for clients already in the wild that draw a
--    month grid from it; nothing here decides anything from it, and the next
--    build stops reading it.
-- ---------------------------------------------------------------------------

create or replace function public.core_my_progress(p_language text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c           core_club_config%rowtype;
  v_uid       uuid := auth.uid();
  v_lang      text := nullif(lower(trim(coalesce(p_language, ''))), '');
  v_today     date := (now() at time zone 'utc')::date;
  v_days      jsonb;
  v_flags     boolean[];
  v_met_entry integer := 0;
  v_met_keep  integer := 0;
  v_member    jsonb;
  v_join      integer;
  v_qualified boolean := false;
  v_seated    boolean := false;
  v_last_left date;
  v_club      integer;
  v_streak    integer := 0;
  v_missed    integer := 0;
  v_to_entry  integer;
  v_to_return integer;
  v_requal    boolean := false;
  v_ahead     integer;
  v_len       integer;
  v_gap       integer;
  v_start     date;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if v_lang is null then
    raise exception 'p_language required';
  end if;

  select * into c from core_club_config where id;

  select greatest(c.counting_since, u.created_at::date) into v_start
    from auth.users u where u.id = v_uid;
  v_start := coalesce(v_start, c.counting_since);

  v_streak := public.core_streak(v_uid, v_lang, v_today);
  v_missed := public.core_missed_recent(v_uid, v_lang, v_today);

  -- The month, for clients that still draw it. Integer offsets, not
  -- generate_series over dates: the date arguments would resolve to the
  -- timestamptz overload and cast back through the session timezone, which
  -- can land a day either side of the UTC day the settlement uses.
  with span as (
    select v_today - g as day
      from generate_series(0, c.keep_window_days - 1) g
  ), joined as (
    select s.day,
           coalesce(a.talk_seconds, 0)::bigint as seconds,
           coalesce(a.talk_seconds, 0) >= c.daily_bar_seconds as met,
           s.day >= v_start as counted
      from span s
      left join core_daily_activity a
        on a.user_id = v_uid and a.day = s.day
       and a.language = v_lang
  )
  select jsonb_agg(jsonb_build_object('day', day, 'seconds', seconds,
                                      'met', met, 'counted', counted)
                   order by day),
         count(*) filter (where met)::int,
         count(*) filter (where met)::int
    into v_days, v_met_entry, v_met_keep
    from joined;

  -- The keep window as an array, oldest first, ENDING YESTERDAY — exactly the
  -- days `core_missed_recent` counts. Today is deliberately absent: it is not
  -- a missed day until it is over, and including it would make the roll-out
  -- arithmetic below disagree with the number beside it on screen.
  with span as (
    select v_today - g as day
      from generate_series(1, c.keep_window_days) g
  )
  select array_agg(coalesce(a.talk_seconds, 0) >= c.daily_bar_seconds
                   order by s.day)
    into v_flags
    from span s
    left join core_daily_activity a
      on a.user_id = v_uid and a.day = s.day
     and a.language = v_lang;

  select true, m.seated, m.last_left_on, m.join_number,
         jsonb_build_object('seated', m.seated,
                            'days_total', m.days_total,
                            'qualified_at', m.qualified_at)
    into v_qualified, v_seated, v_last_left, v_join, v_member
    from core_membership m
   where m.user_id = v_uid and m.language = v_lang;

  -- SELECT INTO with no matching row sets its targets to NULL, not to their
  -- initialisers — so a learner who hasn't qualified leaves v_qualified NULL,
  -- `not v_qualified` evaluates to NULL, and the countdown below silently
  -- never runs. Pin them back to booleans.
  v_qualified := coalesce(v_qualified, false);
  v_seated    := coalesce(v_seated, false);

  select count(*) into v_club from core_membership
   where seated and language = v_lang;

  -- Days to qualify is now subtraction. A broken streak is a 30 again, and
  -- the client says so in words rather than making the number mean it.
  if not v_qualified then
    v_to_entry := greatest(c.entry_streak_days - v_streak, 0);
  end if;

  -- How many qualified people are ahead in this language's line. Counts
  -- everyone with a lower join_number who is not seated, including anyone
  -- currently below the keep bar: they are still ahead in the queue and can
  -- be back over the bar tomorrow, so leaving them out would promise a seat
  -- sooner than the settlement will actually give one.
  if v_qualified and not v_seated then
    select count(*) into v_ahead
      from core_membership m
     where m.language = v_lang and not m.seated and m.join_number < v_join;
  end if;

  -- Days until a seatless member is over the keep bar again: how long the
  -- excess missed days take to roll out of the window, assuming every day
  -- from here is met. Past requalify_after_days it is the full streak again.
  if v_qualified and not v_seated then
    v_requal := v_last_left is not null
                and (v_today - v_last_left) > c.requalify_after_days;
    if v_requal then
      v_to_return := greatest(c.entry_streak_days - v_streak, 0);
    else
      v_len := coalesce(array_length(v_flags, 1), 0);
      v_to_return := c.keep_window_days;
      for k in 0..c.keep_window_days loop
        -- The window k days from now holds the last (keep_window - k) days of
        -- history plus k days assumed met. `v_flags` ends at yesterday and is
        -- oldest-first, so those are exactly the entries from k+1 onward, and
        -- k = 0 reproduces `missed_recent`.
        v_gap := 0;
        if k < v_len then
          select count(*) into v_gap
            from unnest(v_flags[k + 1:v_len]) f
           where not f;
        end if;
        if v_gap <= c.keep_grace_days then
          v_to_return := k;
          exit;
        end if;
      end loop;
    end if;
  end if;

  return jsonb_build_object(
    'language',       v_lang,
    'counting_since', v_start,
    'bar_seconds',    c.daily_bar_seconds,
    'seats',          c.seats,
    'club_size',      v_club,
    'member',         v_member,
    -- The streak model, in three numbers.
    'streak',         v_streak,
    'entry_streak',   c.entry_streak_days,
    'missed_recent',  v_missed,
    'keep_grace',     c.keep_grace_days,
    'keep_window',    c.keep_window_days,
    'queue_ahead',    v_ahead,
    'days_to_entry',  v_to_entry,
    'days_to_return', v_to_return,
    'requalifying',   v_requal,
    -- Bar cleared, badge held, nothing to do but wait for a seat to open.
    'waiting_for_seat', v_qualified and not v_seated
                        and coalesce(v_to_return, -1) = 0,
    -- Deployed clients only, all of it. Nothing above is derived from these.
    'days',           coalesce(v_days, '[]'::jsonb),
    'met_entry',      v_met_entry,
    'entry_required', c.entry_required_days,
    'entry_window',   c.entry_streak_days,
    'met_keep',       v_met_keep,
    'keep_required',  c.keep_required_days,
    'first_seat_on',  case
                        when v_to_entry is not null and v_to_entry > 0
                        then v_today + v_to_entry
                      end);
end;
$$;

grant execute on function public.core_my_progress(text) to authenticated;
