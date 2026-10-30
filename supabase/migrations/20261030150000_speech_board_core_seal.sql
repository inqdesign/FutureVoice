-- A speech board shows who is in the Core (founder, 2026-10-30).
--
-- The seal was drawn only in Find people, and a seated member (Olivia, en)
-- stood at the top of four English boards with nothing beside her name.
-- Boards are the other place a learner is seen by strangers, so the seal goes
-- there too, under the same rule as everywhere: seated in the club of the
-- CHALLENGE's language, today. Still no user id leaves the function; `core`
-- is one boolean, appended last.
--
-- The return type changes, so the function is dropped and made again with
-- the same arguments and grants. Builds that don't know the column ignore it
-- (Swift Decodable, Kotlin `ignoreUnknownKeys`).

drop function if exists public.speech_challenge_board(uuid, int);
create function public.speech_challenge_board(p_challenge uuid, p_limit int default 10)
returns table (rank int, display_name text, avatar text, score int, is_me boolean, core boolean)
language sql stable security definer set search_path = public as $$
  with ranked as (
    select e.user_id, p.display_name, p.avatar_jpeg, e.best_score, e.best_at,
           rank() over (order by e.best_score desc)::int as r,
           row_number() over (order by e.best_score desc, e.best_at) as pos
    from speech_challenge_entries e
    join speech_challenge_profiles p on p.user_id = e.user_id
    where e.challenge_id = p_challenge
  )
  select r, display_name, avatar_jpeg, best_score, ranked.user_id = auth.uid(),
         exists (
           select 1
             from core_membership m
             join speech_challenges c on c.id = p_challenge
            where m.user_id = ranked.user_id
              and m.language = c.language
              and m.seated
         )
  from ranked
  where pos <= least(greatest(p_limit, 1), 50) or ranked.user_id = auth.uid()
  order by pos;
$$;
revoke all on function public.speech_challenge_board(uuid, int) from public;
grant execute on function public.speech_challenge_board(uuid, int) to authenticated;
