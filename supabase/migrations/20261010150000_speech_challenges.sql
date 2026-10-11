-- Speech challenges: scripts the founder publishes for EVERY learner of a
-- target language, each with its own leaderboard. A learner's own scripts
-- stay private and have no board.
--
-- Rules (founder decisions, 2026-10-10):
--   * one board per script, per target language; no level brackets — the
--     board is a bowling alley's, everybody on it;
--   * only a take recorded with the CAMERA on is entered (the cheapest guard
--     against a speaker playing someone else's voice) — and the video is
--     never published, nor the audio: a board shows a name, a score and,
--     when the learner chose to show it, a small profile photo;
--   * a learner's BEST take stands; attempts are counted.
--
-- The score is computed on the phone by `SpeechAnalyzer` (code, never a
-- model). The server can't re-run it, but it can check the overall is the
-- documented weighting of its five parts, which turns a hand-edited request
-- into work rather than a single number.

create table if not exists public.speech_challenges (
  id              uuid primary key default gen_random_uuid(),
  language        text not null,
  title           text not null,
  genre           text not null default 'explainer',
  body            text not null,
  summary         text not null default '',
  key_terms       jsonb not null default '[]'::jsonb,
  sources         jsonb not null default '[]'::jsonb,
  target_seconds  int  not null default 60,
  created_by      uuid references auth.users(id) on delete set null,
  published_at    timestamptz not null default now(),
  is_active       boolean not null default true
);

create index if not exists speech_challenges_language_idx
  on public.speech_challenges(language, published_at desc) where is_active;

alter table public.speech_challenges enable row level security;

drop policy if exists "speech_challenges: read active" on public.speech_challenges;
create policy "speech_challenges: read active" on public.speech_challenges
  for select using (is_active);

-- How a learner appears on every board: one name, and a profile photo only
-- if they chose to show it. The photo is a ~96 px JPEG as base64 — small
-- enough for a column, and the app never uses Supabase Storage. Profile
-- photos otherwise live only on the phone (`AvatarStore`).
create table if not exists public.speech_challenge_profiles (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  display_name    text not null,
  avatar_jpeg     text,
  updated_at      timestamptz not null default now()
);

alter table public.speech_challenge_profiles enable row level security;

create table if not exists public.speech_challenge_entries (
  challenge_id    uuid not null references public.speech_challenges(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  best_score      int  not null,
  accuracy        int  not null,
  pace_score      int  not null,
  pause_score     int  not null,
  filler_score    int  not null,
  steadiness      int  not null,
  seconds         int  not null,
  attempts        int  not null default 1,
  best_at         timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (challenge_id, user_id)
);

create index if not exists speech_challenge_entries_board_idx
  on public.speech_challenge_entries(challenge_id, best_score desc, best_at);

-- No policies on either table: they are read only through the functions
-- below, which hand out a name, a photo and a score and never a user id.
alter table public.speech_challenge_entries enable row level security;

-- ---------------------------------------------------------------------------
-- The list: every active challenge of a language, with the caller's place.
-- ---------------------------------------------------------------------------
create or replace function public.speech_challenge_list(p_language text)
returns table (
  id uuid, title text, genre text, body text, summary text,
  key_terms jsonb, sources jsonb, target_seconds int, published_at timestamptz,
  entrants int, top_score int, my_best int, my_rank int, my_attempts int,
  top_three jsonb
)
language sql stable security definer set search_path = public as $$
  with ranked as (
    select e.challenge_id, e.user_id, e.best_score, e.attempts,
           rank() over (partition by e.challenge_id order by e.best_score desc) as r
    from speech_challenge_entries e
    join speech_challenges c on c.id = e.challenge_id
    where c.language = p_language and c.is_active
  )
  select c.id, c.title, c.genre, c.body, c.summary, c.key_terms, c.sources,
         c.target_seconds, c.published_at,
         (select count(*)::int from ranked x where x.challenge_id = c.id),
         (select max(x.best_score) from ranked x where x.challenge_id = c.id),
         me.best_score, me.r::int, me.attempts,
         coalesce((
           select jsonb_agg(jsonb_build_object('display_name', t.display_name, 'avatar', t.avatar_jpeg)
                            order by t.best_score desc, t.best_at)
           from (
             select p.display_name, p.avatar_jpeg, e.best_score, e.best_at
             from speech_challenge_entries e
             join speech_challenge_profiles p on p.user_id = e.user_id
             where e.challenge_id = c.id
             order by e.best_score desc, e.best_at
             limit 3
           ) t
         ), '[]'::jsonb)
  from speech_challenges c
  left join ranked me on me.challenge_id = c.id and me.user_id = auth.uid()
  where c.language = p_language and c.is_active
  order by c.published_at desc;
$$;

-- ---------------------------------------------------------------------------
-- The board: the top N, plus the caller's own row when it is below them.
-- ---------------------------------------------------------------------------
create or replace function public.speech_challenge_board(p_challenge uuid, p_limit int default 10)
returns table (rank int, display_name text, score int, is_me boolean)
language sql stable security definer set search_path = public as $$
  with ranked as (
    select e.user_id, p.display_name, e.best_score, e.best_at,
           rank() over (order by e.best_score desc)::int as r,
           row_number() over (order by e.best_score desc, e.best_at) as pos
    from speech_challenge_entries e
    join speech_challenges c on c.id = e.challenge_id and c.is_active
    join speech_challenge_profiles p on p.user_id = e.user_id
    where e.challenge_id = p_challenge
  )
  select r, display_name, best_score, user_id = auth.uid()
  from ranked
  where pos <= least(greatest(p_limit, 1), 50) or user_id = auth.uid()
  order by pos;
$$;

-- ---------------------------------------------------------------------------
-- How the caller appears on every board. Called from the name sheet, and by
-- every submit (so a photo changed since is picked up). A null photo means
-- "don't show one".
-- ---------------------------------------------------------------------------
create or replace function public.set_speech_challenge_profile(p_display_name text, p_avatar text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_name text := btrim(coalesce(p_display_name, ''));
  v_avatar text := nullif(p_avatar, '');
begin
  if auth.uid() is null then raise exception 'NOT_SIGNED_IN'; end if;
  if char_length(v_name) < 1 or char_length(v_name) > 24 then raise exception 'BAD_NAME'; end if;
  -- ~96 px JPEG is a few KB; refuse anything that isn't a thumbnail.
  if v_avatar is not null and char_length(v_avatar) > 40000 then raise exception 'BAD_AVATAR'; end if;
  insert into speech_challenge_profiles (user_id, display_name, avatar_jpeg)
  values (auth.uid(), v_name, v_avatar)
  on conflict (user_id) do update set
    display_name = excluded.display_name,
    avatar_jpeg  = excluded.avatar_jpeg,
    updated_at   = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Entering a take. Keeps the best; counts every attempt.
-- ---------------------------------------------------------------------------
create or replace function public.submit_speech_challenge_take(
  p_challenge uuid, p_display_name text, p_avatar text,
  p_overall int, p_accuracy int, p_pace int, p_pause int, p_filler int,
  p_steadiness int, p_seconds int
)
returns table (rank int, previous_rank int, entrants int, best int, improved boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_expected int;
  v_prev_best int;
  v_prev_rank int;
  v_improved boolean;
begin
  if v_uid is null then raise exception 'NOT_SIGNED_IN'; end if;
  if not exists (select 1 from speech_challenges where id = p_challenge and is_active) then
    raise exception 'CHALLENGE_NOT_FOUND';
  end if;
  if least(p_overall, p_accuracy, p_pace, p_pause, p_filler, p_steadiness) < 0
     or greatest(p_overall, p_accuracy, p_pace, p_pause, p_filler, p_steadiness) > 100
     or p_seconds < 1 or p_seconds > 1800 then
    raise exception 'BAD_SCORE';
  end if;
  -- SpeechAnalyzer.analyze's weighting.
  v_expected := round(0.40 * p_accuracy + 0.20 * p_pace + 0.15 * p_pause
                      + 0.10 * p_filler + 0.15 * p_steadiness);
  if abs(v_expected - p_overall) > 1 then raise exception 'BAD_SCORE'; end if;

  perform set_speech_challenge_profile(p_display_name, p_avatar);

  select e.best_score into v_prev_best
  from speech_challenge_entries e
  where e.challenge_id = p_challenge and e.user_id = v_uid;

  if v_prev_best is not null then
    select 1 + count(*)::int into v_prev_rank
    from speech_challenge_entries e
    where e.challenge_id = p_challenge and e.best_score > v_prev_best;
  end if;

  v_improved := v_prev_best is null or p_overall > v_prev_best;

  insert into speech_challenge_entries as e
    (challenge_id, user_id, best_score, accuracy, pace_score,
     pause_score, filler_score, steadiness, seconds)
  values (p_challenge, v_uid, p_overall, p_accuracy, p_pace,
          p_pause, p_filler, p_steadiness, p_seconds)
  on conflict (challenge_id, user_id) do update set
    attempts     = e.attempts + 1,
    updated_at   = now(),
    best_score   = case when v_improved then excluded.best_score   else e.best_score end,
    accuracy     = case when v_improved then excluded.accuracy     else e.accuracy end,
    pace_score   = case when v_improved then excluded.pace_score   else e.pace_score end,
    pause_score  = case when v_improved then excluded.pause_score  else e.pause_score end,
    filler_score = case when v_improved then excluded.filler_score else e.filler_score end,
    steadiness   = case when v_improved then excluded.steadiness   else e.steadiness end,
    seconds      = case when v_improved then excluded.seconds      else e.seconds end,
    best_at      = case when v_improved then now()                 else e.best_at end;

  return query
  select 1 + (select count(*)::int from speech_challenge_entries x
              where x.challenge_id = p_challenge and x.best_score > me.best_score),
         v_prev_rank,
         (select count(*)::int from speech_challenge_entries x where x.challenge_id = p_challenge),
         me.best_score,
         v_improved
  from speech_challenge_entries me
  where me.challenge_id = p_challenge and me.user_id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Publishing: admin accounts only (user_credits.unlimited, the same flag the
-- app's admin surfaces read).
-- ---------------------------------------------------------------------------
create or replace function public.publish_speech_challenge(
  p_language text, p_title text, p_genre text, p_body text, p_summary text,
  p_key_terms jsonb, p_sources jsonb, p_target_seconds int
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not exists (select 1 from user_credits where user_id = auth.uid() and unlimited) then
    raise exception 'NOT_ADMIN';
  end if;
  if char_length(btrim(coalesce(p_body, ''))) < 20 or char_length(btrim(coalesce(p_title, ''))) < 1 then
    raise exception 'BAD_SCRIPT';
  end if;
  insert into speech_challenges
    (language, title, genre, body, summary, key_terms, sources, target_seconds, created_by)
  values (p_language, btrim(p_title), coalesce(nullif(p_genre, ''), 'explainer'), btrim(p_body),
          coalesce(p_summary, ''), coalesce(p_key_terms, '[]'::jsonb),
          coalesce(p_sources, '[]'::jsonb), greatest(coalesce(p_target_seconds, 60), 10), auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.retire_speech_challenge(p_challenge uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from user_credits where user_id = auth.uid() and unlimited) then
    raise exception 'NOT_ADMIN';
  end if;
  update speech_challenges set is_active = false where id = p_challenge;
end;
$$;

revoke all on function public.speech_challenge_list(text) from public;
revoke all on function public.speech_challenge_board(uuid, int) from public;
revoke all on function public.set_speech_challenge_profile(text, text) from public;
revoke all on function public.submit_speech_challenge_take(uuid, text, text, int, int, int, int, int, int, int) from public;
revoke all on function public.publish_speech_challenge(text, text, text, text, text, jsonb, jsonb, int) from public;
revoke all on function public.retire_speech_challenge(uuid) from public;
grant execute on function public.speech_challenge_list(text) to authenticated;
grant execute on function public.speech_challenge_board(uuid, int) to authenticated;
grant execute on function public.set_speech_challenge_profile(text, text) to authenticated;
grant execute on function public.submit_speech_challenge_take(uuid, text, text, int, int, int, int, int, int, int) to authenticated;
grant execute on function public.publish_speech_challenge(text, text, text, text, text, jsonb, jsonb, int) to authenticated;
grant execute on function public.retire_speech_challenge(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- The first challenge: the bundled sample, in every language that has one.
-- Its id IS the bundled script's id (`SpeechLibrary.builtInId`), so the takes
-- already on learners' phones belong to the challenge, and the app shows the
-- challenge in place of the sample. The text is copied as it ships today; the
-- server copy is the one the board is read against.
-- ---------------------------------------------------------------------------
insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-000000000001', 'en', 'Why practise out loud?', 'explainer',
   'Have you ever had the perfect sentence in your head, only to watch it fall apart the moment you said it?

Speaking is a skill, not just knowledge. You can know the words and the grammar, but if your mouth has never actually built the sentence, it tends to let you down when it matters. That''s why practice has to happen out loud.

Saying things aloud also helps them stick. Research suggests we remember what we''ve said better than what we''ve only read.

And when you record yourself, you notice things you''d never catch otherwise: how fast you really talk, how often you say "um" and "uh", whether your voice fades at the end of a sentence.

Presentations, interviews, even a first conversation with someone new all get easier with practice. The minute you just spent reading this out loud? That was your first rep.', 60),
  ('5beec000-0000-4000-8000-000000000002', 'ko', '왜 소리 내어 연습해야 할까', 'explainer',
   '여러분, 머릿속에서는 완벽했던 문장이 막상 입 밖으로 나오는 순간 엉켜 버린 적, 있으시죠?

말하기는 아는 것과 하는 것이 다른 기술입니다. 단어와 문법을 알아도 입이 그 문장을 직접 만들어 본 적이 없으면, 정작 중요한 순간에 막힙니다. 그래서 연습은 소리 내어 해야 합니다.

소리 내어 말하면 기억에도 더 오래 남습니다. 눈으로만 읽은 내용보다 직접 말해 본 내용을 더 잘 기억한다는 연구도 있습니다.

녹음해서 들어 보면 더 많은 것이 보입니다. 내가 실제로 얼마나 빨리 말하는지, "음", "어" 같은 말을 얼마나 자주 하는지, 문장 끝에서 목소리가 작아지지는 않는지. 혼자서는 잘 모르는 것들이거든요.

발표도, 면접도, 처음 만나는 사람과 나누는 대화도 연습한 만큼 편해집니다. 지금 이 원고를 소리 내어 읽은 일 분이 바로 그 첫 연습입니다.', 60),
  ('5beec000-0000-4000-8000-000000000003', 'ja', '声に出して話そう', 'explainer',
   '皆さん、頭の中では完璧だった文が、口に出した瞬間に崩れてしまった経験はありませんか。

話すことは、知識ではなく技術です。単語や文法を知っていても、自分の口で一度も言ったことのない文は、いざという時に出てきません。だから練習は、声に出してするものなんです。

声に出すと、覚えやすくもなります。黙って読んだことより、声に出して言ったことのほうが記憶に残りやすい、という研究もあるそうです。

そして、自分の声を録音してみてください。本当はどのくらいの速さで話しているのか。「えーと」や「あの」を、どれだけ言っているのか。文の終わりで、声が小さくなっていないか。一人では気づけないことが、はっきり聞こえてきます。

発表も、面接も、初めての人との会話も、練習すれば楽になります。今この文章を声に出して読んだ一分間が、皆さんの最初の練習です。', 60),
  ('5beec000-0000-4000-8000-000000000004', 'de', 'Sprecht es laut aus', 'explainer',
   'Kennt ihr das? Im Kopf ist der Satz perfekt. Und sobald ihr ihn aussprecht, fällt er auseinander.

Sprechen ist eine Fähigkeit, nicht nur Wissen. Ihr könnt alle Wörter und die Grammatik kennen. Wenn euer Mund den Satz aber noch nie gebildet hat, lässt er euch im entscheidenden Moment im Stich. Deshalb müsst ihr laut üben.

Was ihr laut sagt, bleibt außerdem besser hängen. Studien deuten darauf hin, dass wir uns an Ausgesprochenes besser erinnern als an das, was wir nur still gelesen haben.

Nehmt euch dabei auf. Dann hört ihr, was euch allein nicht auffällt: wie schnell ihr wirklich sprecht, wie oft ihr „äh“ oder „ähm“ sagt, und ob eure Stimme am Satzende leiser wird.

Präsentationen, Vorstellungsgespräche, sogar ein Gespräch mit jemand Neuem: Mit Übung wird das alles leichter. Und die Minute, in der ihr das gerade laut gelesen habt? Das war eure erste Übung.', 60)
on conflict (id) do nothing;
