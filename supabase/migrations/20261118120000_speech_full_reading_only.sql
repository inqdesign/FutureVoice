-- A challenge is read to the END, and a Season 2 board holds only takes
-- scored by its own rule (2026-11-18, founder: "the script is read to the
-- end, always; stopped halfway, it can't go up" and "the old records must
-- not be mixed in").
--
-- 1. submit_speech_reading_take_v8 refuses a take that read under 95% of
--    the script (INCOMPLETE). Until now an early stop lost at most the 20
--    points of the words area: 27 seconds of a 244-word script scored 58.
--    The app no longer scores such a take at all (SpeechTakeSession.stop);
--    this is for builds that still do. 95%, not 100%: the app's coverage
--    already lets a few misheard words through.
--
-- 2. The entries a scoring-7 build put on a Season 2 board through
--    20261113150000 (no per-sound counts, so never charged for sounds; one
--    read 99) are removed. They are the rows with no `sounds`; every other
--    Season 2 entry was scored by the price list. 20261117170000 already
--    refuses new ones. On 2026-11-18 that was four English rows (two
--    learners); they go back on the board with a take read on a current
--    build.
--
-- Same signature, so the function is replaced in place.

create or replace function public.submit_speech_reading_take_v8(
  p_challenge uuid, p_display_name text,
  p_overall int, p_speed int, p_rhythm int, p_pauses int, p_accuracy int,
  p_pronunciation int, p_coverage double precision, p_seconds int, p_scoring int,
  p_stops int, p_words int, p_sounds int, p_rhythm_point int, p_speed_point int,
  p_avatar text default null
)
returns table (rank int, previous_rank int, entrants int, best int, improved boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_expected int;
  v_lost numeric;
  v_prev_best int;
  v_prev_rank int;
  v_improved boolean;
  v_season record;
begin
  if v_uid is null then raise exception 'NOT_SIGNED_IN'; end if;
  if not exists (select 1 from speech_challenges where id = p_challenge and is_active) then
    raise exception 'CHALLENGE_NOT_FOUND';
  end if;
  select s.min_scoring, s.opened_at, s.ended_at into v_season
    from speech_challenges c
    join speech_seasons s on s.language = c.language and s.season = c.season
   where c.id = p_challenge;
  if v_season.ended_at is not null then raise exception 'SEASON_ENDED'; end if;
  if v_season.opened_at is null and not speech_is_admin() then raise exception 'CHALLENGE_NOT_FOUND'; end if;
  if p_scoring < v_season.min_scoring then raise exception 'NEEDS_UPDATE'; end if;
  if least(p_overall, p_speed, p_rhythm, p_pauses, p_accuracy, p_pronunciation) < 0
     or greatest(p_overall, p_speed, p_rhythm, p_pauses, p_accuracy, p_pronunciation) > 100
     or p_coverage < 0 or p_coverage > 1.5
     or p_seconds < 1 or p_seconds > 1800 then
    raise exception 'BAD_SCORE';
  end if;
  if least(p_stops, p_words, p_sounds, p_rhythm_point, p_speed_point) < 0 then raise exception 'BAD_SCORE'; end if;
  -- The script is read to the end (SpeechChallenges.fullReading).
  if p_coverage < 0.95 then raise exception 'INCOMPLETE'; end if;
  -- The price list (SpeechReadingScore.Price): keep the two in step.
  -- Five areas of 20 points each; an area stops at 0 and the total is
  -- what is left of the five (= their average out of 100).
  v_lost := p_stops * 1.0 + p_words * 1.0 + p_sounds * 0.4
          + greatest(0, 90 - p_rhythm_point) * 0.5 + greatest(0, 85 - p_speed_point) * 1.0;
  if v_lost = 0 then
    v_expected := 100;
  else
    v_expected := least(99, greatest(0, round(
        greatest(0, 20 - greatest(0, 85 - p_speed_point) * 1.0)
      + greatest(0, 20 - greatest(0, 90 - p_rhythm_point) * 0.5)
      + greatest(0, 20 - p_stops * 1.0)
      + greatest(0, 20 - p_words * 1.0)
      + greatest(0, 20 - p_sounds * 0.4))));
  end if;
  if abs(p_overall - v_expected) > 1 then raise exception 'BAD_SCORE'; end if;

  perform set_speech_challenge_profile(p_display_name, p_avatar);

  select e.best_score into v_prev_best
  from speech_challenge_entries e
  where e.challenge_id = p_challenge and e.user_id = v_uid;

  if v_prev_best is not null then
    select 1 + count(*)::int into v_prev_rank
    from speech_challenge_entries e
    where e.challenge_id = p_challenge and e.best_score > v_prev_best;
  end if;

  v_improved := v_prev_best is null or p_overall > v_prev_best;

  insert into speech_challenge_entries as e
    (challenge_id, user_id, best_score, accuracy, pace_score,
     pause_score, filler_score, steadiness, pronunciation, seconds,
     stops, words, sounds)
  values (p_challenge, v_uid, p_overall, p_accuracy, p_speed,
          p_pauses, 0, p_rhythm, p_pronunciation, p_seconds,
          p_stops, p_words, p_sounds)
  on conflict (challenge_id, user_id) do update set
    attempts      = e.attempts + 1,
    updated_at    = now(),
    best_score    = case when v_improved then excluded.best_score    else e.best_score end,
    accuracy      = case when v_improved then excluded.accuracy      else e.accuracy end,
    pace_score    = case when v_improved then excluded.pace_score    else e.pace_score end,
    pause_score   = case when v_improved then excluded.pause_score   else e.pause_score end,
    filler_score  = case when v_improved then excluded.filler_score  else e.filler_score end,
    steadiness    = case when v_improved then excluded.steadiness    else e.steadiness end,
    pronunciation = case when v_improved then excluded.pronunciation else e.pronunciation end,
    seconds       = case when v_improved then excluded.seconds       else e.seconds end,
    stops         = case when v_improved then excluded.stops         else e.stops end,
    words         = case when v_improved then excluded.words         else e.words end,
    sounds        = case when v_improved then excluded.sounds        else e.sounds end,
    best_at       = case when v_improved then now()                  else e.best_at end;

  return query
  select 1 + (select count(*)::int from speech_challenge_entries x
              where x.challenge_id = p_challenge and x.best_score > me.best_score),
         v_prev_rank,
         (select count(*)::int from speech_challenge_entries x where x.challenge_id = p_challenge),
         me.best_score,
         v_improved
  from speech_challenge_entries me
  where me.challenge_id = p_challenge and me.user_id = v_uid;
end;
$$;

delete from speech_challenge_entries e
using speech_challenges c, speech_seasons s
where c.id = e.challenge_id
  and s.language = c.language and s.season = c.season
  and s.min_scoring >= 8
  and e.sounds is null;

notify pgrst, 'reload schema';
