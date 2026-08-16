-- The Core becomes one club PER TARGET LANGUAGE.
--
-- WHY. A single 100-seat club spanning every target language is incoherent in
-- three separate ways:
--
--   * Find people is ALREADY per language (`public_personas.language`, fetched
--     for the learner's `targetLanguage`). So a seal earned by talking Korean
--     was showing up next to a name in the German pool, where it means
--     nothing about anything.
--   * Switching target language carried the seat along. A seat is a claim
--     about keeping something up in a language; it cannot follow you into a
--     language you have never spoken.
--   * 100 is only a meaningful number against a population. One global club
--     makes the bar arbitrary relative to whichever languages happen to be
--     growing.
--
-- THE HARD PART WAS NOT THE CLUB, IT WAS THE DATA. `talk-tick` sent only
-- `{seconds, session_id}`; across 2,865 metered ledger rows on 2026-08-16 not
-- one carried a language. There was no signal to partition — not historically
-- and not live. So this adds the signal first and hangs the club off it.
--
-- WHERE THE SIGNAL LIVES. A new `talk_seconds_by_language`, NOT a new column
-- on `tts_char_pool`. That table's primary key is (user_id, day, action) and
-- every billing path writes through it; widening its key to carry a language
-- would put the whole metering system on the critical path of a feature that
-- grants nothing. The Core gets its own ledger, billing is untouched, and the
-- two can be reconciled by summing.
--
-- CONSEQUENCE FOR EXISTING DATA: talk recorded before this migration has no
-- language and therefore counts toward NO club. That is three days of one
-- account (`TalkMeter` shipped 2026-08-11 and is not in any tester build), so
-- nothing real is lost, and guessing a language would be inventing evidence
-- for a claim about persistence.
--
-- A learner with two target languages can hold a seat in each, and has to
-- earn each one separately. That is the honest reading: the bar is about
-- keeping a language up, and doing it twice is twice the work.

-- ---------------------------------------------------------------------------
-- 1) The Core's own activity ledger, with a language on every row.
-- ---------------------------------------------------------------------------

create table if not exists public.talk_seconds_by_language (
  user_id    uuid not null references auth.users(id) on delete cascade,
  day        date not null,
  language   text not null,
  seconds    bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, day, language)
);

alter table public.talk_seconds_by_language enable row level security;
-- Server-only, like tts_char_pool: this is per-learner talk volume, and the
-- one client that needs a slice of it gets that slice from core_my_progress.
revoke all on public.talk_seconds_by_language from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) Talk metering learns the language. Optional argument, so a deployed
--    client that doesn't send one still bills exactly as it does today — it
--    just contributes to no club, which is the correct outcome for a build
--    that cannot say what was being spoken.
-- ---------------------------------------------------------------------------

