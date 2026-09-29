-- nawana.app/community, round two: likes and replies on chat messages.
--
-- A reply is an ordinary message with `parent_id` set, so every rule the chat
-- already has (signed-in only, rate limits, reserved names, moderation by
-- `hidden`) covers replies with no second copy. Threads are ONE level deep:
-- replying to a reply files it under the original message, the way a chat
-- thread reads, and nothing ever has to render a tree.
--
-- A like is a row per (message, person). Anyone can read them (the counts are
-- public); only the signed-in person can add or remove their own.

alter table public.community_messages
  add column if not exists parent_id bigint references public.community_messages(id) on delete set null;

create index if not exists community_messages_replies
  on public.community_messages (parent_id, created_at) where parent_id is not null and not hidden;

-- Settle the thread in the same guard that settles everything else a browser sends.
create or replace function public.community_message_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recent int;
  v_last   timestamptz;
  v_parent community_messages%rowtype;
begin
  new.body := btrim(new.body);
  new.display_name := btrim(regexp_replace(new.display_name, '\s+', ' ', 'g'));
  new.created_at := now();
  new.hidden := false;
  new.is_staff := exists (select 1 from community_staff s where s.user_id = new.user_id);

  if new.parent_id is not null then
    select * into v_parent from community_messages where id = new.parent_id;
    if not found or v_parent.hidden then
      raise exception 'parent_missing' using errcode = 'P0001';
    end if;
    -- one level: a reply to a reply belongs to the original message
    if v_parent.parent_id is not null then
      new.parent_id := v_parent.parent_id;
    end if;
  end if;

  if not new.is_staff and lower(new.display_name) ~ '(nawana|나와나|운영자|admin)' then
    raise exception 'display_name_reserved' using errcode = 'P0001';
  end if;

  select max(created_at), count(*) filter (where created_at > now() - interval '10 minutes')
    into v_last, v_recent
    from community_messages
   where user_id = new.user_id and created_at > now() - interval '10 minutes';

  if not new.is_staff and v_last is not null and v_last > now() - interval '3 seconds' then
    raise exception 'slow_down' using errcode = 'P0001';
  end if;
  if not new.is_staff and v_recent >= 20 then
    raise exception 'too_many' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- ── likes ─────────────────────────────────────────────────────────────────
create table if not exists public.community_reactions (
  message_id bigint not null references public.community_messages(id) on delete cascade,
  user_id    uuid   not null references auth.users(id) on delete cascade,
  kind       text   not null default 'like' check (kind in ('like')),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, kind)
);

create index if not exists community_reactions_by_message on public.community_reactions (message_id);

alter table public.community_reactions enable row level security;

drop policy if exists "likes are public" on public.community_reactions;
create policy "likes are public" on public.community_reactions
  for select to anon, authenticated using (true);

drop policy if exists "people like as themselves" on public.community_reactions;
create policy "people like as themselves" on public.community_reactions
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
    and exists (select 1 from public.community_messages m where m.id = message_id and not m.hidden)
  );

drop policy if exists "people take back their own like" on public.community_reactions;
create policy "people take back their own like" on public.community_reactions
  for delete to authenticated
  using (user_id = auth.uid());

revoke update on public.community_reactions from anon, authenticated;

-- A delete event only carries the primary key unless the old row is logged in
-- full; the page needs message_id to take the heart back live.
alter table public.community_reactions replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'community_reactions'
  ) then
    alter publication supabase_realtime add table public.community_reactions;
  end if;
end $$;
