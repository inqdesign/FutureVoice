-- Short surveys sent by mail (2026-10-20).
--
-- One page (web/survey.html, served at nawana.app/s/<survey>) shows any
-- survey; its questions are a JSON file beside it (web/survey/<survey>.json),
-- so a new survey is a new file, not a migration. Each recipient gets an
-- opaque random token in the link (scripts/survey-mail.py writes it here when
-- it sends), which ties an answer to the learner and the group they were
-- mailed in without asking for anything. A link with no token still works,
-- for a survey shared in a post; those answers are anonymous.
--
-- Both tables have RLS on and no policies: the page goes through the two
-- functions below, and only the service role reads answers
-- (scripts/survey-results.py).

create table if not exists public.survey_invites (
  token       text primary key,
  survey_id   text not null,
  user_id     uuid references auth.users(id) on delete cascade,
  grp         text,
  email       text,
  sent_at     timestamptz not null default now(),
  opened_at   timestamptz
);
create index if not exists survey_invites_survey on public.survey_invites (survey_id);
create unique index if not exists survey_invites_one_per_user
  on public.survey_invites (survey_id, user_id) where user_id is not null;
alter table public.survey_invites enable row level security;

create table if not exists public.survey_responses (
  id           bigint generated always as identity primary key,
  survey_id    text not null,
  token        text references public.survey_invites(token) on delete set null,
  answers      jsonb not null,
  lang         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
-- A token answers once; sending again replaces its answer.
create unique index if not exists survey_responses_one_per_token
  on public.survey_responses (token) where token is not null;
create index if not exists survey_responses_survey on public.survey_responses (survey_id, created_at);
alter table public.survey_responses enable row level security;

-- Opening the link: marks the invite opened and hands back the answer
-- already given, so a learner who opens it twice edits instead of starting
-- over. An unknown token is treated as no token.
create or replace function public.survey_open(p_survey text, p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_known boolean := false;
  v_answers jsonb;
begin
  if p_token is null or length(p_token) > 64 then
    return jsonb_build_object('known', false);
  end if;
  update survey_invites set opened_at = coalesce(opened_at, now())
   where token = p_token and survey_id = p_survey
  returning true into v_known;
  if not coalesce(v_known, false) then
    return jsonb_build_object('known', false);
  end if;
  select answers into v_answers from survey_responses where token = p_token;
  return jsonb_build_object('known', true, 'answers', v_answers);
end $$;

create or replace function public.survey_submit(p_survey text, p_token text, p_answers jsonb, p_lang text default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_token text;
begin
  if p_survey is null or p_survey !~ '^[a-z0-9-]{1,64}$' then
    raise exception 'bad survey';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' or length(p_answers::text) > 8000 then
    raise exception 'bad answers';
  end if;
  select token into v_token from survey_invites where token = p_token and survey_id = p_survey;
  if v_token is null then
    -- Anonymous: a shared link. Bounded so the table can't be flooded.
    if (select count(*) from survey_responses
         where survey_id = p_survey and token is null and created_at > now() - interval '1 hour') >= 200 then
      raise exception 'busy';
    end if;
    insert into survey_responses (survey_id, answers, lang) values (p_survey, p_answers, left(p_lang, 8));
    return true;
  end if;
  insert into survey_responses (survey_id, token, answers, lang)
  values (p_survey, v_token, p_answers, left(p_lang, 8))
  on conflict (token) where token is not null
  do update set answers = excluded.answers, lang = excluded.lang, updated_at = now();
  return true;
end $$;

revoke all on function public.survey_open(text, text) from public;
revoke all on function public.survey_submit(text, text, jsonb, text) from public;
grant execute on function public.survey_open(text, text) to anon, authenticated;
grant execute on function public.survey_submit(text, text, jsonb, text) to anon, authenticated;
