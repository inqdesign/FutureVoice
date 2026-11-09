-- Season 2's total is the plain average of its five parts (scoring 7,
-- 2026-11-09, founder: "96 is 96"). 100 needs every part at 100; it used to
-- need every part at 95.

create or replace function public.submit_speech_reading_take(
  p_challenge uuid, p_display_name text,
  p_overall int, p_speed int, p_rhythm int, p_pauses int, p_accuracy int,
  p_pronunciation int, p_coverage double precision, p_seconds int, p_scoring int,
  p_avatar text default null
)
returns table (rank int, previous_rank int, entrants int, best int, improved boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_expected int;
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
  if least(p_speed, p_rhythm, p_pauses, p_accuracy, p_pronunciation) = 100 and p_coverage >= 0.999 then
    v_expected := 100;
  else
    v_expected := least(99, greatest(0, round(
      (p_speed + p_rhythm + p_pauses + p_accuracy + p_pronunciation) / 5.0
      * (0.2 + 0.8 * least(1, p_coverage)))));
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
     pause_score, filler_score, steadiness, pronunciation, seconds)
  values (p_challenge, v_uid, p_overall, p_accuracy, p_speed,
          p_pauses, 0, p_rhythm, p_pronunciation, p_seconds)
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

notify pgrst, 'reload schema';
