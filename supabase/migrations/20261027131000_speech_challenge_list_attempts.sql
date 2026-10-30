-- The challenge card counts TRIES, not people (founder, 2026-10-27).
--
-- "12 taking part" reads small on a board that is days old; how many times
-- people have stood up and read it is the livelier number, and it is the one
-- that says "people keep coming back to this". `speech_challenge_entries
-- .attempts` already counts every take a learner put up, so the list adds
-- their sum as `attempts`, last, beside everything it returned before.
--
-- Builds that don't know the column ignore it (Swift Decodable, Kotlin
-- `ignoreUnknownKeys`). The return type changes, so the function is dropped
-- and made again with the same argument list and the same grants.

drop function if exists public.speech_challenge_list(text);
create function public.speech_challenge_list(p_language text)
returns table (
  id uuid, title text, genre text, body text, summary text,
  key_terms jsonb, sources jsonb, target_seconds int, published_at timestamptz,
  retired_at timestamptz,
  entrants int, top_score int, my_best int, my_rank int, my_attempts int,
  top_three jsonb, attempts int
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
         (select coalesce(sum(x.attempts), 0)::int from ranked x where x.challenge_id = c.id)
  from speech_challenges c
  left join ranked me on me.challenge_id = c.id and me.user_id = auth.uid()
  where c.language = p_language
  order by c.is_active desc, c.published_at desc;
$$;

revoke all on function public.speech_challenge_list(text) from public;
grant execute on function public.speech_challenge_list(text) to authenticated;
