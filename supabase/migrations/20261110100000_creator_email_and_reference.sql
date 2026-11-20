-- The creator application asks for an email (how everyone is reached: the
-- result, the free code, the start date) and, optionally, a video or creator
-- the applicant wants to work like.
--
-- `contact` stays filled: the social handle when given, otherwise the email.
-- One email is one application from here on; rows already on file keep their
-- handle key. A page cached from before this still posts `contact` alone and
-- works as it did. Apply BEFORE deploying the page, which sends the new
-- fields: the old function would silently drop them.

alter table public.creator_applications
  add column if not exists email text check (char_length(email) <= 254),
  add column if not exists reference_link text check (char_length(reference_link) <= 300);

create or replace function public.creator_apply(p jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email   text := nullif(lower(left(btrim(coalesce(p->>'email', '')), 254)), '');
  v_handle  text := nullif(left(btrim(coalesce(p->>'contact', '')), 200), '');
  v_contact text := coalesce(v_handle, v_email, '');
  v_key     text := coalesce(v_email, public.creator_contact_key(v_contact));
  v_ref     text := nullif(left(btrim(coalesce(p->>'reference_link', '')), 300), '');
  v_status  text;
  v_id      uuid;
  v_new     boolean := false;
begin
  if p is null or jsonb_typeof(p) <> 'object' or length(p::text) > 8000 then
    raise exception 'bad_payload';
  end if;
  if v_email is not null and v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'bad_email';
  end if;
  if coalesce(v_key, '') = '' then raise exception 'bad_contact'; end if;
  if coalesce((p->>'consent')::boolean, false) is not true then
    raise exception 'no_consent';
  end if;
  -- The form is public; this bounds what a script can pour in.
  if (select count(*) from creator_applications
       where created_at > now() - interval '1 hour') >= 120 then
    raise exception 'busy';
  end if;

  select id, status into v_id, v_status
    from creator_applications where contact_key = v_key;

  if v_id is null then
    v_new := true;
    insert into creator_applications (
      name, contact, contact_key, email, reference_link, platforms, stage, language, device, nawana_use,
      cadence, cadence_note, persona, why, link, source, consent_at)
    values (
      left(btrim(p->>'name'), 60), v_contact, v_key, v_email, v_ref,
      coalesce((select array_agg(left(x.v, 20)) from jsonb_array_elements_text(p->'platforms') as x(v)), '{}'),
      p->>'stage', p->>'language', p->>'device', p->>'nawana_use',
      p->>'cadence', nullif(left(btrim(coalesce(p->>'cadence_note', '')), 200), ''),
      left(btrim(p->>'persona'), 1000), left(btrim(p->>'why'), 1000),
      nullif(left(btrim(coalesce(p->>'link', '')), 300), ''),
      nullif(left(btrim(coalesce(p->>'source', '')), 40), ''), now());
  elsif v_status = 'new' then
    update creator_applications set
      name = left(btrim(p->>'name'), 60),
      contact = v_contact,
      email = v_email,
      reference_link = v_ref,
      platforms = coalesce((select array_agg(left(x.v, 20)) from jsonb_array_elements_text(p->'platforms') as x(v)), '{}'),
      stage = p->>'stage', language = p->>'language', device = p->>'device',
      nawana_use = p->>'nawana_use', cadence = p->>'cadence',
      cadence_note = nullif(left(btrim(coalesce(p->>'cadence_note', '')), 200), ''),
      persona = left(btrim(p->>'persona'), 1000), why = left(btrim(p->>'why'), 1000),
      link = nullif(left(btrim(coalesce(p->>'link', '')), 300), ''),
      consent_at = now(), updated_at = now()
    where id = v_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'new', v_new,
    'waiting', (select count(*) from creator_applications where status = 'new'));
end $$;

revoke all on function public.creator_apply(jsonb) from public, anon, authenticated;
grant execute on function public.creator_apply(jsonb) to service_role;
