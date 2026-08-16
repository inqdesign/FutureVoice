-- Give the Core back the days people actually practised.
--
-- THE BUG IS THAT REAL DAYS READ AS ZERO. The club's own ledger
-- (`talk_seconds_by_language`) only started receiving rows when
-- `charge_talk_seconds` learned about languages on 2026-08-16. Everything
-- before that was dropped on the floor, so a learner who had been talking for
-- weeks opened the screen and saw an empty month. Nothing about that boundary
-- was real: it was the date of a migration, not the date anything happened.
--
-- There are three eras of evidence, and only the middle boundary is genuine:
--
--   2026-06-10 → 07-29   Conversations exist. TTS characters were the meter,
--                        and the rows carry no `purpose`, so conversation and
--                        review sit in one bucket.
--   2026-07-30 → 08-09   Same, but rows are tagged, so `purpose = 'turn'`
--                        isolates actual conversation.
--   2026-08-10 →         Wall-clock call seconds are measured directly
--                        (`tts_char_pool.talk_seconds`) — the minutes model.
--
-- So: 08-10 onward is copied as MEASURED. Everything earlier is ESTIMATED
-- from characters at 750 chars ≈ 1 minute — the same rate the server already
-- trusts as its anti-under-reporting floor in `charge_tts_floored`. That rate
-- counts only the fluent self's spoken output, while a call also contains the
-- learner talking and thinking, so the estimate lands BELOW the real call
-- length. Erring short is the right direction: it can understate a day, never
-- manufacture one.
--
-- Rows are marked `estimated` and keep their source, so this is auditable and
-- reversible — delete where estimated and the club falls back to measurement
-- alone.
--
-- LANGUAGE comes from `profiles.target_language`. For an account with one
-- target language that is not a guess, it is the only possibility. Accounts
-- with no target language on file are skipped rather than assigned one.
--
-- CONSEQUENCE TO WATCH: the qualifying window is the last 30 days and it is
-- rolling, so these days are inside it right now. A learner whose backfilled
-- history clears 28 of 30 can therefore be seated at the very next
-- settlement, off partly-estimated evidence. That is a deliberate trade —
-- the alternative is telling someone the month they spent talking never
-- happened — but it is the reason the estimate is conservative and labelled.

alter table public.talk_seconds_by_language
  add column if not exists estimated boolean not null default false,
  add column if not exists source text;

comment on column public.talk_seconds_by_language.estimated is
  'True when the seconds were derived from TTS characters rather than a '
  'measured call clock (pre-2026-08-10). Conservative by construction.';

-- ---------------------------------------------------------------------------
-- 1) Measured: the minutes model's own per-day totals, 2026-08-10 onward.
-- ---------------------------------------------------------------------------

insert into public.talk_seconds_by_language (user_id, day, language, seconds, estimated, source)
select p.user_id,
       p.day,
       lower(pr.target_language),
       p.chars,
       false,
       'talk_seconds'
  from public.tts_char_pool p
  join public.profiles pr on pr.id = p.user_id
 where p.action = 'talk_seconds'
   and pr.target_language is not null
   and p.chars > 0
on conflict (user_id, day, language) do nothing;

-- ---------------------------------------------------------------------------
-- 2) Estimated: conversation characters before the clock existed.
--
--    `tts_timestamps` is excluded throughout — that endpoint is shadowing,
--    which is review, not talking. In the tagged era only 'turn' and 'opener'
--    count; in the untagged era there is nothing to filter on, so those days
--    are the loosest evidence here and are marked exactly like the rest.
-- ---------------------------------------------------------------------------

insert into public.talk_seconds_by_language (user_id, day, language, seconds, estimated, source)
select l.user_id,
       l.created_at::date,
       lower(pr.target_language),
       -- 750 chars ≈ 60 s.
       greatest(1, floor(sum((l.metadata->>'chars')::numeric) * 60 / 750))::bigint,
       true,
       case when l.metadata ? 'purpose' then 'chars:turn' else 'chars:untagged' end
  from public.usage_ledger l
  join public.profiles pr on pr.id = l.user_id
 where l.action = 'tts'
   and l.metadata ? 'chars'
   and pr.target_language is not null
   and l.created_at::date < date '2026-08-10'
   and (not (l.metadata ? 'purpose')
        or l.metadata->>'purpose' in ('turn', 'opener'))
 group by l.user_id, l.created_at::date, lower(pr.target_language),
          case when l.metadata ? 'purpose' then 'chars:turn' else 'chars:untagged' end
on conflict (user_id, day, language) do nothing;

-- ---------------------------------------------------------------------------
-- 3) The counting boundary is now the first day any evidence exists, not the
--    day a migration ran. Per learner it still can't precede their signup,
--    which core_my_progress applies on top.
-- ---------------------------------------------------------------------------

update public.core_club_config
   set counting_since = least(
         counting_since,
         coalesce((select min(day) from public.talk_seconds_by_language), counting_since)),
       updated_at = now();

-- ---------------------------------------------------------------------------
-- 4) The boundary becomes PER LEARNER.
--
--    With history backfilled, `counting_since` is now 2026-06-10 — before
--    most accounts exist. A single global date would hand someone who signed
--    up this morning a window in which they had already missed twenty-nine
--    days, which is the exact failure this whole boundary was added to stop,
--    just pointed at newcomers instead of everyone.
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
  -- The first day THIS learner could have been observed: the day the Core
  -- began measuring, or the day they signed up, whichever is later. A global
  -- boundary alone would tell someone who joined this morning that they had
  -- missed the previous twenty-nine days.
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
    'counting_since', v_start,
    -- Only while it is still ahead. Once the window is fully observed the
    -- earliest-possible-seat date is in the past and says nothing; returning
    -- it anyway leaves the client hiding a wrong value by luck rather than
    -- being handed nothing to show.
    'first_seat_on',  case
                        when v_start + (c.entry_required_days - 1) > v_today
                        then v_start + (c.entry_required_days - 1)
                      end,
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
