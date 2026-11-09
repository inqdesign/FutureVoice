-- The Learner Record (docs/learner-record.md): what each learner has learned,
-- one fact per row, so the tutor and every other feature read one source.
-- The content of conversations never comes here, and the RPC below is what
-- makes that true: only listed kinds, only listed value keys, short values.
--
-- Additive only. Nothing reads these tables yet, and nothing is stored until
-- billing_config.learner_record_on is switched on.

alter table public.billing_config
  add column if not exists learner_record_on boolean not null default false;

-- What each kind of event may carry. `max_string` is the longest text value:
-- most kinds hold fixed words, and only setup and goal hold what was typed.
create table public.learner_event_kinds (
  kind       text primary key,
  value_keys text[] not null,
  max_string integer not null default 16
);

insert into public.learner_event_kinds (kind, value_keys, max_string) values
  ('setup',      array['value'], 300),
  ('goal',       array['kind', 'date', 'title', 'place', 'notes'], 500),
  ('talk',       array['minutes', 'mode', 'learner_words', 'turns', 'wpm', 'pauses',
                       'vocabulary', 'grammar', 'expressiveness', 'fluency',
                       'pronunciation', 'cefr', 'grammar_range'], 16),
  ('item',       array['right', 'wrong', 'item_kind'], 16),
  ('word',       array['state', 'count'], 16),
  ('expression', array['state', 'count'], 16),
  ('card',       array['box', 'seen', 'correct', 'used_at'], 32),
  ('shadow',     array['overall', 'match', 'rhythm', 'partial'], 16),
  ('sound',      array['score', 'samples', 'surface'], 24),
  ('lesson',     array['challenges', 'tries', 'done', 'check_passed'], 16),
  ('test',       array['right', 'appealed', 'score'], 16),
  ('day',        array['talk_seconds', 'word_reps', 'expression_reps', 'drill_reps',
                       'shadow_reps', 'scene_reps', 'listens', 'speech_takes'], 16),
  ('routine',    array['weekday', 'time', 'amount', 'kept'], 16);

alter table public.learner_event_kinds enable row level security;

create table public.learner_events (
  user_id     uuid not null references auth.users(id) on delete cascade,
  key         text not null,
  language    text not null,
  occurred_at timestamptz not null,
  source_id   text,
  kind        text not null references public.learner_event_kinds(kind),
  subject     text not null,
  value       jsonb not null default '{}'::jsonb,
  platform    text,
  app_version text,
  received_at timestamptz not null default now(),
  primary key (user_id, key)
);

create index learner_events_by_time
  on public.learner_events (user_id, language, occurred_at desc);
create index learner_events_by_source
  on public.learner_events (user_id, source_id) where source_id is not null;

alter table public.learner_events enable row level security;
create policy "learner_events_read_own" on public.learner_events
  for select to authenticated using (user_id = auth.uid());

-- One computed record per learner and language. Written by the server only.
create table public.learner_record (
  user_id        uuid not null references auth.users(id) on delete cascade,
  language       text not null,
  schema_version integer not null default 1,
  body           jsonb not null default '{}'::jsonb,
  computed_at    timestamptz not null default now(),
  primary key (user_id, language)
);

alter table public.learner_record enable row level security;
create policy "learner_record_read_own" on public.learner_record
  for select to authenticated using (user_id = auth.uid());

revoke all on public.learner_event_kinds from anon, authenticated;
revoke insert, update, delete on public.learner_events from anon, authenticated;
revoke insert, update, delete on public.learner_record from anon, authenticated;

create function public.learner_record_enabled()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select learner_record_on from billing_config where id), false);
$$;

-- Stores a batch and returns how many events were accepted. One event that
-- breaks a rule is skipped; the rest of the batch still lands.
create function public.learner_events_put(p_batch jsonb)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_user     uuid := auth.uid();
  v_event    jsonb;
  v_kind     learner_event_kinds%rowtype;
  v_value    jsonb;
  v_when     timestamptz;
  v_entry    record;
  v_ok       boolean;
  v_accepted integer := 0;
begin
  if v_user is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'an account is required';
  end if;
  if jsonb_typeof(p_batch) <> 'array' or jsonb_array_length(p_batch) > 500 then
    raise exception 'batch must be an array of at most 500 events';
  end if;
  if not learner_record_enabled() then
    return 0;
  end if;

  for v_event in select * from jsonb_array_elements(p_batch) loop
    select * into v_kind from learner_event_kinds where kind = v_event ->> 'kind';
    continue when not found;

    continue when coalesce(length(v_event ->> 'key'), 0) not between 1 and 200;
    continue when coalesce(length(v_event ->> 'language'), 0) not between 2 and 16;
    continue when coalesce(length(v_event ->> 'subject'), 0) not between 1 and 60;
    continue when coalesce(length(v_event ->> 'source_id'), 0) > 80;

    v_value := coalesce(v_event -> 'value', '{}'::jsonb);
    continue when jsonb_typeof(v_value) <> 'object';

    v_ok := true;
    for v_entry in select * from jsonb_each(v_value) loop
      if not (v_entry.key = any (v_kind.value_keys)) then
        v_ok := false;
      elsif jsonb_typeof(v_entry.value) not in ('number', 'boolean', 'string', 'null') then
        v_ok := false;
      elsif jsonb_typeof(v_entry.value) = 'string'
            and length(v_entry.value #>> '{}') > v_kind.max_string then
        v_ok := false;
      end if;
      exit when not v_ok;
    end loop;
    continue when not v_ok;

    begin
      v_when := (v_event ->> 'occurred_at')::timestamptz;
    exception when others then
      continue;
    end;
    continue when v_when is null or v_when > now() + interval '1 day';

    insert into learner_events
      (user_id, key, language, occurred_at, source_id, kind, subject, value, platform, app_version)
    values
      (v_user, v_event ->> 'key', v_event ->> 'language', v_when, v_event ->> 'source_id',
       v_kind.kind, v_event ->> 'subject', v_value,
       left(v_event ->> 'platform', 16), left(v_event ->> 'app_version', 24))
    on conflict (user_id, key) do update set
      language    = excluded.language,
      occurred_at = excluded.occurred_at,
      source_id   = excluded.source_id,
      kind        = excluded.kind,
      subject     = excluded.subject,
      value       = excluded.value,
      platform    = excluded.platform,
      app_version = excluded.app_version,
      received_at = now();

    v_accepted := v_accepted + 1;
  end loop;

  return v_accepted;
end;
$$;

-- A deleted talk takes its rows with it.
create function public.learner_events_forget(p_source_id text)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_user    uuid := auth.uid();
  v_deleted integer;
begin
  if v_user is null then
    raise exception 'an account is required';
  end if;
  delete from learner_events where user_id = v_user and source_id = p_source_id;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.learner_record_enabled() from public;
revoke all on function public.learner_events_put(jsonb) from public;
revoke all on function public.learner_events_forget(text) from public;
grant execute on function public.learner_record_enabled() to authenticated;
grant execute on function public.learner_events_put(jsonb) to authenticated;
grant execute on function public.learner_events_forget(text) to authenticated;
