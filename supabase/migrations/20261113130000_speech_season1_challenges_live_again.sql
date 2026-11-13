-- English Season 1's challenges are live again (2026-11-13, founder: "there
-- was no reason to archive the list; the scoring changed. Keep Season 1's
-- scores, but the challenges should be alive. It's about the winner").
--
-- A board row is one per (challenge, person), so reopening a Season 1
-- challenge in place would let a new-scoring take overwrite an old score and
-- move Season 1's total and its winner. So:
--
-- 1. Season 1's results are FROZEN into `speech_season_entries`, exactly as
--    they stand (nothing has been entered on them since the season ended:
--    submit refuses an ended season). Season 1's overall board reads them
--    from now on, so its standings and winner never move again.
-- 2. The seven challenges move into Season 2 (`revived_from` = 1) and their
--    live boards start empty, scored the Season 2 way like every other
--    Season 2 challenge, and counted in Season 2's total.
-- 3. A build that can't score Season 2 (scoring < the season's bar) keeps
--    seeing them exactly as before: past, Season 1, practice only, with the
--    frozen numbers. `speech_challenge_list` (pre-season builds) is the same
--    list at scoring 3.
-- 4. `my_speech_season_records` gives the app the learner's own frozen score
--    and place, so the challenge page can say "Season 1: 93 · #2".
--
-- Not covered: `speech_challenge_board` has no build version, so an old
-- build opening one of these sees the live Season 2 board under it.

-- 1. The frozen results.
create table if not exists public.speech_season_entries (
  language text not null,
  season int not null,
  challenge_id uuid not null references public.speech_challenges(id) on delete cascade,
  user_id uuid not null,
  best_score int not null,
  attempts int not null default 0,
  best_at timestamptz,
  primary key (season, challenge_id, user_id)
);
alter table public.speech_season_entries enable row level security;
-- No policies: read only through the functions below.

alter table public.speech_challenges add column if not exists revived_from int;

do $$
begin
  -- Guard: run once. A second run would find the challenges already moved.
  if exists (select 1 from public.speech_challenges where language = 'en' and revived_from = 1) then
    raise notice 'already revived';
    return;
  end if;
  if not exists (select 1 from public.speech_seasons where language = 'en' and season = 1 and ended_at is not null) then
    raise exception 'English Season 1 has not ended';
  end if;

  insert into public.speech_season_entries (language, season, challenge_id, user_id, best_score, attempts, best_at)
  select 'en', 1, e.challenge_id, e.user_id, e.best_score, e.attempts, e.best_at
  from public.speech_challenge_entries e
  join public.speech_challenges c on c.id = e.challenge_id
  where c.language = 'en' and c.season = 1;

  delete from public.speech_challenge_entries e
  using public.speech_challenges c
  where c.id = e.challenge_id and c.language = 'en' and c.season = 1;

  update public.speech_challenges
  set season = 2, revived_from = 1
  where language = 'en' and season = 1 and is_active;
end $$;

-- 2. The list: a revived challenge is live to a build that can score its
-- season, and its old self (past, frozen numbers) to one that can't.
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
           (c.revived_from is not null and s.min_scoring > p_scoring) as as_past
    from speech_challenges c
    join speech_seasons s on s.language = c.language and s.season = c.season
    left join speech_seasons f on f.language = c.language and f.season = c.revived_from
    where c.language = p_language
      and (s.opened_at is not null or speech_is_admin())
      and (s.min_scoring <= p_scoring
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

-- Pre-season builds score at most 3: the same list, without the season.
create or replace function public.speech_challenge_list(p_language text)
returns table(id uuid, title text, genre text, body text, summary text, key_terms jsonb, sources jsonb,
              target_seconds integer, published_at timestamptz, retired_at timestamptz, entrants integer,
              top_score integer, my_best integer, my_rank integer, my_attempts integer, top_three jsonb,
              attempts integer, category text, intro jsonb, link text)
language sql stable security definer set search_path = public as $$
  select l.id, l.title, l.genre, l.body, l.summary, l.key_terms, l.sources, l.target_seconds,
         l.published_at, l.retired_at, l.entrants, l.top_score, l.my_best, l.my_rank, l.my_attempts,
         l.top_three, l.attempts, l.category, l.intro, l.link
  from speech_challenge_list_v2(p_language, 3) l
  where l.season = 1;
$$;

-- 3. A season's total: its live boards plus whatever was frozen for it.
create or replace function public.speech_overall_board_v2(p_language text, p_season integer, p_limit integer default 10)
returns table(rank integer, display_name text, avatar text, score integer, is_me boolean, core_theme smallint, challenges integer)
language sql stable security definer set search_path = public as $$
  with pool as (
    select e.user_id, e.best_score, e.best_at
    from speech_challenge_entries e
    join speech_challenges c on c.id = e.challenge_id
    where c.language = p_language and c.season = p_season
    union all
    select r.user_id, r.best_score, r.best_at
    from speech_season_entries r
    where r.language = p_language and r.season = p_season
  ),
  totals as (
    select p.user_id, sum(p.best_score)::int as total, count(*)::int as n, max(p.best_at) as reached_at
    from pool p
    group by p.user_id
  ),
  ranked as (
    select t.user_id, pr.display_name, pr.avatar_jpeg, t.total, t.n,
           rank() over (order by t.total desc)::int as r,
           row_number() over (order by t.total desc, t.reached_at) as pos
    from totals t
    join speech_challenge_profiles pr on pr.user_id = t.user_id
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

-- 4. The learner's own frozen scores, with their place on each.
create or replace function public.my_speech_season_records(p_language text)
returns table(challenge_id uuid, season integer, score integer, rank integer, entrants integer)
language sql stable security definer set search_path = public as $$
  with ranked as (
    select r.challenge_id, r.season, r.user_id, r.best_score,
           rank() over (partition by r.challenge_id, r.season order by r.best_score desc)::int as rk,
           count(*) over (partition by r.challenge_id, r.season)::int as n
    from speech_season_entries r
    where r.language = p_language
  )
  select x.challenge_id, x.season, x.best_score, x.rk, x.n
  from ranked x
  where x.user_id = auth.uid();
$$;

revoke all on function public.my_speech_season_records(text) from public;
grant execute on function public.my_speech_season_records(text) to authenticated;
