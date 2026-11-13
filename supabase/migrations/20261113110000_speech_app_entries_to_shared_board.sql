-- The speech app joins nawana's boards (2026-11-13, founder: "both apps
-- share one leaderboard, most people will read in nawana"). The app's own
-- board (`speech_app_entries`, 20261112210000) is no longer read or written.
--
-- Its scores move onto the shared board, for challenges whose season is
-- still open only: an ended season's board is frozen and stays as it was.
-- The better score stands (as a take would). Attempts are carried only for a
-- row the app alone had; an existing row keeps its own count, so running
-- this twice changes nothing.

with live as (
  select a.*
  from speech_app_entries a
  join speech_challenges c on c.id = a.challenge_id
  join speech_seasons s on s.language = c.language and s.season = c.season
  where s.opened_at is not null and s.ended_at is null
)
insert into speech_challenge_entries as e
  (challenge_id, user_id, best_score, accuracy, pace_score,
   pause_score, filler_score, steadiness, pronunciation, seconds,
   attempts, best_at, updated_at)
select challenge_id, user_id, best_score, accuracy, speed,
       pauses, 0, rhythm, pronunciation, seconds,
       attempts, best_at, updated_at
from live
on conflict (challenge_id, user_id) do update set
  updated_at    = greatest(e.updated_at, excluded.updated_at),
  best_score    = greatest(e.best_score, excluded.best_score),
  accuracy      = case when excluded.best_score > e.best_score then excluded.accuracy      else e.accuracy end,
  pace_score    = case when excluded.best_score > e.best_score then excluded.pace_score    else e.pace_score end,
  pause_score   = case when excluded.best_score > e.best_score then excluded.pause_score   else e.pause_score end,
  filler_score  = case when excluded.best_score > e.best_score then excluded.filler_score  else e.filler_score end,
  steadiness    = case when excluded.best_score > e.best_score then excluded.steadiness    else e.steadiness end,
  pronunciation = case when excluded.best_score > e.best_score then excluded.pronunciation else e.pronunciation end,
  seconds       = case when excluded.best_score > e.best_score then excluded.seconds       else e.seconds end,
  best_at       = case when excluded.best_score > e.best_score then excluded.best_at       else e.best_at end;
