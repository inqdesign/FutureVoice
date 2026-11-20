-- A guestbook line can be changed by whoever wrote it: the browser that wrote
-- it keeps the line's id, and the edit is accepted only when it comes with the
-- same random browser id the line was written with (the one the daily limit
-- already uses; never shown, never returned).
--
-- creator_note_add now returns the new line's id; creator_notes_recent returns
-- each line's id; creator_note_edit is new. All three are reached only through
-- the creator-apply function (service role), except recent, which anon reads.

alter table public.creator_notes
  add column if not exists edited_at timestamptz;

create or replace function public.creator_note_add(p_body text, p_client text, p_day int default null, p_name text default null, p_color text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_body   text := btrim(regexp_replace(coalesce(p_body, ''), '[[:space:]]+', ' ', 'g'));
  v_name   text := nullif(left(btrim(regexp_replace(coalesce(p_name, ''), '[[:space:]]+', ' ', 'g')), 16), '');
  v_client text := left(btrim(coalesce(p_client, '')), 64);
  v_day    int := case when p_day between 1 and 100000 then p_day end;
  v_color  text := case when p_color in ('ink', 'red', 'orange', 'green', 'pink', 'purple') then p_color end;
  v_plain  text;
  v_id     uuid;
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
  insert into creator_notes (body, client, day, name, color) values (v_body, v_client, v_day, v_name, v_color)
    returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.creator_note_edit(p_id uuid, p_client text, p_body text, p_name text default null, p_color text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_body   text := btrim(regexp_replace(coalesce(p_body, ''), '[[:space:]]+', ' ', 'g'));
  v_name   text := nullif(left(btrim(regexp_replace(coalesce(p_name, ''), '[[:space:]]+', ' ', 'g')), 16), '');
  v_client text := left(btrim(coalesce(p_client, '')), 64);
  v_color  text := case when p_color in ('ink', 'red', 'orange', 'green', 'pink', 'purple') then p_color end;
  v_plain  text;
  v_edited timestamptz;
begin
  if char_length(v_body) = 0 or char_length(v_body) > 60 then raise exception 'bad_note'; end if;
  if char_length(v_client) < 8 then raise exception 'bad_client'; end if;
  v_plain := lower(regexp_replace(v_body || coalesce(v_name, ''), '[^[:alnum:]가-힣ㄱ-ㅎ]', '', 'g'));
  if v_plain ~ '(씨발|시발|씨바|ㅅㅂ|ㅆㅂ|병신|ㅂㅅ|좆|존나|개새|새끼|ㅅㄲ|미친놈|미친년|fuck|shit|bitch|http|www)' then
    raise exception 'bad_word';
  end if;
  -- Only the browser that wrote it, and never a line the admin hid.
  select edited_at into v_edited from creator_notes where id = p_id and client = v_client and not hidden;
  if not found then raise exception 'not_yours'; end if;
  if v_edited > now() - interval '5 seconds' then raise exception 'busy'; end if;
  update creator_notes set body = v_body, name = v_name, color = v_color, edited_at = now() where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.creator_note_edit(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.creator_note_edit(uuid, text, text, text, text) to service_role;

drop function if exists public.creator_notes_recent();
create function public.creator_notes_recent()
returns table (id uuid, body text, created_at timestamptz, day int, name text, color text)
language sql stable security definer set search_path = public as $$
  select id, body, created_at, day, name, color from creator_notes where not hidden order by created_at desc limit 500
$$;

revoke all on function public.creator_notes_recent() from public;
grant execute on function public.creator_notes_recent() to anon, authenticated, service_role;
