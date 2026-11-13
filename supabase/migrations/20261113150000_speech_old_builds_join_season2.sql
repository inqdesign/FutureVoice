-- Shipped builds see English Season 2 again (2026-11-13, founder: "the list
-- still isn't there in the production app").
--
-- 20261113120000 raised English Season 2 to scoring 8 (the price list), and
-- every build in the store scores 7, so `speech_challenge_list_v2` hid the
-- whole season from them: the page said "Season 2" over nothing.
--
-- A scoring-7 take carries the same parts the price list was already
-- rebuilt from for the entries on the boards that day (20261113120000 step
-- 4, the founder's choice): stops from the pause part, words from the
-- accuracy part, the rhythm and speed parts as their points, no sounds. So
-- instead of refusing such a take, the server checks it as scoring 7 and
-- files it under the price list, by that same rebuild. One rule on the
-- board; an old build just can't be charged for sounds.
--
-- `speech_seasons.converts_from`: the lowest scoring a season shows its
-- challenges to and converts takes from. NULL: nothing below `min_scoring`.

alter table public.speech_seasons add column if not exists converts_from int;
update public.speech_seasons set converts_from = 7 where language = 'en' and season = 2;

-- 1. The list: a season is shown to a build at or above its bar, or at or
-- above the scoring it converts from.
create or replace function public.speech_challenge_list_v2(p_language text, p_scoring integer)
returns table(id uuid, title text, genre text, body text, summary text, key_terms jsonb, sources jsonb,
              target_seconds integer, published_at timestamptz, retired_at timestamptz, entrants integer,
              top_score integer, my_best integer, my_rank integer, my_attempts integer, top_three jsonb,
              attempts integer, category text, intro jsonb, link text, season integer)
language sql stable security definer set search_path = public as $$
  with shown as (
    select c.id, c.title, c.genre, c.body, c.summary, c.key_terms, c.sources, c.target_seconds,
           c.published_at, c.retired_at as c_retired, c.is_active, c.category, c.intro, c.link,
           c.season as c_season, c.revived_from,
           s.ended_at as s_ended, f.ended_at as f_ended,
           (c.revived_from is not null
            and not (s.min_scoring <= p_scoring or coalesce(s.converts_from, 1000) <= p_scoring)) as as_past
    from speech_challenges c
    join speech_seasons s on s.language = c.language and s.season = c.season
    left join speech_seasons f on f.language = c.language and f.season = c.revived_from
    where c.language = p_language
      and (s.opened_at is not null or speech_is_admin())
      and (s.min_scoring <= p_scoring
           or coalesce(s.converts_from, 1000) <= p_scoring
           or (c.revived_from is not null and f.min_scoring <= p_scoring))
  ),
  pool as (
    select e.challenge_id, e.user_id, e.best_score, e.attempts, e.best_at, false as frozen
    from speech_challenge_entries e
    join speech_challenges c on c.id = e.challenge_id
    where c.language = p_language
    union all
    select r.challenge_id, r.user_id, r.best_score, r.attempts, r.best_at, true as frozen
    from speech_season_entries r
    join speech_challenges c on c.id = r.challenge_id and r.season = c.revived_from
    where r.language = p_language
  ),
  ranked as (
    select p.*, rank() over (partition by p.challenge_id, p.frozen order by p.best_score desc) as r
    from pool p
  )
  select c.id, c.title, c.genre, c.body, c.summary, c.key_terms, c.sources,
         c.target_seconds, c.published_at,
         case when c.as_past then coalesce(c.f_ended, c.published_at)
              when c.is_active and c.s_ended is null then null
              else coalesce(c.c_retired, c.s_ended, c.published_at) end,
         (select count(*)::int from ranked x where x.challenge_id = c.id and x.frozen = c.as_past),
         (select max(x.best_score) from ranked x where x.challenge_id = c.id and x.frozen = c.as_past),
         me.best_score, me.r::int, me.attempts,
         coalesce((
           select jsonb_agg(jsonb_build_object('display_name', t.display_name, 'avatar', t.avatar_jpeg)
                            order by t.best_score desc, t.best_at)
           from (
             select pr.display_name, pr.avatar_jpeg, x.best_score, x.best_at
             from ranked x
             join speech_challenge_profiles pr on pr.user_id = x.user_id
             where x.challenge_id = c.id and x.frozen = c.as_past
             order by x.best_score desc, x.best_at
             limit 3
           ) t
         ), '[]'::jsonb),
         (select coalesce(sum(x.attempts), 0)::int from ranked x where x.challenge_id = c.id and x.frozen = c.as_past),
         c.category, c.intro, c.link,
         (case when c.as_past then c.revived_from else c.c_season end)::int
  from shown c
  left join ranked me on me.challenge_id = c.id and me.user_id = auth.uid() and me.frozen = c.as_past
  order by (not c.as_past and c.is_active and c.s_ended is null) desc, c.published_at desc;
$$;

-- 2. The old builds' submit: checked as scoring 7, filed under the price list.
create or replace function public.submit_speech_reading_take(
  p_challenge uuid, p_display_name text, p_overall integer, p_speed integer, p_rhythm integer,
  p_pauses integer, p_accuracy integer, p_pronunciation integer, p_coverage double precision,
  p_seconds integer, p_scoring integer, p_avatar text default null
)
returns table(rank integer, previous_rank integer, entrants integer, best integer, improved boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_expected int;
  v_score int;
  v_stops int;
  v_words int;
  v_n int;
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
  select s.min_scoring, s.converts_from, s.opened_at, s.ended_at,
         array_length(regexp_split_to_array(trim(c.body), '\s+'), 1) as n
    into v_season
    from speech_challenges c
    join speech_seasons s on s.language = c.language and s.season = c.season
   where c.id = p_challenge;
  if v_season.ended_at is not null then raise exception 'SEASON_ENDED'; end if;
  if v_season.opened_at is null and not speech_is_admin() then raise exception 'CHALLENGE_NOT_FOUND'; end if;
  if p_scoring < v_season.min_scoring
     and (v_season.converts_from is null or p_scoring < v_season.converts_from) then
    raise exception 'NEEDS_UPDATE';
  end if;
  if least(p_overall, p_speed, p_rhythm, p_pauses, p_accuracy, p_pronunciation) < 0
     or greatest(p_overall, p_speed, p_rhythm, p_pauses, p_accuracy, p_pronunciation) > 100
     or p_coverage < 0 or p_coverage > 1.5
     or p_seconds < 1 or p_seconds > 1800 then
    raise exception 'BAD_SCORE';
  end if;
  -- The take is checked by the rule it was scored with (scoring 7).
  if least(p_speed, p_rhythm, p_pauses, p_accuracy, p_pronunciation) = 100 and p_coverage >= 0.999 then
    v_expected := 100;
  else
    v_expected := least(99, greatest(0, round(
      (p_speed + p_rhythm + p_pauses + p_accuracy + p_pronunciation) / 5.0
      * (0.2 + 0.8 * least(1, p_coverage)))));
  end if;
  if abs(p_overall - v_expected) > 1 then raise exception 'BAD_SCORE'; end if;

  v_score := p_overall;
  if p_scoring < v_season.min_scoring then
    -- Filed under the price list, rebuilt from the parts exactly as
    -- 20261113120000 rebuilt the entries already on the board.
    v_n := coalesce(v_season.n, 0);
    v_stops := round((100 - p_pauses) / 100.0 * v_n)::int;
    v_words := round((100 - p_accuracy) / 100.0 * v_n)::int;
    v_lost := v_stops * 1.0 + v_words * 1.0
            + greatest(0, 90 - p_rhythm) * 0.5 + greatest(0, 85 - p_speed) * 1.0;
    v_score := case when v_lost = 0 then 100 else least(99, greatest(0, round(100 - v_lost)))::int end;
  end if;

  perform set_speech_challenge_profile(p_display_name, p_avatar);

  select e.best_score into v_prev_best
  from speech_challenge_entries e
  where e.challenge_id = p_challenge and e.user_id = v_uid;

  if v_prev_best is not null then
    select 1 + count(*)::int into v_prev_rank
    from speech_challenge_entries e
    where e.challenge_id = p_challenge and e.best_score > v_prev_best;
  end if;

  v_improved := v_prev_best is null or v_score > v_prev_best;

  insert into speech_challenge_entries as e
    (challenge_id, user_id, best_score, accuracy, pace_score,
     pause_score, filler_score, steadiness, pronunciation, seconds, stops, words)
  values (p_challenge, v_uid, v_score, p_accuracy, p_speed,
          p_pauses, 0, p_rhythm, p_pronunciation, p_seconds, v_stops, v_words)
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
    sounds        = case when v_improved then null                   else e.sounds end,
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
