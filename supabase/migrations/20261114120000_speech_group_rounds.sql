-- A group plays ONE challenge at a time, with a deadline (2026-11-14,
-- founder). Someone sets a challenge (a public one, or a script of the
-- group's own) and when it ends; until then members practise and the page
-- shows who leads and who hasn't started; when time is up the best score
-- takes that challenge's CARD. The group's ranking is how many cards each
-- member holds.
--
-- Rules (founder agreed with these picks the same day):
--   1. Only takes made DURING the round count. A score read last month is
--      not a head start, so a round keeps its own scores
--      (`speech_group_round_scores`), written by the same
--      `submit_speech_friendly_score` every take already calls, so builds
--      already out count too.
--   2. Anyone sets the next round once nothing is running; the person who
--      set it (or the group's maker) can cancel it early. A cancelled round
--      gives no card.
--   3. A tie goes to whoever reached that score first.
--   4. Nobody read it: the round ends with no card.
--   5. A challenge can be played again later: it is a new round, a second
--      copy of the card, with its own winner.
--
-- Settling is LAZY: a round past its deadline is settled by the next read
-- or start in that group, so nothing has to run on a clock. The winner is
-- chosen among the members at that moment.
--
-- The earlier picks, group boards and `speech_group_leaders` stay as they
-- are for builds already out; the new app no longer reads them.

create table if not exists public.speech_group_rounds (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.speech_groups(id) on delete cascade,
  script_id     uuid not null,
  kind          text not null check (kind in ('challenge', 'script')),
  set_by        uuid references auth.users(id) on delete set null,
  started_at    timestamptz not null default now(),
  ends_at       timestamptz not null,
  cancelled_at  timestamptz,
  settled_at    timestamptz,
  winner_id     uuid references auth.users(id) on delete set null,
  winner_score  int
);
create index if not exists speech_group_rounds_group_idx
  on public.speech_group_rounds(group_id, started_at desc);
-- One round open per group: a new one can start only once the last is
-- settled or cancelled.
create unique index if not exists speech_group_rounds_one_open
  on public.speech_group_rounds(group_id)
  where settled_at is null and cancelled_at is null;

create table if not exists public.speech_group_round_scores (
  round_id    uuid not null references public.speech_group_rounds(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  best_score  int  not null check (best_score between 0 and 100),
  attempts    int  not null default 1,
  best_at     timestamptz not null default now(),
  primary key (round_id, user_id)
);

alter table public.speech_group_rounds enable row level security;
alter table public.speech_group_round_scores enable row level security;

-- ---------------------------------------------------------------------------
-- Rounds of a group past their deadline get their winner.
create or replace function public.speech_settle_group_rounds(p_group uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_user uuid;
  v_score int;
begin
  for r in
    select id from speech_group_rounds
     where group_id = p_group and settled_at is null and cancelled_at is null
       and ends_at <= now()
     for update skip locked
  loop
    v_user := null;
    v_score := null;
    select s.user_id, s.best_score into v_user, v_score
      from speech_group_round_scores s
      join speech_group_members m on m.group_id = p_group and m.user_id = s.user_id
     where s.round_id = r.id
     order by s.best_score desc, s.best_at
     limit 1;
    update speech_group_rounds
       set settled_at = now(),
           winner_id = v_user,
           winner_score = v_score
     where id = r.id;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- A take: the loose best as before, and the round's best for every round
-- running on this script in a group the learner is in.
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

  insert into speech_group_round_scores (round_id, user_id, best_score)
  select r.id, auth.uid(), p_score
    from speech_group_rounds r
    join speech_group_members m on m.group_id = r.group_id and m.user_id = auth.uid()
   where r.script_id = p_script
     and r.settled_at is null and r.cancelled_at is null
     and now() < r.ends_at
  on conflict (round_id, user_id) do update set
    attempts   = speech_group_round_scores.attempts + 1,
    best_at    = case when excluded.best_score > speech_group_round_scores.best_score
                      then now() else speech_group_round_scores.best_at end,
    best_score = greatest(speech_group_round_scores.best_score, excluded.best_score);
end;
$$;

-- ---------------------------------------------------------------------------
-- The group's round: the one running, else the last one that ended (with
-- its winner). No row: the group has never set one, or the last one was
-- cancelled.
create or replace function public.speech_group_round(p_group uuid)
returns table (
  id uuid, kind text, script_id uuid, title text, genre text, body text,
  summary text, target_seconds int, set_by text, set_by_me boolean,
  started_at timestamptz, ends_at timestamptz, ended boolean,
  winner_name text, winner_avatar text, winner_score int, winner_is_me boolean
)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not speech_is_group_member(p_group) then return; end if;
  perform speech_settle_group_rounds(p_group);
  return query
    select r.id, r.kind, r.script_id,
           coalesce(c.title, s.title, ''), coalesce(c.genre, s.genre, 'explainer'),
           coalesce(s.body, ''), coalesce(c.summary, s.summary, ''),
           coalesce(c.target_seconds, s.target_seconds, 60),
           coalesce((select p.display_name from speech_challenge_profiles p where p.user_id = r.set_by), ''),
           r.set_by = auth.uid(),
           r.started_at, r.ends_at, r.settled_at is not null,
           (select p.display_name from speech_challenge_profiles p where p.user_id = r.winner_id),
           (select p.avatar_jpeg from speech_challenge_profiles p where p.user_id = r.winner_id),
           r.winner_score,
           r.winner_id is not null and r.winner_id = auth.uid()
      from speech_group_rounds r
      left join speech_challenges c on r.kind = 'challenge' and c.id = r.script_id
      left join speech_group_scripts s on r.kind = 'script' and s.id = r.script_id
     where r.id = (select l.id from speech_group_rounds l
                    where l.group_id = p_group
                    order by l.started_at desc limit 1)
       and r.cancelled_at is null;
end;
$$;

-- Who's where in the round: every member, best and takes, nulls for those
-- who haven't started (listed last).
create or replace function public.speech_group_round_board(p_round uuid)
returns table (rank int, display_name text, avatar text, score int, attempts int, is_me boolean)
language sql stable security definer set search_path = public as $$
  with r as (
    select group_id from speech_group_rounds where id = p_round
  ), rows as (
    select m.user_id, s.best_score, coalesce(s.attempts, 0) as attempts, s.best_at, m.joined_at
      from speech_group_members m
      join r on r.group_id = m.group_id
      left join speech_group_round_scores s on s.round_id = p_round and s.user_id = m.user_id
  )
  select case when x.best_score is null then null
              else (row_number() over (order by x.best_score desc nulls last, x.best_at))::int end,
         coalesce(p.display_name, ''), p.avatar_jpeg, x.best_score, x.attempts,
         x.user_id = auth.uid()
    from rows x
    left join speech_challenge_profiles p on p.user_id = x.user_id
   where speech_is_group_member((select group_id from r))
   order by x.best_score desc nulls last, x.best_at, x.joined_at;
$$;

-- The group's ranking: every member, how many cards they hold, and which.
create or replace function public.speech_group_cards(p_group uuid)
returns table (rank int, display_name text, avatar text, cards int, won jsonb, is_me boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not speech_is_group_member(p_group) then return; end if;
  perform speech_settle_group_rounds(p_group);
  return query
    with wins as (
      select r.winner_id as user_id,
             count(*)::int as n,
             max(r.settled_at) as last_won,
             jsonb_agg(jsonb_build_object(
               'round_id', r.id, 'script_id', r.script_id, 'kind', r.kind,
               'title', coalesce(c.title, s.title, ''), 'score', r.winner_score,
               'won_at', r.settled_at)
               order by r.settled_at desc) as won
        from speech_group_rounds r
        left join speech_challenges c on r.kind = 'challenge' and c.id = r.script_id
        left join speech_group_scripts s on r.kind = 'script' and s.id = r.script_id
       where r.group_id = p_group and r.settled_at is not null and r.winner_id is not null
       group by r.winner_id
    )
    select (rank() over (order by coalesce(w.n, 0) desc))::int,
           coalesce(p.display_name, ''), p.avatar_jpeg,
           coalesce(w.n, 0), coalesce(w.won, '[]'::jsonb),
           m.user_id = auth.uid()
      from speech_group_members m
      left join wins w on w.user_id = m.user_id
      left join speech_challenge_profiles p on p.user_id = m.user_id
     where m.group_id = p_group
     order by coalesce(w.n, 0) desc, w.last_won, m.joined_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- Setting the next round: a public challenge, or a script posted to this
-- group, for 1 to 30 days.
create or replace function public.start_speech_group_round(p_group uuid, p_script uuid, p_days int)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_kind text;
  v_id uuid;
begin
  if not speech_is_group_member(p_group) then raise exception 'NOT_A_MEMBER'; end if;
  if p_days is null or p_days < 1 or p_days > 30 then raise exception 'BAD_DEADLINE'; end if;
  perform speech_settle_group_rounds(p_group);
  if exists (select 1 from speech_challenges where id = p_script) then
    v_kind := 'challenge';
  elsif exists (select 1 from speech_group_scripts
                 where id = p_script and group_id = p_group and removed_at is null) then
    v_kind := 'script';
  else
    raise exception 'NO_SUCH_SCRIPT';
  end if;
  begin
    insert into speech_group_rounds (group_id, script_id, kind, set_by, ends_at)
    values (p_group, p_script, v_kind, auth.uid(), now() + make_interval(days => p_days))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'ROUND_RUNNING';
  end;
  return v_id;
end;
$$;

-- Ending a round early: whoever set it, or whoever made the group. No card.
create or replace function public.cancel_speech_group_round(p_group uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_creator boolean := exists (select 1 from speech_groups where id = p_group and created_by = auth.uid());
begin
  if not speech_is_group_member(p_group) then raise exception 'NOT_A_MEMBER'; end if;
  update speech_group_rounds set cancelled_at = now()
   where group_id = p_group and settled_at is null and cancelled_at is null
     and now() < ends_at
     and (set_by = auth.uid() or v_creator);
end;
$$;

revoke all on function public.speech_settle_group_rounds(uuid) from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'speech_group_round(uuid)', 'speech_group_round_board(uuid)', 'speech_group_cards(uuid)',
    'start_speech_group_round(uuid, uuid, int)', 'cancel_speech_group_round(uuid)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
