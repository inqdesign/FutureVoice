-- A speech take's overall counts its SOUNDS (2026-11-04, founder).
--
-- Every challenge take read 90–100 once the script was familiar: the overall
-- was accuracy 40% + delivery 60% (pace, pauses, fillers, steadiness), and
-- nothing in it listened to how a word sounded — the phoneme assessment
-- (`PronunciationAssessor`) was shown on its own row only. A take with a
-- pronunciation score is now weighted
--   accuracy 30 · pronunciation 25 · pace 15 · pauses 10 · fillers 10 · steadiness 10,
-- everything but accuracy scaled by how far into the script the reader got
-- (`coverage`, 20261014120000). So the check is again a range: at least the
-- accuracy part alone, at most the full weighting (±1 for rounding).
--
-- A take WITHOUT pronunciation (the assessment failed, or a build that
-- doesn't send it) is checked against the 2026-10-14 weighting exactly as
-- before. Entries already on a board stay as they were (founder's pick):
-- nothing is re-scored or hidden.
--
-- New builds call the ELEVEN-argument function and always send
-- p_pronunciation (null when not assessed). The ten- and nine-argument
-- functions shipped builds call stay, the ten now handing over to the eleven
-- with null. No argument has a default, so no call can match two of them.

alter table public.speech_challenge_entries
  add column if not exists pronunciation int;

create or replace function public.submit_speech_challenge_take(
  p_challenge uuid, p_display_name text, p_avatar text,
  p_overall int, p_accuracy int, p_pace int, p_pause int, p_filler int,
  p_steadiness int, p_pronunciation int, p_seconds int
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
  if least(p_overall, p_accuracy, p_pace, p_pause, p_filler, p_steadiness,
           coalesce(p_pronunciation, 0)) < 0
     or greatest(p_overall, p_accuracy, p_pace, p_pause, p_filler, p_steadiness,
                 coalesce(p_pronunciation, 0)) > 100
     or p_seconds < 1 or p_seconds > 1800 then
    raise exception 'BAD_SCORE';
  end if;
  -- SpeechAnalyzer.overall: everything said scaled by coverage (0…1), so
  -- anything from the accuracy part alone up to the full weighting.
  if p_pronunciation is null then
    v_full  := round(0.40 * p_accuracy + 0.20 * p_pace + 0.15 * p_pause
                     + 0.10 * p_filler + 0.15 * p_steadiness);
    v_floor := round(0.40 * p_accuracy);
  else
    v_full  := round(0.30 * p_accuracy + 0.25 * p_pronunciation + 0.15 * p_pace
                     + 0.10 * p_pause + 0.10 * p_filler + 0.10 * p_steadiness);
    v_floor := round(0.30 * p_accuracy);
  end if;
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
     pause_score, filler_score, steadiness, pronunciation, seconds)
  values (p_challenge, v_uid, p_overall, p_accuracy, p_pace,
          p_pause, p_filler, p_steadiness, p_pronunciation, p_seconds)
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

revoke all on function public.submit_speech_challenge_take(
  uuid, text, text, int, int, int, int, int, int, int, int) from public, anon;
grant execute on function public.submit_speech_challenge_take(
  uuid, text, text, int, int, int, int, int, int, int, int) to authenticated;

-- What shipped builds call: the same check, with no pronunciation.
create or replace function public.submit_speech_challenge_take(
  p_challenge uuid, p_display_name text, p_avatar text,
  p_overall int, p_accuracy int, p_pace int, p_pause int, p_filler int,
  p_steadiness int, p_seconds int
)
returns table (rank int, previous_rank int, entrants int, best int, improved boolean)
language sql security definer set search_path = public as $$
  select * from public.submit_speech_challenge_take(
    p_challenge, p_display_name, p_avatar,
    p_overall, p_accuracy, p_pace, p_pause, p_filler, p_steadiness,
    null::int, p_seconds);
$$;

notify pgrst, 'reload schema';
