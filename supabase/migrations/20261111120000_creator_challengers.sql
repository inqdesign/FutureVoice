-- The 100-day challenge takes challengers beside creators: people who post
-- nothing, pay for their own plan, and earn the next three months free by
-- keeping the days (4+ minutes of talk and one speech a day, one missed day
-- per 30 forgiven). For now only the application is taken: same table, a
-- `kind`, and the plan they mean to use.

alter table public.creator_applications
  add column if not exists kind text not null default 'creator' check (kind in ('creator', 'challenger')),
  add column if not exists plan text check (plan in ('light', 'plus', 'max'));

create or replace function public.creator_apply(p jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email   text := nullif(lower(left(btrim(coalesce(p->>'email', '')), 254)), '');
  v_handle  text := nullif(left(btrim(coalesce(p->>'contact', '')), 200), '');
  v_contact text := coalesce(v_handle, v_email, '');
  v_key     text := coalesce(v_email, public.creator_contact_key(v_contact));
  v_ref     text := nullif(left(btrim(coalesce(p->>'reference_link', '')), 300), '');
  v_level   text := case when lower(btrim(coalesce(p->>'level', ''))) in ('a1', 'a2', 'b1', 'b2', 'c1', 'c2')
                         then lower(btrim(p->>'level')) end;
  -- A challenger pays for their own plan and posts nothing: the creator-only answers get fixed stand-ins.
  v_kind    text := case when p->>'kind' = 'challenger' then 'challenger' else 'creator' end;
  v_plan    text := case when p->>'plan' in ('light', 'plus', 'max') then p->>'plan' end;
  v_stage   text := case when p->>'kind' = 'challenger' then 'not_started' else p->>'stage' end;
  v_cadence text := case when p->>'kind' = 'challenger' then 'daily' else p->>'cadence' end;
  v_persona text := coalesce(nullif(left(btrim(coalesce(p->>'persona', '')), 1000), ''), case when p->>'kind' = 'challenger' then '-' end);
  v_why     text := coalesce(nullif(left(btrim(coalesce(p->>'why', '')), 1000), ''), case when p->>'kind' = 'challenger' then '-' end);
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
      name, contact, contact_key, email, reference_link, level, platforms, stage, language, device, nawana_use,
      cadence, cadence_note, persona, why, link, source, consent_at, kind, plan)
    values (
      left(btrim(p->>'name'), 60), v_contact, v_key, v_email, v_ref, v_level,
      coalesce((select array_agg(left(x.v, 20)) from jsonb_array_elements_text(p->'platforms') as x(v)), '{}'),
      v_stage, p->>'language', p->>'device', p->>'nawana_use',
      v_cadence, nullif(left(btrim(coalesce(p->>'cadence_note', '')), 200), ''),
      v_persona, v_why,
      nullif(left(btrim(coalesce(p->>'link', '')), 300), ''),
      nullif(left(btrim(coalesce(p->>'source', '')), 40), ''), now(), v_kind, v_plan);
  elsif v_status = 'new' then
    update creator_applications set
      name = left(btrim(p->>'name'), 60),
      contact = v_contact,
      email = v_email,
      reference_link = v_ref,
      level = v_level,
      platforms = coalesce((select array_agg(left(x.v, 20)) from jsonb_array_elements_text(p->'platforms') as x(v)), '{}'),
      stage = v_stage, language = p->>'language', device = p->>'device',
      nawana_use = p->>'nawana_use', cadence = v_cadence, kind = v_kind, plan = v_plan,
      cadence_note = nullif(left(btrim(coalesce(p->>'cadence_note', '')), 200), ''),
      persona = v_persona, why = v_why,
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
