-- Remove what the streak rule left behind.
--
-- Two things stopped meaning anything when entry became "30 days in a row"
-- (20260817140000), and both were mine.
--
-- 1) THE ESTIMATED BACKFILL. 20260817120000 reconstructed pre-2026-08-10 talk
--    from TTS characters at 750 chars ≈ 1 min, and argued the estimate was
--    safe because it errs SHORT: "it can understate a day, never manufacture
--    one." That was true of "28 of the last 30 days", where one understated
--    day costs a thirtieth. Under a streak one understated day costs
--    everything, so the direction of harm inverted the moment the rule
--    changed.
--
--    It is not hypothetical. Of 54 estimated days, only 18 clear the 240 s
--    bar and 15 sit between 120 s and 239 s — just under, with an average of
--    209 s. Those fifteen are exactly where a conservative guess would have
--    broken a run that really happened.
--
--    And the estimates cannot help anyone anyway: the longest unbroken run in
--    the whole backfilled history is 3 days against an entry of 30. They are
--    invisible (the month grid they were restored for is gone), incapable of
--    qualifying anybody, and indistinguishable from measurement to a
--    pass/fail rule. Measured rows (2026-08-10 onward) stay.
--
-- 2) THE COUNTING BOUNDARY. `counting_since` / `first_seat_on` / the per-day
--    `counted` flag existed to stop a rolling window from drawing unmeasured
--    days as failures. The window is gone, the grid that drew it is gone, and
--    no client reads any of the three.
--
-- While here, the payload drops the rest of what nothing reads: `days` (a
-- thirty-object array rebuilt on every call), `met_entry`, `met_keep`,
-- `entry_required`, `entry_window`, `keep_required`, `keep_window`. They were
-- kept "for deployed clients", but no build containing the Core has ever
-- shipped — it is all unreleased on this branch — so those clients don't
-- exist. `v_flags` and `keep_window_days` stay: the days-to-entry projection
-- and the grace count still read them.

-- ---------------------------------------------------------------------------
-- 1) Guessed history goes. Measured history stays.
-- ---------------------------------------------------------------------------

delete from public.talk_seconds_by_language where estimated;

-- ---------------------------------------------------------------------------
-- 2) The boundary had one consumer and it was deleted.
-- ---------------------------------------------------------------------------

alter table public.core_club_config drop column if exists counting_since;

-- ---------------------------------------------------------------------------
-- 3) The payload, carrying only what is read.
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
  v_flags     boolean[];
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
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if v_lang is null then
    raise exception 'p_language required';
  end if;

  select * into c from core_club_config where id;


  v_streak := public.core_streak(v_uid, v_lang, v_today);
  v_missed := public.core_missed_recent(v_uid, v_lang, v_today);

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
    'bar_seconds',    c.daily_bar_seconds,
    'seats',          c.seats,
    'club_size',      v_club,
    'member',         v_member,
    -- The streak model, in three numbers.
    'streak',         v_streak,
    'entry_streak',   c.entry_streak_days,
    'missed_recent',  v_missed,
    'keep_grace',     c.keep_grace_days,
    'queue_ahead',    v_ahead,
    'days_to_entry',  v_to_entry,
    'days_to_return', v_to_return,
    'requalifying',   v_requal,
    -- Bar cleared, badge held, nothing to do but wait for a seat to open.
    'waiting_for_seat', v_qualified and not v_seated
                        and coalesce(v_to_return, -1) = 0);
end;
$$;
