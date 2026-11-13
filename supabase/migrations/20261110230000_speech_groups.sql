-- Speech groups (2026-11-10, founder): friends, or people who study
-- together, racing each other on the same scripts like a night at the
-- karaoke. A group is joined only by its invite code; nobody can find one.
--
-- Two kinds of group challenge (founder's pick: both):
--   * a pick: any member hangs one of the language's challenges on the group;
--   * a script: a subscriber posts a script of their own, seen only there.
--
-- Group boards are LOOSE (founder's pick): every scored take counts, camera
-- or not, over the public bar or not, best one stands. The public boards keep
-- their own rules and their own table; nothing here touches them. A loose
-- score belongs to the learner and the script, not to a group, so a take
-- counts in every group the learner is in, and a group joined later sees
-- the best already on file.
--
-- Names and photos are the public boards' own (`speech_challenge_profiles`).
-- Every table is read only through the functions below.

create table if not exists public.speech_groups (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(name) between 1 and 40),
  language     text not null,
  invite_code  text not null unique,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);

create table if not exists public.speech_group_members (
  group_id   uuid not null references public.speech_groups(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists speech_group_members_user_idx on public.speech_group_members(user_id);

-- A public challenge hung on a group.
create table if not exists public.speech_group_picks (
  group_id      uuid not null references public.speech_groups(id) on delete cascade,
  challenge_id  uuid not null references public.speech_challenges(id) on delete cascade,
  picked_by     uuid references auth.users(id) on delete set null,
  picked_at     timestamptz not null default now(),
  primary key (group_id, challenge_id)
);

-- A subscriber's own script, posted to one group.
create table if not exists public.speech_group_scripts (
  id              uuid primary key default gen_random_uuid(),
  group_id        uuid not null references public.speech_groups(id) on delete cascade,
  posted_by       uuid references auth.users(id) on delete set null,
  title           text not null check (char_length(title) between 1 and 120),
  genre           text not null,
  body            text not null check (char_length(body) between 1 and 6000),
  summary         text not null default '',
  target_seconds  int  not null default 60,
  created_at      timestamptz not null default now(),
  removed_at      timestamptz
);
create index if not exists speech_group_scripts_group_idx on public.speech_group_scripts(group_id);

-- The loose best per learner per script (a challenge id or a group script id).
create table if not exists public.speech_friendly_scores (
  script_id   uuid not null,
  user_id     uuid not null references auth.users(id) on delete cascade,
  best_score  int  not null check (best_score between 0 and 100),
  attempts    int  not null default 1,
  best_at     timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (script_id, user_id)
);

alter table public.speech_groups enable row level security;
alter table public.speech_group_members enable row level security;
alter table public.speech_group_picks enable row level security;
alter table public.speech_group_scripts enable row level security;
alter table public.speech_friendly_scores enable row level security;

-- ---------------------------------------------------------------------------
create or replace function public.speech_is_group_member(p_group uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from speech_group_members
                  where group_id = p_group and user_id = auth.uid());
$$;

-- Six letters and digits nobody misreads (no 0/O, 1/I/L).
create or replace function public.speech_new_invite_code()
returns text
language plpgsql volatile set search_path = public as $$
declare
  v_chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    end loop;
    exit when not exists (select 1 from speech_groups where invite_code = v_code);
  end loop;
  return v_code;
end;
$$;

-- ---------------------------------------------------------------------------
-- The caller's groups in a language.
create or replace function public.my_speech_groups(p_language text)
returns table (id uuid, name text, invite_code text, members int, is_creator boolean)
language sql stable security definer set search_path = public as $$
  select g.id, g.name, g.invite_code,
         (select count(*)::int from speech_group_members m2 where m2.group_id = g.id),
         g.created_by = auth.uid()
  from speech_groups g
  join speech_group_members m on m.group_id = g.id and m.user_id = auth.uid()
  where g.language = p_language
  order by m.joined_at;
$$;

create or replace function public.create_speech_group(p_name text, p_language text)
returns table (id uuid, name text, invite_code text, members int, is_creator boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'NOT_SIGNED_IN'; end if;
  if char_length(v_name) < 1 or char_length(v_name) > 40 then raise exception 'BAD_NAME'; end if;
  if (select count(*) from speech_group_members where user_id = auth.uid()) >= 20 then
    raise exception 'TOO_MANY_GROUPS';
  end if;
  insert into speech_groups (name, language, invite_code, created_by)
  values (v_name, p_language, speech_new_invite_code(), auth.uid())
  returning speech_groups.id into v_id;
  insert into speech_group_members (group_id, user_id) values (v_id, auth.uid());
  return query
    select g.id, g.name, g.invite_code, 1, true from speech_groups g where g.id = v_id;
end;
$$;

create or replace function public.join_speech_group(p_code text)
returns table (id uuid, name text, invite_code text, members int, is_creator boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_group speech_groups%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_SIGNED_IN'; end if;
  select * into v_group from speech_groups
   where invite_code = upper(btrim(coalesce(p_code, '')));
  if not found then raise exception 'NO_SUCH_GROUP'; end if;
  if not exists (select 1 from speech_group_members
                  where group_id = v_group.id and user_id = auth.uid()) then
    if (select count(*) from speech_group_members where group_id = v_group.id) >= 50 then
      raise exception 'GROUP_FULL';
    end if;
    if (select count(*) from speech_group_members where user_id = auth.uid()) >= 20 then
      raise exception 'TOO_MANY_GROUPS';
    end if;
    insert into speech_group_members (group_id, user_id) values (v_group.id, auth.uid());
  end if;
  return query
    select g.id, g.name, g.invite_code,
           (select count(*)::int from speech_group_members m where m.group_id = g.id),
           g.created_by = auth.uid()
    from speech_groups g where g.id = v_group.id;
end;
$$;

-- Leaving the last seat closes the group.
create or replace function public.leave_speech_group(p_group uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from speech_group_members where group_id = p_group and user_id = auth.uid();
  if not exists (select 1 from speech_group_members where group_id = p_group) then
    delete from speech_groups where id = p_group;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- A loose score: any scored take, best one stands. A script is a live or
-- past public challenge, or a group script of a group the caller is in.
create or replace function public.submit_speech_friendly_score(p_script uuid, p_score int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'NOT_SIGNED_IN'; end if;
  if p_score is null or p_score < 0 or p_score > 100 then raise exception 'BAD_SCORE'; end if;
  if not exists (select 1 from speech_challenges where id = p_script)
     and not exists (select 1 from speech_group_scripts s
                      where s.id = p_script and s.removed_at is null
                        and speech_is_group_member(s.group_id)) then
    raise exception 'NO_SUCH_SCRIPT';
  end if;
  insert into speech_friendly_scores (script_id, user_id, best_score)
  values (p_script, auth.uid(), p_score)
  on conflict (script_id, user_id) do update set
    attempts   = speech_friendly_scores.attempts + 1,
    best_at    = case when excluded.best_score > speech_friendly_scores.best_score
                      then now() else speech_friendly_scores.best_at end,
    best_score = greatest(speech_friendly_scores.best_score, excluded.best_score),
    updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Who leads a group: each member's best per script added up, over every
-- public challenge of the group's language and the group's own scripts.
-- Every member is listed, zero included: it's a room of people you know.
create or replace function public.speech_group_leaders(p_group uuid)
returns table (rank int, display_name text, avatar text, score int, challenges int, is_me boolean)
language sql stable security definer set search_path = public as $$
  with totals as (
    select m.user_id,
           coalesce(sum(f.best_score), 0)::int as total,
           count(f.script_id)::int as n,
           min(m.joined_at) as joined_at
    from speech_group_members m
    join speech_groups g on g.id = m.group_id
    left join speech_friendly_scores f on f.user_id = m.user_id
      and (f.script_id in (select c.id from speech_challenges c where c.language = g.language)
           or f.script_id in (select s.id from speech_group_scripts s
                               where s.group_id = g.id and s.removed_at is null))
    where m.group_id = p_group
    group by m.user_id
  )
  select rank() over (order by t.total desc)::int,
         coalesce(p.display_name, ''), p.avatar_jpeg, t.total, t.n,
         t.user_id = auth.uid()
  from totals t
  left join speech_challenge_profiles p on p.user_id = t.user_id
  where speech_is_group_member(p_group)
  order by t.total desc, t.joined_at;
$$;

-- One script's board inside a group: members who have read it.
create or replace function public.speech_group_board(p_group uuid, p_script uuid)
returns table (rank int, display_name text, avatar text, score int, attempts int, is_me boolean)
language sql stable security definer set search_path = public as $$
  select rank() over (order by f.best_score desc)::int,
         coalesce(p.display_name, ''), p.avatar_jpeg, f.best_score, f.attempts,
         f.user_id = auth.uid()
  from speech_friendly_scores f
  join speech_group_members m on m.user_id = f.user_id and m.group_id = p_group
  left join speech_challenge_profiles p on p.user_id = f.user_id
  where f.script_id = p_script and speech_is_group_member(p_group)
  order by f.best_score desc, f.best_at;
$$;

-- ---------------------------------------------------------------------------
-- The group's challenges, newest first: picks carry the challenge id (the app
-- has its script), group scripts carry their text.
create or replace function public.speech_group_challenges(p_group uuid)
returns table (
  kind text, id uuid, title text, genre text, body text, summary text,
  target_seconds int, added_at timestamptz, added_by text, added_by_me boolean,
  tried int, my_best int, top_three jsonb
)
language sql stable security definer set search_path = public as $$
  with items as (
    select 'pick'::text as kind, c.id, c.title, c.genre, ''::text as body, c.summary,
           c.target_seconds, k.picked_at as added_at, k.picked_by as by_user
    from speech_group_picks k join speech_challenges c on c.id = k.challenge_id
    where k.group_id = p_group
    union all
    select 'script', s.id, s.title, s.genre, s.body, s.summary,
           s.target_seconds, s.created_at, s.posted_by
    from speech_group_scripts s
    where s.group_id = p_group and s.removed_at is null
  ), scores as (
    select f.script_id, f.user_id, f.best_score, f.best_at
    from speech_friendly_scores f
    join speech_group_members m on m.user_id = f.user_id and m.group_id = p_group
    where f.script_id in (select id from items)
  )
  select i.kind, i.id, i.title, i.genre, i.body, i.summary, i.target_seconds, i.added_at,
         coalesce((select p.display_name from speech_challenge_profiles p where p.user_id = i.by_user), ''),
         i.by_user = auth.uid(),
         (select count(*)::int from scores x where x.script_id = i.id),
         (select x.best_score from scores x where x.script_id = i.id and x.user_id = auth.uid()),
         coalesce((
           select jsonb_agg(jsonb_build_object('display_name', t.display_name, 'avatar', t.avatar_jpeg)
                            order by t.best_score desc, t.best_at)
           from (
             select coalesce(p.display_name, '') as display_name, p.avatar_jpeg, x.best_score, x.best_at
             from scores x left join speech_challenge_profiles p on p.user_id = x.user_id
             where x.script_id = i.id
             order by x.best_score desc, x.best_at
             limit 3
           ) t
         ), '[]'::jsonb)
  from items i
  where speech_is_group_member(p_group)
  order by i.added_at desc;
$$;

create or replace function public.pick_speech_group_challenge(p_group uuid, p_challenge uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not speech_is_group_member(p_group) then raise exception 'NOT_A_MEMBER'; end if;
  insert into speech_group_picks (group_id, challenge_id, picked_by)
  values (p_group, p_challenge, auth.uid())
  on conflict (group_id, challenge_id) do update set picked_at = now(), picked_by = auth.uid();
end;
$$;

-- Posting a script of your own is a subscriber's (the same rule as writing
-- one in the app).
create or replace function public.post_speech_group_script(
  p_group uuid, p_title text, p_genre text, p_body text, p_summary text, p_target_seconds int)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not speech_is_group_member(p_group) then raise exception 'NOT_A_MEMBER'; end if;
  if not voice_owner_is_entitled(auth.uid()) then raise exception 'NOT_SUBSCRIBED'; end if;
  insert into speech_group_scripts (group_id, posted_by, title, genre, body, summary, target_seconds)
  values (p_group, auth.uid(), btrim(p_title), coalesce(p_genre, 'explainer'), p_body,
          coalesce(p_summary, ''), greatest(10, least(coalesce(p_target_seconds, 60), 900)))
  returning id into v_id;
  return v_id;
end;
$$;

-- Taking a group challenge down: whoever hung it, or whoever made the group.
create or replace function public.remove_speech_group_challenge(p_group uuid, p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_creator boolean := exists (select 1 from speech_groups where id = p_group and created_by = auth.uid());
begin
  if not speech_is_group_member(p_group) then raise exception 'NOT_A_MEMBER'; end if;
  delete from speech_group_picks
   where group_id = p_group and challenge_id = p_id and (picked_by = auth.uid() or v_creator);
  update speech_group_scripts set removed_at = now()
   where group_id = p_group and id = p_id and removed_at is null
     and (posted_by = auth.uid() or v_creator);
end;
$$;

revoke all on function public.speech_new_invite_code() from public, anon, authenticated;
revoke all on function public.speech_is_group_member(uuid) from public, anon;
grant execute on function public.speech_is_group_member(uuid) to authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'my_speech_groups(text)', 'create_speech_group(text, text)', 'join_speech_group(text)',
    'leave_speech_group(uuid)', 'submit_speech_friendly_score(uuid, int)',
    'speech_group_leaders(uuid)', 'speech_group_board(uuid, uuid)',
    'speech_group_challenges(uuid)', 'pick_speech_group_challenge(uuid, uuid)',
    'post_speech_group_script(uuid, text, text, text, text, int)',
    'remove_speech_group_challenge(uuid, uuid)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
