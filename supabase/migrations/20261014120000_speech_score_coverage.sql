-- A take that stops early no longer scores like a finished one (2026-10-14).
--
-- SpeechAnalyzer's overall was 0.40 accuracy + 0.60 delivery (pace, pauses,
-- fillers, steadiness), and delivery is measured only on what was SAID — so
-- reading three sentences of a long script and stopping scored ~75: accuracy
-- low, delivery near 100. The app now scales the delivery part by how much of
-- the script was reached (`coverage`, 0…1), so the overall can only go DOWN
-- from the old weighting, never up.
--
-- The check therefore becomes a range instead of an equality: at least the
-- accuracy part alone, at most the old full weighting (±1 for rounding).
-- Builds that don't know about coverage compute exactly the old weighting and
-- still pass; the signature is unchanged, so no new overload appears.

create or replace function public.submit_speech_challenge_take(
  p_challenge uuid, p_display_name text, p_avatar text,
  p_overall int, p_accuracy int, p_pace int, p_pause int, p_filler int,
  p_steadiness int, p_seconds int
)
returns table (rank int, previous_rank int, entrants int, best int, improved boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_full int;
  v_floor int;
  v_prev_best int;
  v_prev_rank int;
  v_improved boolean;
begin
  if v_uid is null then raise exception 'NOT_SIGNED_IN'; end if;
  if not exists (select 1 from speech_challenges where id = p_challenge and is_active) then
    raise exception 'CHALLENGE_NOT_FOUND';
  end if;
  if least(p_overall, p_accuracy, p_pace, p_pause, p_filler, p_steadiness) < 0
     or greatest(p_overall, p_accuracy, p_pace, p_pause, p_filler, p_steadiness) > 100
     or p_seconds < 1 or p_seconds > 1800 then
    raise exception 'BAD_SCORE';
  end if;
  -- SpeechAnalyzer.analyze's weighting, delivery scaled by coverage (0…1):
  -- anything from the accuracy part alone up to the full weighting.
  v_full  := round(0.40 * p_accuracy + 0.20 * p_pace + 0.15 * p_pause
                   + 0.10 * p_filler + 0.15 * p_steadiness);
  v_floor := round(0.40 * p_accuracy);
  if p_overall > v_full + 1 or p_overall < v_floor - 1 then raise exception 'BAD_SCORE'; end if;

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
     pause_score, filler_score, steadiness, seconds)
  values (p_challenge, v_uid, p_overall, p_accuracy, p_pace,
          p_pause, p_filler, p_steadiness, p_seconds)
  on conflict (challenge_id, user_id) do update set
    attempts     = e.attempts + 1,
    updated_at   = now(),
    best_score   = case when v_improved then excluded.best_score   else e.best_score end,
    accuracy     = case when v_improved then excluded.accuracy     else e.accuracy end,
    pace_score   = case when v_improved then excluded.pace_score   else e.pace_score end,
    pause_score  = case when v_improved then excluded.pause_score  else e.pause_score end,
    filler_score = case when v_improved then excluded.filler_score else e.filler_score end,
    steadiness   = case when v_improved then excluded.steadiness   else e.steadiness end,
    seconds      = case when v_improved then excluded.seconds      else e.seconds end,
    best_at      = case when v_improved then now()                 else e.best_at end;

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
