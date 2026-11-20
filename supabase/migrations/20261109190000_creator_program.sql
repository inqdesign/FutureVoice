-- The creator program (founder, 2026-11-09): nawana.app/creators.
--
-- People who want to study a language in public for 100 days apply on a web page; the
-- founder reads every application in the admin console (/admin/creators),
-- DMs them, hands them a code, and watches whether they keep the promise.
--
-- Nothing here touches an existing table. Both tables have RLS on and no
-- policies, so only the service role sees them: an application carries a
-- real person's handle and what they wrote about their life.
--
--   web/creators.html  ->  edge function creator-apply  ->  creator_apply()
--   admin/src/creators.ts  ->  these tables, with the service-role key
--
-- The free access is an ordinary comp code (comp_codes), STANDING so it rolls
-- every month with its pool refilled: a creator who keeps going costs the
-- founder no monthly chore. Ending someone sets cancel_at_period_end on their
-- comp row, and the existing nightly sweep ends it on the period's last day.
-- A learner can only ever redeem ONE comp code (redeem_referral), which is
-- why renewal is a roll and never a second code.

create table if not exists public.creator_applications (
  id            uuid primary key default gen_random_uuid(),

  -- What the applicant wrote.
  name          text not null check (char_length(name) between 1 and 60),
  contact       text not null check (char_length(contact) between 2 and 200),
  -- `contact` reduced to the handle: one person, one row, however they typed it.
  contact_key   text not null unique,
  platforms     text[] not null default '{}',
  stage         text not null check (stage in ('not_started', 'small', 'running')),
  language      text not null check (language in ('en', 'de', 'ja', 'es', 'ko')),
  device        text not null check (device in ('iphone', 'android')),
  nawana_use    text not null check (nawana_use in ('never', 'tried', 'using')),
  cadence       text not null check (cadence in ('daily', 'weekdays', 'three', 'custom')),
  cadence_note  text check (char_length(cadence_note) <= 200),
  persona       text not null check (char_length(persona) between 1 and 1000),
  why           text not null check (char_length(why) between 1 and 1000),
  link          text check (char_length(link) <= 300),
  source        text check (char_length(source) <= 40),   -- ?ref= on the link they came from
  consent_at    timestamptz not null,

  -- The founder's side.
  status        text not null default 'new'
                check (status in ('new', 'talking', 'active', 'paused', 'ended', 'declined')),
  note          text check (char_length(note) <= 4000),
  comp_code     text references public.comp_codes(code) on delete set null,
  started_at    timestamptz,
  ended_at      timestamptz,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists creator_applications_status
  on public.creator_applications (status, created_at desc);
alter table public.creator_applications enable row level security;
revoke all on public.creator_applications from anon, authenticated;

-- One row per day the founder saw a post. The app's own usage for the same
-- days is read live from talk_seconds_by_language and never copied here.
create table if not exists public.creator_posts (
  application_id uuid not null references public.creator_applications(id) on delete cascade,
  day            date not null,
  created_at     timestamptz not null default now(),
  primary key (application_id, day)
);
alter table public.creator_posts enable row level security;
revoke all on public.creator_posts from anon, authenticated;

-- "@name", "name", "https://www.threads.com/@name/" are one person.
create or replace function public.creator_contact_key(p_contact text)
returns text
language sql immutable
set search_path = public as $$
  select case
           when h ~ '^(threads\.(net|com)|instagram\.com|tiktok\.com|youtube\.com)/'
             then regexp_replace(regexp_replace(h, '^[^/]+/@?', ''), '[/?#].*$', '')
           -- Any other address keeps its path: two blogs on one host are two people.
           else regexp_replace(regexp_replace(h, '^@', ''), '/+$', '')
         end
    from (select regexp_replace(lower(btrim(p_contact)), '^https?://(www\.|m\.)?', '') as h) s
$$;

-- Called only by the creator-apply edge function, which holds the service
-- role, so a request can't reach it without passing the honeypot there.
-- Sending the form again with the same handle replaces the application while
-- the founder hasn't acted on it; after that it changes nothing.
create or replace function public.creator_apply(p jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_contact text := left(btrim(coalesce(p->>'contact', '')), 200);
  v_key     text := public.creator_contact_key(v_contact);
  v_status  text;
  v_id      uuid;
  v_new     boolean := false;
begin
  if p is null or jsonb_typeof(p) <> 'object' or length(p::text) > 8000 then
    raise exception 'bad_payload';
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
      name, contact, contact_key, platforms, stage, language, device, nawana_use,
      cadence, cadence_note, persona, why, link, source, consent_at)
    values (
      left(btrim(p->>'name'), 60), v_contact, v_key,
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
revoke all on function public.creator_contact_key(text) from public, anon, authenticated;
grant execute on function public.creator_apply(jsonb) to service_role;
grant execute on function public.creator_contact_key(text) to service_role;
