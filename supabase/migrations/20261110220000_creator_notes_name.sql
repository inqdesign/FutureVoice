-- Guestbook pages carry the writer's name (shown on the page's band in place of
-- "DAY"), a page holds one line and nobody else can write over it, and the pile
-- can grow past 100 pages (tapping the pad sheds 100 more), so a page number
-- can go past 100.
--
-- creator_note_add gains p_name. The three-argument version is dropped rather
-- than overloaded ("not unique" otherwise); a deployed function that still sends
-- three arguments lands on p_name's default.

alter table public.creator_notes
  add column if not exists name text check (char_length(name) between 1 and 16);

alter table public.creator_notes drop constraint if exists creator_notes_day_check;
alter table public.creator_notes alter column day type int;
alter table public.creator_notes add constraint creator_notes_day_check check (day between 1 and 100000);

drop function if exists public.creator_note_add(text, text, int);

create or replace function public.creator_note_add(p_body text, p_client text, p_day int default null, p_name text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_body   text := btrim(regexp_replace(coalesce(p_body, ''), '[[:space:]]+', ' ', 'g'));
  v_name   text := nullif(left(btrim(regexp_replace(coalesce(p_name, ''), '[[:space:]]+', ' ', 'g')), 16), '');
  v_client text := left(btrim(coalesce(p_client, '')), 64);
  v_day    int := case when p_day between 1 and 100000 then p_day end;
  v_plain  text;
begin
  if char_length(v_body) = 0 or char_length(v_body) > 60 then raise exception 'bad_note'; end if;
  if char_length(v_client) < 8 then raise exception 'bad_client'; end if;
  -- A basic word filter over the line and the name; anything it misses is hidden from the admin.
  v_plain := lower(regexp_replace(v_body || coalesce(v_name, ''), '[^[:alnum:]가-힣ㄱ-ㅎ]', '', 'g'));
  if v_plain ~ '(씨발|시발|씨바|ㅅㅂ|ㅆㅂ|병신|ㅂㅅ|좆|존나|개새|새끼|ㅅㄲ|미친놈|미친년|fuck|shit|bitch|http|www)' then
    raise exception 'bad_word';
  end if;
  -- One line per page: a page someone already wrote on is theirs.
  if v_day is not null and exists (select 1 from creator_notes where day = v_day and not hidden) then
    raise exception 'taken';
  end if;
  if (select count(*) from creator_notes where client = v_client and created_at > now() - interval '1 day') >= 3 then
    raise exception 'too_many';
  end if;
  if (select count(*) from creator_notes where created_at > now() - interval '1 hour') >= 120 then
    raise exception 'busy';
  end if;
  insert into creator_notes (body, client, day, name) values (v_body, v_client, v_day, v_name);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.creator_note_add(text, text, int, text) from public, anon, authenticated;
grant execute on function public.creator_note_add(text, text, int, text) to service_role;

drop function if exists public.creator_notes_recent();
create function public.creator_notes_recent()
returns table (body text, created_at timestamptz, day int, name text)
language sql stable security definer set search_path = public as $$
  select body, created_at, day, name from creator_notes where not hidden order by created_at desc limit 500
$$;

revoke all on function public.creator_notes_recent() from public;
grant execute on function public.creator_notes_recent() to anon, authenticated, service_role;
