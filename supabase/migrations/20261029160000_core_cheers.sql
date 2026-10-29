-- Cheers on a Core seat: hearts and one-line notes (2026-10-29, founder).
--
-- Anyone signed in can leave a heart (one per seat) or a short note
-- (40 characters) on a seated member's cube. The seat's sheet shows the
-- hearts as a count and the notes rising over the cube like live comments.
-- The owner of the seat sees new ones quietly on their next visit; there is
-- no push to them.
--
-- Kept deliberately light (founder: "don't overdo it, a hundred seats is
-- something I can watch"): no word filter, no reports, no blocks, no rate
-- limits. The author and the seat's owner can delete a note, and every new
-- note reaches the founder's Telegram through `owner-watch`
-- (`core_cheer_alerts_claim`), WITH its text, because reading it is the
-- moderation.
--
-- Every table is RLS-on with no policies: all access goes through these
-- security-definer functions, which never return a user id.

create table if not exists public.core_cheers (
  id          bigserial primary key,
  seat_user   uuid not null references auth.users(id) on delete cascade,
  language    text not null,
  author      uuid not null references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('heart', 'note')),
  body        text check (body is null or char_length(body) between 1 and 40),
  hidden      boolean not null default false,
  created_at  timestamptz not null default now()
);

create unique index if not exists core_cheers_one_heart
  on public.core_cheers (seat_user, language, author) where kind = 'heart';
create index if not exists core_cheers_seat
  on public.core_cheers (seat_user, language, created_at desc);
create index if not exists core_cheers_author_day
  on public.core_cheers (author, created_at desc);

alter table public.core_cheers enable row level security;
revoke all on public.core_cheers from anon, authenticated;

-- When the owner last looked at their own seat's cheers, per club.
alter table public.core_membership
  add column if not exists cheers_seen_at timestamptz;

-- The seat at a grid index, ordered exactly like `core_seat_map`.
create or replace function public.core_seat_user(p_language text, p_index integer)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  with seated as (
    select m.user_id, (row_number() over (order by m.join_number))::int - 1 as idx
      from core_membership m
     where m.seated and m.language = lower(btrim(coalesce(p_language, '')))
     order by m.join_number
     limit (select seats from core_club_config where id)
  )
  select user_id from seated where idx = p_index;
$$;
revoke all on function public.core_seat_user(text, integer) from public, anon, authenticated;

