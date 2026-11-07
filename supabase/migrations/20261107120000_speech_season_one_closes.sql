-- Speech challenges get SEASONS, and Season 1 closes (2026-11-07, founder).
--
-- Season 1 was scored by rules a familiar script beats: every part but
-- accuracy and pronunciation reads 100 for anyone who has read it a few
-- times, and pronunciation sits at 91–98 for every learner, so 99–100 came
-- easily. The founder's bar for Season 2: 100 is an announcer's read, perfect
-- in every part. That scoring is not built yet (it is scoring version 4).
--
-- So:
--   * every challenge so far is Season 1, and every one still open is
--     retired now. Its board stays readable and frozen, the winners stay
--     where they are, and nobody can enter it again (submit already refuses
--     a challenge that is not active, on every build);
--   * a season names the scoring it takes (`min_scoring`). Season 2 takes
--     scoring 4 and up, so a Season 2 challenge is listed only to a build
--     that scores that way, and every submit a shipped build can make
--     (scoring 2 or 3) is refused for it. Publishing a Season 2 challenge
--     before the scoring-4 build ships is therefore harmless: nobody on an
--     older build sees it;
--   * the overall board is per season. A build that does not name a season
--     gets Season 1's final standings, which is what every shipped build
--     (iOS 1.3.x, Android) should show from today.
--
-- New challenges (publish_speech_challenge) land in Season 2 by the column's
-- default. When Season 3 comes, move the default in its own migration.

create table if not exists public.speech_seasons (
  season      smallint primary key,
  -- The oldest SpeechAnalyzer.scoringVersion this season takes.
  min_scoring int not null,
  ended_at    timestamptz
);
alter table public.speech_seasons enable row level security;  -- read through the functions only

insert into public.speech_seasons (season, min_scoring, ended_at) values
  (1, 2, now()),
  (2, 4, null)
on conflict (season) do nothing;

-- Everything on file when the column arrives is Season 1; everything
-- published after it is Season 2. Done once, so a second run can never move
-- a Season 2 challenge back.
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'speech_challenges'
                    and column_name = 'season') then
    alter table public.speech_challenges
      add column season smallint not null default 1
      references public.speech_seasons(season);
    alter table public.speech_challenges alter column season set default 2;
  end if;
end;
$$;

-- Season 1 closes: the open challenges become past ones, boards frozen.
update public.speech_challenges
   set is_active = false, retired_at = coalesce(retired_at, now())
 where season = 1 and is_active;

-- ---------------------------------------------------------------------------
-- The list: `season` on every row, and only what the caller can score.
-- Shipped builds call it with `p_language` alone and are scoring 3 at most.

drop function if exists public.speech_challenge_list(text);
drop function if exists public.speech_challenge_list(text, int);
create function public.speech_challenge_list(p_language text, p_scoring int default 3)
returns table (
  id uuid, title text, genre text, body text, summary text,
  key_terms jsonb, sources jsonb, target_seconds int, published_at timestamptz,
  retired_at timestamptz,
  entrants int, top_score int, my_best int, my_rank int, my_attempts int,
  top_three jsonb, attempts int, category text, intro jsonb, link text,
  season smallint
)
language sql stable security definer set search_path = public as $$
  with ranked as (
    select e.challenge_id, e.user_id, e.best_score, e.attempts,
           rank() over (partition by e.challenge_id order by e.best_score desc) as r
    from speech_challenge_entries e
    join speech_challenges c on c.id = e.challenge_id
    where c.language = p_language
  )
  select c.id, c.title, c.genre, c.body, c.summary, c.key_terms, c.sources,
         c.target_seconds, c.published_at,
         case when c.is_active then null else coalesce(c.retired_at, c.published_at) end,
         (select count(*)::int from ranked x where x.challenge_id = c.id),
         (select max(x.best_score) from ranked x where x.challenge_id = c.id),
         me.best_score, me.r::int, me.attempts,
         coalesce((
           select jsonb_agg(jsonb_build_object('display_name', t.display_name, 'avatar', t.avatar_jpeg)
                            order by t.best_score desc, t.best_at)
           from (
             select p.display_name, p.avatar_jpeg, e.best_score, e.best_at
             from speech_challenge_entries e
             join speech_challenge_profiles p on p.user_id = e.user_id
             where e.challenge_id = c.id
             order by e.best_score desc, e.best_at
             limit 3
           ) t
         ), '[]'::jsonb),
         (select coalesce(sum(x.attempts), 0)::int from ranked x where x.challenge_id = c.id),
         c.category, c.intro, c.link,
         c.season
  from speech_challenges c
  join speech_seasons s on s.season = c.season
  left join ranked me on me.challenge_id = c.id and me.user_id = auth.uid()
  where c.language = p_language
    and s.min_scoring <= coalesce(p_scoring, 3)
  order by c.is_active desc, c.published_at desc;
$$;

revoke all on function public.speech_challenge_list(text, int) from public;
grant execute on function public.speech_challenge_list(text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- The overall board, one per season. No season named = Season 1.

drop function if exists public.speech_overall_board(text, int);
drop function if exists public.speech_overall_board(text, int, int);
create function public.speech_overall_board(p_language text, p_limit int default 10,
                                            p_season int default 1)
returns table (rank int, display_name text, avatar text, score int, is_me boolean,
               core_theme smallint, challenges int)
language sql stable security definer set search_path = public as $$
  with totals as (
    select e.user_id,
           sum(e.best_score)::int as total,
           count(*)::int as n,
           max(e.best_at) as reached_at
    from speech_challenge_entries e
    join speech_challenges c on c.id = e.challenge_id
    where c.language = p_language
      and c.season = coalesce(p_season, 1)
    group by e.user_id
  ),
  ranked as (
    select t.user_id, p.display_name, p.avatar_jpeg, t.total, t.n,
           rank() over (order by t.total desc)::int as r,
           row_number() over (order by t.total desc, t.reached_at) as pos
    from totals t
    join speech_challenge_profiles p on p.user_id = t.user_id
  )
  select r, display_name, avatar_jpeg, total, ranked.user_id = auth.uid(),
         (select m.theme
            from core_membership m
           where m.user_id = ranked.user_id
             and m.language = p_language
             and m.seated),
         n
  from ranked
  where pos <= least(greatest(p_limit, 1), 50) or ranked.user_id = auth.uid()
  order by pos;
$$;
revoke all on function public.speech_overall_board(text, int, int) from public;
grant execute on function public.speech_overall_board(text, int, int) to authenticated;

-- ---------------------------------------------------------------------------
-- Submitting: the eleven-argument function every other one hands over to.
-- The only change from 20261104190000 is the season check after the
-- challenge check: every caller of these functions scores 2 or 3, so a
-- season asking for more refuses them. The scoring-4 build gets a function
-- of its own, with its own weighting check, in the migration that ships it.

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
  if exists (select 1
               from speech_challenges c
               join speech_seasons s on s.season = c.season
              where c.id = p_challenge and s.min_scoring > 3) then
    raise exception 'NEEDS_UPDATE';
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

notify pgrst, 'reload schema';
