-- nawana.app/community: news the founder writes, and a public chat.
--
-- Anyone can READ both (the page is public and signed out by default).
-- Only a signed-in, non-anonymous account can WRITE a chat message, and only
-- as itself: a message is tied to a real account so abuse can be traced and
-- the founder can reply to an actual learner. News is written only with the
-- service role (scripts/community.py), never from a browser.
--
-- Moderation is `hidden = true` on a message: it leaves the public read at
-- once (the page re-reads every minute; realtime can't announce it, because a
-- hidden row no longer passes the read policy). Nothing is deleted, so a
-- report can still be read later.

-- ── news ──────────────────────────────────────────────────────────────────
create table if not exists public.community_news (
  id            uuid primary key default gen_random_uuid(),
  published_at  timestamptz not null default now(),
  title_ko      text not null,
  title_en      text not null,
  body_ko       text not null default '',
  body_en       text not null default '',
  link_url      text,
  image_url     text,
  is_published  boolean not null default false,
  created_at    timestamptz not null default now()
);

alter table public.community_news enable row level security;

drop policy if exists "news is public once published" on public.community_news;
create policy "news is public once published" on public.community_news
  for select to anon, authenticated
  using (is_published);

-- ── staff (who gets the 운영자 / Team badge) ─────────────────────────────
create table if not exists public.community_staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  label   text not null default 'nawana'
);
alter table public.community_staff enable row level security;
-- no policies: only the service role and the trigger below read it

-- ── chat ──────────────────────────────────────────────────────────────────
create table if not exists public.community_messages (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  display_name  text not null,
  body          text not null,
  is_staff      boolean not null default false,
  hidden        boolean not null default false,
  created_at    timestamptz not null default now(),
  constraint community_messages_body_len check (char_length(body) between 1 and 500),
  constraint community_messages_name_len check (char_length(display_name) between 1 and 24)
);

create index if not exists community_messages_recent
  on public.community_messages (created_at desc) where not hidden;
create index if not exists community_messages_by_user
  on public.community_messages (user_id, created_at desc);

alter table public.community_messages enable row level security;

drop policy if exists "chat is public" on public.community_messages;
create policy "chat is public" on public.community_messages
  for select to anon, authenticated
  using (not hidden);

drop policy if exists "signed-in people post as themselves" on public.community_messages;
create policy "signed-in people post as themselves" on public.community_messages
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
    and not hidden
  );

-- The browser chooses the words and the nickname, never the badge, the time
-- or how fast it may post. The trigger settles all three.
create or replace function public.community_message_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recent int;
  v_last   timestamptz;
begin
  new.body := btrim(new.body);
  new.display_name := btrim(regexp_replace(new.display_name, '\s+', ' ', 'g'));
  new.created_at := now();
  new.hidden := false;
  new.is_staff := exists (select 1 from community_staff s where s.user_id = new.user_id);

  -- A nickname can't borrow the team's name unless it IS the team.
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

drop trigger if exists community_message_guard on public.community_messages;
create trigger community_message_guard
  before insert on public.community_messages
  for each row execute function public.community_message_guard();

-- Nobody edits or deletes from the browser; hiding is the service role's.
revoke update, delete on public.community_messages from anon, authenticated;

-- Live updates for the page: new messages appear without a reload.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'community_messages'
  ) then
    alter publication supabase_realtime add table public.community_messages;
  end if;
end $$;
