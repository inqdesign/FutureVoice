-- One board over every speech challenge of a language (founder, 2026-11-05).
--
-- Each challenge counts once per learner: their BEST take on it, the number
-- its own board shows. The overall score is the sum of those, so two 100s on
-- one challenge are still one 100, and the way up is to take more challenges.
-- Past (retired) challenges count too: their boards are frozen, and what was
-- earned there stays earned. Entries scored before pronunciation counted
-- (scoring 2) stand as they are, like on the challenge boards.
--
-- Same shape and rules as `speech_challenge_board`: a name, a face, a number,
-- never a user id; the top `p_limit` plus the caller's own row. `challenges`
-- is how many challenges that learner's total is made of. Ties share a rank
-- and are listed by who reached the total first.

create or replace function public.speech_overall_board(p_language text, p_limit int default 10)
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
revoke all on function public.speech_overall_board(text, int) from public;
grant execute on function public.speech_overall_board(text, int) to authenticated;