create or replace function public.charge_talk_seconds(
  p_user_id uuid,
  p_seconds integer,
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null,
  p_language text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lang text := nullif(lower(trim(coalesce(p_language, ''))), '');
begin
  if p_seconds < 1 or p_seconds > 600 then
    raise exception 'p_seconds out of range';
  end if;

  -- Accumulated BEFORE the charge on purpose. consume_metered_seconds raises
  -- on DAILY_CAP_REACHED / INSUFFICIENT_CREDITS, and a raise rolls this back
  -- with it — so seconds the learner was never allowed to spend never count
  -- toward a seat. The idempotency guard mirrors the one inside consume: a
  -- retried tick must not accumulate twice.
  if v_lang is not null
     and (p_idempotency_key is null
          or not exists (select 1 from usage_ledger
                          where idempotency_key = p_idempotency_key)) then
    insert into talk_seconds_by_language (user_id, day, language, seconds)
    values (p_user_id, current_date, v_lang, p_seconds)
    on conflict (user_id, day, language) do update
      set seconds = talk_seconds_by_language.seconds + excluded.seconds,
          updated_at = now();
  end if;

  return public.consume_metered_seconds(
    p_user_id => p_user_id,
    p_seconds => p_seconds,
    p_pool    => 'talk_seconds',
    p_action  => 'talk_time',
    p_source_fn => p_source_fn,
    p_idempotency_key => p_idempotency_key,
    p_metadata => coalesce(p_metadata, '{}'::jsonb)
      || jsonb_build_object('language', v_lang));
end;
$$;

-- The view gains a column in the MIDDLE, which CREATE OR REPLACE VIEW cannot
-- do, so it is dropped and rebuilt (and re-revoked — a rebuilt view comes
-- back with Supabase's default grants).
drop view if exists public.core_daily_activity;
create view public.core_daily_activity as
  select user_id, day, language, seconds as talk_seconds
    from public.talk_seconds_by_language;
revoke all on public.core_daily_activity from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Membership is keyed by (person, language).
-- ---------------------------------------------------------------------------

alter table public.core_membership add column if not exists language text;

do $$
begin
  if exists (select 1 from public.core_membership where language is null) then
    raise exception
      'core_membership holds rows with no language. They predate per-language '
      'clubs and cannot be attributed without guessing; assign or delete them '
      'first.';
  end if;
end $$;

alter table public.core_membership alter column language set not null;

alter table public.core_membership drop constraint if exists core_membership_pkey;
alter table public.core_membership add primary key (user_id, language);

drop index if exists core_membership_seated_idx;
create index if not exists core_membership_seated_idx
  on public.core_membership(language) where seated;

-- `join_number` stays GLOBALLY unique and off one sequence. It is the
-- qualification order and therefore the queue (20260815150000), and ordering a
-- single language's waiting list by a global sequence still yields
-- first-qualified-first inside that language.

alter table public.core_events add column if not exists language text;

alter table public.core_settlement_log add column if not exists language text;
update public.core_settlement_log set language = '' where language is null;
alter table public.core_settlement_log alter column language set not null;
alter table public.core_settlement_log drop constraint if exists core_settlement_log_pkey;
alter table public.core_settlement_log add primary key (day, language);

-- ---------------------------------------------------------------------------
-- 4) Settlement, per language.
--
--    The body that used to BE settle_core_club moves down a level, scoped to
--    one language, and the public function loops. Splitting it this way keeps
--    each club's settlement independent: one language's promotions can never
--    consume another's seats, and a language with no activity at all is
--    simply not settled.
--
--    Every rule inside is unchanged — one bar for everything
--    (20260815140000), release strictly before promote so no arrival
--    displaces a sitting member, and the queue ordered by join_number
--    (20260815150000).
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

  drop table if exists _core_stats;
  create temporary table _core_stats on commit drop as
  with act as (
    select user_id, day, talk_seconds
      from core_daily_activity
     where language = p_language
       and day > p_as_of - c.entry_window_days
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
          select user_id from core_membership where language = p_language) u
    left join act a on a.user_id = u.user_id
   group by u.user_id;

  -- (a) Qualify, in this language.
  drop table if exists _core_new;
  create temporary table _core_new on commit drop as
  with fresh as (
    select s.user_id
      from _core_stats s
     where s.met_entry >= c.entry_required_days
       and not exists (select 1 from core_membership m
                        where m.user_id = s.user_id
                          and m.language = p_language)
     order by s.user_id
  ), issued as (
    insert into core_membership (user_id, language, join_number)
    select user_id, p_language, nextval('core_join_number_seq') from fresh
    returning user_id, join_number
  )
  select * from issued;

  select count(*) into v_qualified from _core_new;

  -- (b) Release. Still the ONLY way a seat opens.
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
       and s.met_keep < c.keep_required_days
    returning m.user_id, m.join_number
  )
  select * from released;

  select count(*) into v_released from _core_out;

  -- (c) Promote, oldest qualification first, into THIS language's seats.
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
             then s.met_keep >= c.keep_required_days
             else s.met_entry >= c.entry_required_days
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

  -- (d) Tenure, for this language's seats only.
  update core_membership set days_total = days_total + 1
   where seated and language = p_language;

  select count(*) into v_seated
    from core_membership where seated and language = p_language;

  -- (e) Events carry the language, so a client only hears about arrivals in
  --     the club it is looking at.
  insert into core_events (kind, user_id, join_number, club_size, language)
  select 'left', user_id, join_number, v_seated, p_language from _core_out;

  insert into core_events (kind, user_id, join_number, club_size, language)
  select 'qualified', user_id, join_number, v_seated, p_language from _core_new;

  insert into core_events (kind, user_id, join_number, club_size, first_time, language)
  select 'seated', user_id, join_number, v_seated, first_time, p_language from _core_in;

  -- Once ever, per language.
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

