-- Speech challenges, two follow-ups (2026-10-11, founder):
--   * a retired challenge is PAST, not gone: its board stays readable, frozen,
--     with the learner's final place — the list returns every challenge with
--     `retired_at`, and the board no longer filters on is_active (taking a
--     past challenge is still refused by submit_speech_challenge_take);
--   * the board's rows carry the photo the list's top three already carry, so
--     the top three can be drawn large with their faces.
-- No shipped build calls these functions yet, so the return types change in
-- place (dropped first — `create or replace` can't change a return type and
-- would leave an overload behind).

alter table public.speech_challenges add column if not exists retired_at timestamptz;
update public.speech_challenges set retired_at = now() where not is_active and retired_at is null;

create or replace function public.retire_speech_challenge(p_challenge uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from user_credits where user_id = auth.uid() and unlimited) then
    raise exception 'NOT_ADMIN';
  end if;
  update speech_challenges set is_active = false, retired_at = coalesce(retired_at, now())
  where id = p_challenge;
end;
$$;

drop function if exists public.speech_challenge_list(text);
create function public.speech_challenge_list(p_language text)
returns table (
  id uuid, title text, genre text, body text, summary text,
  key_terms jsonb, sources jsonb, target_seconds int, published_at timestamptz,
  retired_at timestamptz,
  entrants int, top_score int, my_best int, my_rank int, my_attempts int,
  top_three jsonb
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
         ), '[]'::jsonb)
  from speech_challenges c
  left join ranked me on me.challenge_id = c.id and me.user_id = auth.uid()
  where c.language = p_language
  order by c.is_active desc, c.published_at desc;
$$;

drop function if exists public.speech_challenge_board(uuid, int);
create function public.speech_challenge_board(p_challenge uuid, p_limit int default 10)
returns table (rank int, display_name text, avatar text, score int, is_me boolean)
language sql stable security definer set search_path = public as $$
  with ranked as (
    select e.user_id, p.display_name, p.avatar_jpeg, e.best_score, e.best_at,
           rank() over (order by e.best_score desc)::int as r,
           row_number() over (order by e.best_score desc, e.best_at) as pos
    from speech_challenge_entries e
    join speech_challenge_profiles p on p.user_id = e.user_id
    where e.challenge_id = p_challenge
  )
  select r, display_name, avatar_jpeg, best_score, user_id = auth.uid()
  from ranked
  where pos <= least(greatest(p_limit, 1), 50) or user_id = auth.uid()
  order by pos;
$$;

revoke all on function public.speech_challenge_list(text) from public;
revoke all on function public.speech_challenge_board(uuid, int) from public;
grant execute on function public.speech_challenge_list(text) to authenticated;
grant execute on function public.speech_challenge_board(uuid, int) to authenticated;
