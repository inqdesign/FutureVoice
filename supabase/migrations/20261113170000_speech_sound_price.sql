-- A wrong sound costs 0.4, not 0.5 (2026-11-13, founder: the calibration's
-- own ratio to a word is 0.37). App: SpeechReadingScore.Price.sound.
-- Same signature, so this replaces the function in place.

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
  -- The price list (SpeechReadingScore.Price): keep the two in step.
  v_lost := p_stops * 1.0 + p_words * 1.0 + p_sounds * 0.4
          + greatest(0, 90 - p_rhythm_point) * 0.5 + greatest(0, 85 - p_speed_point) * 1.0;
  if v_lost = 0 then
    v_expected := 100;
  else
    v_expected := least(99, greatest(0, round(100 - v_lost)));
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

-- The entries already scored with sounds at 0.5 (only takes from the
-- price-list build carry `sounds`), recomputed with 0.4. A row from the
-- rescore of 20261113120000 has no `sounds` and is left as it is.
update speech_challenge_entries e set
  best_score = case
    when e.stops + e.words + e.sounds + greatest(0, 90 - e.steadiness) + greatest(0, 85 - e.pace_score) = 0 then 100
    else least(99, greatest(0, round(100 - (e.stops * 1.0 + e.words * 1.0 + e.sounds * 0.4
           + greatest(0, 90 - e.steadiness) * 0.5 + greatest(0, 85 - e.pace_score) * 1.0))))::int
  end
where e.sounds is not null and e.stops is not null and e.words is not null;

notify pgrst, 'reload schema';
