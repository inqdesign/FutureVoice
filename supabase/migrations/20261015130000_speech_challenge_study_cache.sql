-- "Study" notes on a speech CHALLENGE are made once and shared (2026-10-15,
-- founder: "of course it should be shared"). A challenge is the same text for
-- every learner of its language, so the notes for one (native language,
-- level) pair are the same notes for all of them — and until now every phone
-- paid for its own copy (`purpose: "script-study"`, a 3.6-flash call of up to
-- 8k tokens).
--
-- Written ONLY by the `script-study` edge function on the service role, which
-- reads the challenge's text from `speech_challenges` itself and holds the
-- prompt — the same reason `word_entry` lost its client insert policy
-- (`20260822100000_prelaunch_security`): a table every learner reads must not
-- be writable by any of them. No policies: the function hands rows out.
--
-- What is stored is the model's RAW answer (highlight candidates + paragraph
-- translations). Each app still places the spans itself (`ScriptStudy.locate`),
-- exactly as it does for a study it made on the phone.
--
-- `body_hash` is in the key so an edited challenge text is a new study, and
-- `prompt_version` matches `ScriptStudy.promptVersion` in the apps.

create table if not exists public.speech_challenge_study (
  challenge_id    uuid not null references public.speech_challenges(id) on delete cascade,
  body_hash       text not null,
  native          text not null,
  level           text not null,
  prompt_version  int  not null,
  payload         jsonb not null,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  primary key (challenge_id, body_hash, native, level, prompt_version)
);

create index if not exists speech_challenge_study_creator_idx
  on public.speech_challenge_study(created_by, created_at desc);

alter table public.speech_challenge_study enable row level security;