-- The nightly entry point: settle every language that has either activity in
-- the window or a club already standing. Signature unchanged, so the existing
-- pg_cron job keeps working untouched.
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
     where day > p_as_of - c.entry_window_days and day <= p_as_of
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
-- 5) Everything the client reads, scoped to the club it is looking at.
--    `core_my_progress` REQUIRES a language: answering about "the Core"
--    with no club named is how a learner ends up reading someone else's
--    progress bar.
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
           coalesce(a.talk_seconds, 0) >= c.daily_bar_seconds as met
      from span s
      left join core_daily_activity a
        on a.user_id = v_uid and a.day = s.day
       and a.language = v_lang
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

drop function if exists public.core_my_progress();
grant execute on function public.core_my_progress(text) to authenticated;

-- Badges are asked for by the pool being browsed. Find people already fetches
-- one language at a time, so a seal earned in Korean stops appearing beside a
-- name in the German pool.
create or replace function public.core_badges_for(
  p_user_ids uuid[],
  p_language text
) returns table(user_id uuid, seated boolean)
language sql
stable
security definer
set search_path = public
as $$
  -- Sliced, not LIMITed: a caller asking about too many people gets a
  -- deterministic prefix of what they asked for, never an arbitrary window
  -- onto the membership table. A screen of personas is ~50.
  select m.user_id, m.seated
    from public.core_membership m
   where m.user_id = any (p_user_ids[1:200])
     and m.language = lower(trim(p_language));
$$;

-- The old single-argument form has to go, or a caller that forgets to pass a
-- language silently keeps the cross-language behaviour this migration exists
-- to remove.
drop function if exists public.core_badges_for(uuid[]);
revoke all on function public.core_badges_for(uuid[], text) from public, anon;
grant execute on function public.core_badges_for(uuid[], text) to authenticated;

-- One room per language.
create or replace function public.core_seat_map(p_language text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_lang   text := nullif(lower(trim(coalesce(p_language, ''))), '');
  v_seats  integer;
  v_themes jsonb;
  v_mine   integer;
  v_taken  integer;
begin
  if v_lang is null then
    raise exception 'p_language required';
  end if;

  select seats into v_seats from core_club_config where id;

  -- Ordered once, into an array, so the position a member holds in `themes`
  -- and the position reported as `mine` can never disagree.
  with seated as (
    select m.user_id, m.theme,
           (row_number() over (order by m.join_number))::int - 1 as idx
      from core_membership m
     where m.seated and m.language = v_lang
     order by m.join_number
     limit v_seats
  )
  select jsonb_agg(theme order by idx),
         count(*)::int,
         max(idx) filter (where user_id = v_uid)
    into v_themes, v_taken, v_mine
    from seated;

  return jsonb_build_object(
    'language', v_lang,
    'seats',  v_seats,
    'taken',  coalesce(v_taken, 0),
    'themes', coalesce(v_themes, '[]'::jsonb),
    'mine',   v_mine);
end;
$$;

drop function if exists public.core_seat_map();
revoke all on function public.core_seat_map(text) from public, anon;
grant execute on function public.core_seat_map(text) to authenticated;

-- The colour is the PERSON's, not the membership's: someone in two clubs is
-- one person and should be the same pixel in both rooms. So this still writes
-- every row they hold.
create or replace function public.core_set_theme(p_theme integer)
returns void
language sql
security definer
set search_path = public
as $$
  -- Clamped, not validated: the client is the only writer and an out-of-range
  -- value means a future theme this server hasn't heard of. Storing it lets a
  -- newer app draw it correctly while older readers fall back — rejecting it
  -- would strand the member on someone else's colour.
  update public.core_membership
     set theme = greatest(0, least(p_theme, 255))
   where user_id = auth.uid();
$$;
