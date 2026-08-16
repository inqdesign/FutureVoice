-- The Core says when it started counting.
--
-- THE BUG THIS FIXES IS A LIE ON SCREEN, not a wrong number. Per-language
-- clubs (20260816120000) gave the Core its own activity ledger, which by
-- construction starts empty: talk recorded before it has no language and is
-- deliberately not attributed. So the day it shipped, every learner's club
-- screen read
--
--     Days met   0 / 28
--
-- over a thirty-day window in which twenty-nine days had never been measured
-- at all. To someone who had been talking daily that is not "you are at the
-- start of something", it is "the app didn't see any of it" — and the more
-- diligent they had been, the more wrong it looked. The number was right and
-- the sentence around it was false.
--
-- A rolling window cannot distinguish "you missed that day" from "nobody was
-- counting that day" on its own, because both are simply an absent row. So
-- the boundary has to be stored, and the client has to draw the two states
-- differently.
--
-- It lives on the config row rather than being derived (say, as the earliest
-- row in the ledger), because a derived value moves: the first learner to
-- talk in a brand-new language would make that language's history look like
-- it began the day THEY arrived, and everyone else's earlier days would
-- silently become "not counted". The date the machinery started is one fact
-- about the deployment, not a fact about whoever happens to be in the table.
--
-- Nothing about qualifying changes. Twenty-eight of the last thirty days
-- still means what it says, and it follows that the earliest possible seat is
-- `counting_since + entry_required_days - 1`. That date is worth SHOWING —
-- "the first seats can be taken on the 13th" is a thing to wait for, where
-- "0 / 28" is a thing to fail.

alter table public.core_club_config
  add column if not exists counting_since date;

-- 20260816120000 is when charge_talk_seconds began accepting a language.
-- Nothing was recorded before it: on 2026-08-17 no ledger row for `talk_time`
-- carried a language at all, so this is the true boundary rather than a
-- conservative guess.
update public.core_club_config
   set counting_since = date '2026-08-16',
       updated_at = now()
 where counting_since is null;

alter table public.core_club_config
  alter column counting_since set not null;

comment on column public.core_club_config.counting_since is
  'First day the Core could observe language-attributed talk. Days before it '
  'are UNMEASURED, not missed, and the UI must not draw them as failures.';

-- ---------------------------------------------------------------------------
-- The progress payload carries the boundary, and every day says whether it
-- was observable at all.
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
  if v_lang is null then
    raise exception 'p_language required';
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
           coalesce(a.talk_seconds, 0) >= c.daily_bar_seconds as met,
           s.day >= c.counting_since as counted
      from span s
      left join core_daily_activity a
        on a.user_id = v_uid and a.day = s.day
       and a.language = v_lang
  )
  select jsonb_agg(jsonb_build_object('day', day, 'seconds', seconds,
                                      'met', met, 'counted', counted)
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
   where m.user_id = v_uid and m.language = v_lang;

  -- SELECT INTO with no matching row sets its targets to NULL, not to their
  -- initialisers — so a learner who hasn't qualified leaves v_qualified NULL,
  -- `not v_qualified` evaluates to NULL, and the challenger countdown below
  -- silently never runs. Pin them back to booleans.
  v_qualified := coalesce(v_qualified, false);
  v_seated    := coalesce(v_seated, false);

  select count(*) into v_club from core_membership
   where seated and language = v_lang;

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
    'language',       v_lang,
    -- The boundary, plus the earliest date a seat could exist at all. A
    -- learner looking at an empty month needs a date to wait for, not a
    -- score to lose.
    'counting_since', c.counting_since,
    'first_seat_on',  c.counting_since + (c.entry_required_days - 1),
    'bar_seconds',    c.daily_bar_seconds,
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
