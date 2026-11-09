-- Speech challenges get SEASONS, per language (2026-11-09, founder).
--
-- Season 2 is scored against a native reading (`SpeechReading`, English only,
-- scoring 6), on a scale Season 1's numbers can't be compared with. So each
-- language has its own seasons; English moves first, the others stay on
-- Season 1 until their scoring is validated.
--
-- Closing a season does NOT retire its challenges: it stamps
-- `speech_seasons.ended_at`, and that decides everything by who is asking.
--   * A build that knows seasons calls the _v2 functions. A closed season's
--     challenges come back with `retired_at` set: past, boards frozen, and
--     the reader can keep practising them, which writes nothing here.
--   * A build already in the store calls the old functions, which keep
--     returning Season 1 with its challenges live. Its tab must not go empty
--     (it has no code to explain why). A take from such a build changes
--     nothing either: submit answers with the standing as it is.
--
-- Nothing here opens a season. `open_speech_season('en', 2)` does, once the
-- build is out and Android has the scoring. Until then Season 2 is a draft
-- that only admin accounts (`user_credits.unlimited`) see and can enter.
--
-- Additive: the app falls back to the old functions while the _v2 ones are
-- missing, so this and the build can go out in either order.

create table if not exists public.speech_seasons (
  language    text not null,
  season      smallint not null,
  -- The oldest scoring version this season takes.
  min_scoring int not null,
  opened_at   timestamptz,          -- null: a draft
  ended_at    timestamptz,
  primary key (language, season)
);
alter table public.speech_seasons enable row level security;  -- read through the functions only

insert into public.speech_seasons (language, season, min_scoring, opened_at)
select l, 1, 2, now()
from (select unnest(array['en', 'ko', 'ja', 'de', 'es']) as l
      union select distinct language from public.speech_challenges) langs
on conflict (language, season) do nothing;

insert into public.speech_seasons (language, season, min_scoring, opened_at)
values ('en', 2, 6, null)
on conflict (language, season) do nothing;

alter table public.speech_challenges
  add column if not exists season smallint not null default 1;

-- A challenge published from now on belongs to its language's newest season,
-- a draft included: English challenges written for Season 2 stay out of every
-- list until it opens.
create or replace function public.speech_challenge_set_season()
returns trigger language plpgsql set search_path = public as $$
begin
  new.season := coalesce((select max(s.season) from speech_seasons s where s.language = new.language), 1);
  return new;
end;
$$;

drop trigger if exists speech_challenge_set_season on public.speech_challenges;
create trigger speech_challenge_set_season
  before insert on public.speech_challenges
  for each row execute function public.speech_challenge_set_season();

-- A learner can take themselves off a board: the score is deleted. Their next
-- take on a live challenge goes on it again like any other.
create or replace function public.withdraw_speech_challenge_entry(p_challenge uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'NOT_SIGNED_IN'; end if;
  delete from speech_challenge_entries where challenge_id = p_challenge and user_id = auth.uid();
end;
$$;
revoke all on function public.withdraw_speech_challenge_entry(uuid) from public, anon;
grant execute on function public.withdraw_speech_challenge_entry(uuid) to authenticated;

create or replace function public.speech_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_credits where user_id = auth.uid() and unlimited);
$$;

-- ---------------------------------------------------------------------------
-- Which seasons a language has, as this account sees them.

create or replace function public.speech_season_status(p_language text)
returns table (season int, min_scoring int, is_open boolean, ended boolean)
language sql stable security definer set search_path = public as $$
  select s.season::int, s.min_scoring,
         s.ended_at is null and (s.opened_at is not null or speech_is_admin()),
         s.ended_at is not null
  from speech_seasons s
  where s.language = p_language
    and (s.opened_at is not null or speech_is_admin())
  order by s.season;