-- Everything the seat's sheet draws: hearts, whether I gave one, and the
-- newest notes (oldest first, so they rise in the order they were written).
create or replace function public.core_cheers_for(p_language text, p_index integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_lang text := lower(btrim(coalesce(p_language, '')));
  v_seat uuid := public.core_seat_user(p_language, p_index);
begin
  if v_seat is null then
    return null;
  end if;

  return jsonb_build_object(
    'hearts', (select count(*) from core_cheers
                where seat_user = v_seat and language = v_lang and kind = 'heart'),
    'hearted', coalesce(v_uid is not null and exists (
                 select 1 from core_cheers
                  where seat_user = v_seat and language = v_lang and kind = 'heart'
                    and author = v_uid), false),
    'mine', coalesce(v_seat = v_uid, false),
    'notes', coalesce((
      select jsonb_agg(n order by n.created_at)
        from (
          select c.id, c.body, c.created_at,
                 coalesce(c.author = v_uid, false) as by_me,
                 coalesce(
                   (select m.engraved_name from core_membership m
                     where m.user_id = c.author and m.language = v_lang),
                   (select p.display_name from public_personas p
                     where p.owner_user_id = c.author
                     order by p.updated_at desc nulls last limit 1)) as name
            from core_cheers c
           where c.seat_user = v_seat and c.language = v_lang
             and c.kind = 'note' and not c.hidden
           order by c.created_at desc
           limit 60
        ) n), '[]'::jsonb));
end;
$$;
revoke all on function public.core_cheers_for(text, integer) from public;
grant execute on function public.core_cheers_for(text, integer) to anon, authenticated;

-- A heart, on or off. Returns the new count and state.
create or replace function public.core_cheer_heart(p_language text, p_index integer, p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_lang text := lower(btrim(coalesce(p_language, '')));
  v_seat uuid := public.core_seat_user(p_language, p_index);
begin
  if v_uid is null or v_seat is null then
    raise exception 'not_allowed';
  end if;
  if p_on then
    insert into core_cheers (seat_user, language, author, kind)
    values (v_seat, v_lang, v_uid, 'heart')
    on conflict do nothing;
  else
    delete from core_cheers
     where seat_user = v_seat and language = v_lang and kind = 'heart' and author = v_uid;
  end if;
  return jsonb_build_object(
    'hearts', (select count(*) from core_cheers
                where seat_user = v_seat and language = v_lang and kind = 'heart'),
    'hearted', p_on);
end;
$$;
revoke all on function public.core_cheer_heart(text, integer, boolean) from public, anon;
grant execute on function public.core_cheer_heart(text, integer, boolean) to authenticated;

-- A note. Refused, with a reason the app can say, when it is empty or too
-- long.
create or replace function public.core_cheer_note(p_language text, p_index integer, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_lang text := lower(btrim(coalesce(p_language, '')));
  v_seat uuid := public.core_seat_user(p_language, p_index);
  v_body text := btrim(coalesce(p_body, ''));
  v_id   bigint;
begin
  if v_uid is null or v_seat is null then
    return jsonb_build_object('ok', false, 'reason', 'not_allowed');
  end if;
  if char_length(v_body) = 0 or char_length(v_body) > 40 then
    return jsonb_build_object('ok', false, 'reason', 'length');
  end if;
  insert into core_cheers (seat_user, language, author, kind, body)
  values (v_seat, v_lang, v_uid, 'note', v_body)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;
revoke all on function public.core_cheer_note(text, integer, text) from public, anon;
grant execute on function public.core_cheer_note(text, integer, text) to authenticated;

-- Remove a note: its author, or the owner of the seat it is on.
create or replace function public.core_cheer_delete(p_id bigint)
returns void
language sql
security definer
set search_path = public
as $$
  delete from core_cheers
   where id = p_id and kind = 'note'
     and (author = auth.uid() or seat_user = auth.uid());
$$;
revoke all on function public.core_cheer_delete(bigint) from public, anon;
grant execute on function public.core_cheer_delete(bigint) to authenticated;

-- How many hearts and notes arrived on my seat since I last opened it.
create or replace function public.core_cheers_unseen(p_language text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from core_cheers c
    join core_membership m
      on m.user_id = c.seat_user and m.language = c.language
   where c.seat_user = auth.uid()
     and c.language = lower(btrim(coalesce(p_language, '')))
     and c.author <> auth.uid()
     and not c.hidden
     and c.created_at > coalesce(m.cheers_seen_at, '-infinity'::timestamptz);
$$;
revoke all on function public.core_cheers_unseen(text) from public, anon;
grant execute on function public.core_cheers_unseen(text) to authenticated;

create or replace function public.core_cheers_mark_seen(p_language text)
returns void
language sql
security definer
set search_path = public
as $$
  update core_membership set cheers_seen_at = now()
   where user_id = auth.uid() and language = lower(btrim(coalesce(p_language, '')));
$$;
revoke all on function public.core_cheers_mark_seen(text) from public, anon;
grant execute on function public.core_cheers_mark_seen(text) to authenticated;

-- New notes for the founder's Telegram, claimed in `owner_alerts` exactly
-- like `owner_alerts_claim` claims its three kinds, so a note is announced
-- once and a Telegram failure is not retried. Called by `owner-watch`.
create or replace function public.core_cheer_alerts_claim(p_limit int default 20)
returns table (kind text, key text, payload jsonb)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with fresh as (
    select c.* from core_cheers c
     where c.kind = 'note'
       and c.created_at > now() - interval '1 day'
       and not exists (select 1 from owner_alerts a
                        where a.kind = 'core_note' and a.key = c.id::text)
     order by c.created_at
     limit p_limit
  ), claimed as (
    insert into owner_alerts (kind, key)
    select 'core_note', id::text from fresh
    on conflict do nothing
    returning owner_alerts.key
  )
  select 'core_note'::text, f.id::text,
         jsonb_build_object(
           'body', f.body,
           'language', f.language,
           'seat', (select m.engraved_name from core_membership m
                     where m.user_id = f.seat_user and m.language = f.language),
           'seat_user', f.seat_user,
           'author', f.author,
           'author_name', coalesce(
             (select m.engraved_name from core_membership m
               where m.user_id = f.author and m.language = f.language),
             (select p.display_name from public_personas p
               where p.owner_user_id = f.author
               order by p.updated_at desc nulls last limit 1)),
           'id', f.id)
    from fresh f
    join claimed c on c.key = f.id::text;
end;
$$;
revoke all on function public.core_cheer_alerts_claim(int) from public, anon, authenticated;
