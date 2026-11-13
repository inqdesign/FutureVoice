-- The speech app's own boards (2026-11-12, founder: "in this app the past
-- challenges are new challenges too; don't tie it to nawana").
--
-- nawana keeps its seasons: a challenge retires, its board freezes, Season 1
-- boards hold the old scoring. The speech app has none of that. Every
-- challenge of a language is open there, on a board of its own, scored one
-- way (the reading score, `SpeechReading`, version 4). Nothing here reads or
-- writes nawana's entries, and nothing of nawana's reads these: a learner's
-- nawana scores do not appear in the app and the app's do not appear in
-- nawana. The name and photo are the same profile on both
-- (`speech_challenge_profiles`), because they are the same person.
--
-- A challenge appears once nawana has published it (a Season 2 draft, not yet
-- opened, stays hidden as there). Retiring it in nawana does not touch it here.

create table if not exists public.speech_app_entries (
  challenge_id   uuid not null references public.speech_challenges(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade,
  best_score     int  not null check (best_score between 0 and 100),
  speed          int  not null,
  rhythm         int  not null,
  pauses         int  not null,
  accuracy       int  not null,
  pronunciation  int  not null,
  seconds        int  not null,
  attempts       int  not null default 1,
  best_at        timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (challenge_id, user_id)
);
create index if not exists speech_app_entries_board_idx
  on public.speech_app_entries(challenge_id, best_score desc, best_at);

-- Read only through the functions below.
alter table public.speech_app_entries enable row level security;

-- A challenge the app shows: active, and in a season that has opened.
create or replace function public.speech_app_challenge_shown(p_challenge uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from speech_challenges c
    join speech_seasons s on s.language = c.language and s.season = c.season
    where c.id = p_challenge and (s.opened_at is not null or speech_is_admin())
  );
$$;

-- ---------------------------------------------------------------------------
-- The list: every challenge of the language, newest first, none of them past.
-- Same shape as `speech_challenge_list_v2`, so the app decodes one row type.
create or replace function public.speech_app_challenge_list(p_language text)
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
    from speech_app_entries e
    join speech_challenges c on c.id = e.challenge_id
    where c.language = p_language
  )
  select c.id, c.title, c.genre, c.body, c.summary, c.key_terms, c.sources,
         c.target_seconds, c.published_at,
         null::timestamptz,
         (select count(*)::int from ranked x where x.challenge_id = c.id),
         (select max(x.best_score) from ranked x where x.challenge_id = c.id),
         me.best_score, me.r::int, me.attempts,
         coalesce((
           select jsonb_agg(jsonb_build_object('display_name', t.display_name, 'avatar', t.avatar_jpeg)
                            order by t.best_score desc, t.best_at)
           from (
             select p.display_name, p.avatar_jpeg, e.best_score, e.best_at
             from speech_app_entries e
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
    and (s.opened_at is not null or speech_is_admin())
  order by c.published_at desc;
$$;

-- One challenge's board: the top N and the caller's own row.
create or replace function public.speech_app_board(p_challenge uuid, p_limit int default 10)
returns table (rank int, display_name text, avatar text, score int, is_me boolean)
language sql stable security definer set search_path = public as $$
  with ranked as (
    select e.user_id, p.display_name, p.avatar_jpeg, e.best_score, e.best_at,
           rank() over (order by e.best_score desc)::int as r,
           row_number() over (order by e.best_score desc, e.best_at) as pos
    from speech_app_entries e
    join speech_challenge_profiles p on p.user_id = e.user_id
    where e.challenge_id = p_challenge
  )
  select r, display_name, avatar_jpeg, best_score, ranked.user_id = auth.uid()
  from ranked
  where pos <= least(greatest(p_limit, 1), 50) or ranked.user_id = auth.uid()
  order by pos;
$$;

-- Everyone's best per challenge, added up.
create or replace function public.speech_app_overall_board(p_language text, p_limit int default 10)
returns table (rank int, display_name text, avatar text, score int, is_me boolean, challenges int)
language sql stable security definer set search_path = public as $$
  with totals as (
    select e.user_id, sum(e.best_score)::int as total, count(*)::int as n, max(e.best_at) as reached_at
    from speech_app_entries e
    join speech_challenges c on c.id = e.challenge_id
    where c.language = p_language
    group by e.user_id
  ),
  ranked as (
    select t.user_id, p.display_name, p.avatar_jpeg, t.total, t.n,
           rank() over (order by t.total desc)::int as r,
           row_number() over (order by t.total desc, t.reached_at) as pos
    from totals t
    join speech_challenge_profiles p on p.user_id = t.user_id
  )
  select r, display_name, avatar_jpeg, total, ranked.user_id = auth.uid(), n
  from ranked
  where pos <= least(greatest(p_limit, 1), 50) or ranked.user_id = auth.uid()
  order by pos;
$$;

-- ---------------------------------------------------------------------------
-- A take, scored by reading against a native reference. The total is checked
-- against its parts by the same formula as `submit_speech_reading_take`
-- (20261109170000); keep the two in step. Best stands, every take counted.
create or replace function public.submit_speech_app_take(
  p_challenge uuid, p_display_name text,
  p_overall int, p_speed int, p_rhythm int, p_pauses int, p_accuracy int,
  p_pronunciation int, p_coverage double precision, p_seconds int, p_scoring int,
  p_avatar text default null
)
returns table (rank int, previous_rank int, entrants int, best int, improved boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_expected int;
  v_prev_best int;
  v_prev_rank int;
  v_improved boolean;
begin
  if v_uid is null then raise exception 'NOT_SIGNED_IN'; end if;
  if not speech_app_challenge_shown(p_challenge) then raise exception 'CHALLENGE_NOT_FOUND'; end if;
  if p_scoring < 4 then raise exception 'NEEDS_UPDATE'; end if;
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
  from speech_app_entries e where e.challenge_id = p_challenge and e.user_id = v_uid;
  if v_prev_best is not null then
    select 1 + count(*)::int into v_prev_rank
    from speech_app_entries e where e.challenge_id = p_challenge and e.best_score > v_prev_best;
  end if;
  v_improved := v_prev_best is null or p_overall > v_prev_best;

  insert into speech_app_entries as e
    (challenge_id, user_id, best_score, speed, rhythm, pauses, accuracy, pronunciation, seconds)
  values (p_challenge, v_uid, p_overall, p_speed, p_rhythm, p_pauses, p_accuracy, p_pronunciation, p_seconds)
  on conflict (challenge_id, user_id) do update set
    attempts      = e.attempts + 1,
    updated_at    = now(),
    best_score    = case when v_improved then excluded.best_score    else e.best_score end,
    speed         = case when v_improved then excluded.speed         else e.speed end,
    rhythm        = case when v_improved then excluded.rhythm        else e.rhythm end,
    pauses        = case when v_improved then excluded.pauses        else e.pauses end,
    accuracy      = case when v_improved then excluded.accuracy      else e.accuracy end,
    pronunciation = case when v_improved then excluded.pronunciation else e.pronunciation end,
    seconds       = case when v_improved then excluded.seconds       else e.seconds end,
    best_at       = case when v_improved then now()                  else e.best_at end;

  return query
  select 1 + (select count(*)::int from speech_app_entries x
              where x.challenge_id = p_challenge and x.best_score > me.best_score),
         v_prev_rank,
         (select count(*)::int from speech_app_entries x where x.challenge_id = p_challenge),
         me.best_score,
         v_improved
  from speech_app_entries me
  where me.challenge_id = p_challenge and me.user_id = v_uid;
end;
$$;

create or replace function public.withdraw_speech_app_entry(p_challenge uuid)
returns void
language sql security definer set search_path = public as $$
  delete from speech_app_entries where challenge_id = p_challenge and user_id = auth.uid();
$$;

-- The caller's name and photo on the boards, so a learner who already has
-- one (from nawana) keeps it in the app without being on an app board yet.
create or replace function public.my_speech_challenge_profile()
returns table (display_name text, avatar text)
language sql stable security definer set search_path = public as $$
  select p.display_name, p.avatar_jpeg from speech_challenge_profiles p where p.user_id = auth.uid();
$$;

revoke all on function public.my_speech_challenge_profile() from public, anon;
grant execute on function public.my_speech_challenge_profile() to authenticated;
revoke all on function public.speech_app_challenge_shown(uuid) from public, anon;
grant execute on function public.speech_app_challenge_shown(uuid) to authenticated;
revoke all on function public.speech_app_challenge_list(text) from public;
grant execute on function public.speech_app_challenge_list(text) to anon, authenticated;
revoke all on function public.speech_app_board(uuid, int) from public;
grant execute on function public.speech_app_board(uuid, int) to authenticated;
revoke all on function public.speech_app_overall_board(text, int) from public;
grant execute on function public.speech_app_overall_board(text, int) to authenticated;
revoke all on function public.submit_speech_app_take(uuid, text, int, int, int, int, int, int, double precision, int, int, text) from public, anon;
grant execute on function public.submit_speech_app_take(uuid, text, int, int, int, int, int, int, double precision, int, int, text) to authenticated;
revoke all on function public.withdraw_speech_app_entry(uuid) from public, anon;
grant execute on function public.withdraw_speech_app_entry(uuid) to authenticated;