$$;
revoke all on function public.speech_season_status(text) from public;
grant execute on function public.speech_season_status(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- The list for a build that knows seasons.

create or replace function public.speech_challenge_list_v2(p_language text, p_scoring int)
returns table (
  id uuid, title text, genre text, body text, summary text,
  key_terms jsonb, sources jsonb, target_seconds int, published_at timestamptz,
  retired_at timestamptz,
  entrants int, top_score int, my_best int, my_rank int, my_attempts int,
  top_three jsonb, attempts int, category text, intro jsonb, link text,
  season int
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
         case when c.is_active and s.ended_at is null then null
              else coalesce(c.retired_at, s.ended_at, c.published_at) end,
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
         c.category, c.intro, c.link, c.season::int
  from speech_challenges c
  join speech_seasons s on s.language = c.language and s.season = c.season
  left join ranked me on me.challenge_id = c.id and me.user_id = auth.uid()
  where c.language = p_language
    and s.min_scoring <= p_scoring
    and (s.opened_at is not null or speech_is_admin())
  order by (c.is_active and s.ended_at is null) desc, c.published_at desc;
$$;
revoke all on function public.speech_challenge_list_v2(text, int) from public;
grant execute on function public.speech_challenge_list_v2(text, int) to anon, authenticated;

-- The list every shipped build calls: Season 1 only, exactly as before.
create or replace function public.speech_challenge_list(p_language text)
returns table (
  id uuid, title text, genre text, body text, summary text,
  key_terms jsonb, sources jsonb, target_seconds int, published_at timestamptz,
  retired_at timestamptz,
  entrants int, top_score int, my_best int, my_rank int, my_attempts int,
  top_three jsonb, attempts int, category text, intro jsonb, link text
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
         c.category, c.intro, c.link
  from speech_challenges c
  left join ranked me on me.challenge_id = c.id and me.user_id = auth.uid()
  where c.language = p_language
    and c.season = 1
  order by c.is_active desc, c.published_at desc;
$$;

-- ---------------------------------------------------------------------------
-- The overall board: per season for a build that knows seasons; Season 1 for
-- every shipped build.

create or replace function public.speech_overall_board_v2(p_language text, p_season int, p_limit int default 10)
returns table (rank int, display_name text, avatar text, score int, is_me boolean, core_theme smallint, challenges int)
language sql stable security definer set search_path = public as $$
  with totals as (
    select e.user_id,
           sum(e.best_score)::int as total,
           count(*)::int as n,
           max(e.best_at) as reached_at
    from speech_challenge_entries e
    join speech_challenges c on c.id = e.challenge_id
    where c.language = p_language and c.season = p_season
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
revoke all on function public.speech_overall_board_v2(text, int, int) from public;
grant execute on function public.speech_overall_board_v2(text, int, int) to authenticated;

create or replace function public.speech_overall_board(p_language text, p_limit integer default 10)
returns table (rank int, display_name text, avatar text, score int, is_me boolean, core_theme smallint, challenges int)
language sql stable security definer set search_path = public as $$
  select * from public.speech_overall_board_v2(p_language, 1, p_limit);
$$;

-- ---------------------------------------------------------------------------
-- Submitting from a shipped build (scoring 2 or 3): the eleven-argument
-- function every other one hands over to. From 20261104190000, plus the
-- season: a closed season writes nothing and answers with the standing as it
-- is, so the take is a practice on a build that can't say so.

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
  v_season record;
begin
  if v_uid is null then raise exception 'NOT_SIGNED_IN'; end if;
  if not exists (select 1 from speech_challenges where id = p_challenge and is_active) then
    raise exception 'CHALLENGE_NOT_FOUND';
  end if;
  select s.min_scoring, s.ended_at into v_season
    from speech_challenges c
    join speech_seasons s on s.language = c.language and s.season = c.season
   where c.id = p_challenge;
  if v_season.min_scoring > 3 then raise exception 'NEEDS_UPDATE'; end if;
  if v_season.ended_at is not null then
    select e.best_score into v_prev_best
      from speech_challenge_entries e
     where e.challenge_id = p_challenge and e.user_id = v_uid;
    return query
    select 1 + (select count(*)::int from speech_challenge_entries x
                 where x.challenge_id = p_challenge
                   and x.best_score > coalesce(v_prev_best, p_overall)),
           null::int,
           (select count(*)::int from speech_challenge_entries x where x.challenge_id = p_challenge),
           coalesce(v_prev_best, p_overall),
           false;
    return;
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

-- ---------------------------------------------------------------------------
-- Submitting a Season 2 take. The score is rechecked from its five parts
-- (`SpeechReadingScore.total`). Entries reuse the table's columns:
-- pace_score = speed, pause_score = pauses, steadiness = rhythm.

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
  if least(p_speed, p_rhythm, p_pauses, p_accuracy, p_pronunciation) >= 95 and p_coverage >= 0.999 then
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
revoke all on function public.submit_speech_reading_take(uuid, text, int, int, int, int, int, int, double precision, int, int, text) from public;
grant execute on function public.submit_speech_reading_take(uuid, text, int, int, int, int, int, int, double precision, int, int, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The switch. Run by the founder when the build is out and Android has the
-- scoring: select open_speech_season('en', 2);
-- Ends every earlier season of the language in the same statement. From the
-- SQL console (no signed-in user) or an admin account.

create or replace function public.open_speech_season(p_language text, p_season int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not speech_is_admin() then raise exception 'NOT_ADMIN'; end if;
  if not exists (select 1 from speech_seasons where language = p_language and season = p_season) then
    raise exception 'NO_SUCH_SEASON';
  end if;
  update speech_seasons
     set ended_at = now()
   where language = p_language and season < p_season and ended_at is null;
  update speech_seasons
     set opened_at = coalesce(opened_at, now()), ended_at = null
   where language = p_language and season = p_season;
end;
$$;
revoke all on function public.open_speech_season(text, int) from public, anon;
grant execute on function public.open_speech_season(text, int) to authenticated;

notify pgrst, 'reload schema';
