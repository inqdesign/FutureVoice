-- The Core lets someone in the moment the thirtieth day is done (2026-10-29).
--
-- Entry used to wait for the nightly settlement (00:05 UTC). A learner who
-- crossed the bar on their thirtieth day stayed outside until then, which in
-- Korea is 09:05 the next morning, and the Core page told them "tonight".
-- Nothing is decided by waiting: the streak is already complete, and with an
-- empty seat there is nobody the wait could protect.
--
-- So ENTRY now happens inside the talk tick that crosses the day's bar:
--   * the streak reaches the entry bar → qualified now (join number, event);
--   * a seat is free and nobody is waiting for one → seated now.
-- When the club is full they are qualified now and wait in line, exactly as
-- before. LEAVING stays nightly, because a missed day is only known once the
-- day is over, and so does promoting people who were already waiting: that
-- happens after releases, in `settle_core_club_language`, which this does
-- not change. The settlement skips anyone who already has a membership row,
-- so a learner let in here is never qualified twice.
--
-- It runs in the same transaction as the tick. `consume_metered_seconds`
-- raises on a wall, and the raise rolls this back with the seconds, so
-- seconds the learner was not allowed to spend never earn a seat.

create or replace function public.core_enter_now(p_user_id uuid, p_language text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c         core_club_config%rowtype;
  v_today   date := (now() at time zone 'utc')::date;
  v_join    integer;
  v_seated  integer;
  v_waiting integer;
  v_seat    boolean := false;
begin
  if p_user_id is null or p_language is null or p_language = '' then
    return jsonb_build_object('entered', false);
  end if;

  -- One writer per club at a time, so two learners finishing together can't
  -- both take the last seat. The nightly settlement takes no such lock, but
  -- it only seats WAITING members and this only seats when nobody waits.
  perform pg_advisory_xact_lock(hashtext('core_enter:' || p_language));

  if exists (select 1 from core_membership
              where user_id = p_user_id and language = p_language) then
    return jsonb_build_object('entered', false, 'reason', 'member');
  end if;

  select * into c from core_club_config where id;

  if public.core_streak(p_user_id, p_language, v_today) < c.entry_streak_days then
    return jsonb_build_object('entered', false, 'reason', 'streak');
  end if;

  select count(*) into v_seated
    from core_membership where seated and language = p_language;

  -- Someone already in line comes first. Counted with the settlement's own
  -- promotion rule, so a member who fell off the keep bar doesn't hold the
  -- door shut for a newcomer.
  select count(*) into v_waiting
    from core_membership m
   where m.language = p_language
     and not m.seated
     and case
           when m.last_left_on is null
             or v_today - m.last_left_on <= c.requalify_after_days
           then public.core_missed_recent(m.user_id, p_language, v_today) <= c.keep_grace_days
           else public.core_streak(m.user_id, p_language, v_today) >= c.entry_streak_days
         end;

  v_seat := v_seated < c.seats and v_waiting = 0;

  -- `days_total` starts at 0 either way: the next settlement's tenure step
  -- counts today, the same +1 a nightly seat gets.
  insert into core_membership (user_id, language, join_number, seated, seated_since)
  values (p_user_id, p_language, nextval('core_join_number_seq'),
          v_seat, case when v_seat then v_today end)
  returning join_number into v_join;

  if v_seat then
    v_seated := v_seated + 1;
  end if;

  insert into core_events (kind, user_id, join_number, club_size, language)
  values ('qualified', p_user_id, v_join, v_seated, p_language);

  if v_seat then
    insert into core_events (kind, user_id, join_number, club_size, first_time, language)
    values ('seated', p_user_id, v_join, v_seated, true, p_language);

    if v_seated >= c.seats
       and not exists (select 1 from core_events
                        where kind = 'club_full' and language = p_language) then
      insert into core_events (kind, club_size, language)
      values ('club_full', v_seated, p_language);
    end if;
  end if;

  return jsonb_build_object('entered', true, 'seated', v_seat, 'join_number', v_join);
end;
$$;

revoke all on function public.core_enter_now(uuid, text) from public, anon, authenticated;

-- Same as 20260816120000, plus the entry check when this tick is the one
-- that carries today over the bar. Only on the crossing, so the hundreds of
-- other ticks a day cost nothing extra.
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
  v_lang  text := nullif(lower(trim(coalesce(p_language, ''))), '');
  v_total integer;
  v_bar   integer;
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
          updated_at = now()
    returning seconds into v_total;

    select daily_bar_seconds into v_bar from core_club_config where id;
    if v_total >= v_bar and v_total - p_seconds < v_bar then
      perform public.core_enter_now(p_user_id, v_lang);
    end if;
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

-- Everyone who already finished today before this was applied: they crossed
-- the bar under the old function, so no tick will cross it again today.
select public.core_enter_now(t.user_id, t.language)
  from talk_seconds_by_language t, core_club_config c
 where c.id
   and t.day = (now() at time zone 'utc')::date
   and t.seconds >= c.daily_bar_seconds;
