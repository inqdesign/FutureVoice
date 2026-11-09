-- Who can see a season before it opens (2026-11-09, founder testing on a phone
-- signed in to an account without `unlimited`). A tester sees and can enter a
-- draft season; nothing else about the account changes. Opening a season stays
-- with admin accounts and the SQL console.

create table if not exists public.speech_season_testers (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now()
);
alter table public.speech_season_testers enable row level security;  -- through the functions only

-- Named for its first use; what it answers now is "may see draft seasons".
create or replace function public.speech_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_credits where user_id = auth.uid() and unlimited)
      or exists (select 1 from speech_season_testers where user_id = auth.uid());
$$;

create or replace function public.open_speech_season(p_language text, p_season int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and not exists (select 1 from user_credits where user_id = auth.uid() and unlimited) then
    raise exception 'NOT_ADMIN';
  end if;
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

insert into public.speech_season_testers (user_id)
values ('3cad242a-aa84-4dcd-8f85-ef4b7262b309')  -- nawana.review@gmail.com
on conflict (user_id) do nothing;

-- One challenge to test with: the shortest English script, in the draft
-- season (the insert trigger puts it there). Delete it before Season 2 opens.
insert into public.speech_challenges
  (language, title, genre, body, summary, key_terms, sources, target_seconds, created_by)
select c.language, '[Test] ' || c.title, c.genre, c.body, c.summary, c.key_terms, c.sources,
       c.target_seconds, c.created_by
from public.speech_challenges c
where c.language = 'en' and c.season = 1 and c.is_active
  and not exists (select 1 from public.speech_challenges t where t.language = 'en' and t.season = 2)
order by c.target_seconds, c.published_at
limit 1;

notify pgrst, 'reload schema';
