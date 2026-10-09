-- The default accent for the German learners who cloned BEFORE it existed
-- (2026-10-09, founder decision).
--
-- `_shared/default-accent.ts` remixes an old build's plain clone into Standard
-- German the first time it speaks German — but only clones made since
-- 2026-10-08 carry `accent_by_server`, so every German learner who cloned
-- before that still hears the accent the model invents per line. And the
-- inline remix also gave up on 10-09 for new clones whenever the account's
-- monthly voice allowance sat at the reserve.
--
-- So: in the background, one learner at a time, and ONLY for learners who
-- come back — a voice is an ElevenLabs add/edit (Pro: 290 a month, never
-- refunded), and spending one on someone who never opens the app again buys
-- nothing. "Comes back" = their auth session refreshed after `p_since`, the
-- moment this started; "old" = the clone existed before it.
--
-- "German" = the target the learner picked (`profiles.target_language`, but
-- only once a build has written it — `setup_at`; before that the column is
-- the trigger's 'en'), else the language they last talked in.
--
-- Left alone on purpose:
--   * anyone who has EVER remixed (`usage_ledger.action = 'voice_remix'`) —
--     their live voice may be an accent they picked, and remixing a remix is
--     the drift 2026-09-18 fixed;
--   * parked voices (there is nothing upstream to remix);
--   * a voice the backfill already tried three times, or tried in the last
--     hour (`default_accent_backfill_log`).
--
-- The remix itself is `speakAs` — the same code, row shape and ledger row as
-- the inline path, so the gateway and `elevenlabs-tts` pick it up with no
-- change. Driver: `default-accent-backfill` every 10 minutes.

create table if not exists public.default_accent_backfill_log (
  voice_id   text primary key,
  user_id    uuid not null,
  tries      int not null default 0,
  last_at    timestamptz not null default now(),
  result     text
);
alter table public.default_accent_backfill_log enable row level security;
-- No policies: service role only.

create or replace function public.default_accent_backfill_candidates(
  p_since timestamptz,
  p_limit int default 3
) returns table (user_id uuid, voice_id text, name text)
language sql
stable
security definer
set search_path = public, auth
as $$
  select vc.user_id, vc.elevenlabs_voice_id, vc.name
    from public.voice_clones vc
    join auth.users u on u.id = vc.user_id and not coalesce(u.is_anonymous, false)
    left join public.profiles p on p.id = vc.user_id
    left join lateral (select t.language from public.talk_seconds_by_language t
                        where t.user_id = vc.user_id
                        order by t.updated_at desc limit 1) lt on true
   where coalesce(case when p.setup_at is not null then p.target_language end, lt.language) like 'de%'
     and vc.is_active
     and vc.parked_at is null
     and vc.speak_as_voice_id is null
     and (vc.speak_as_started_at is null or vc.speak_as_started_at < now() - interval '2 minutes')
     and vc.created_at < p_since
     and not exists (select 1 from public.usage_ledger l
                      where l.user_id = vc.user_id and l.action = 'voice_remix')
     and not exists (select 1 from public.default_accent_backfill_log b
                      where b.voice_id = vc.elevenlabs_voice_id
                        and (b.tries >= 3 or b.last_at > now() - interval '1 hour'))
     and (exists (select 1 from auth.sessions s
                   where s.user_id = vc.user_id
                     and ((s.refreshed_at at time zone 'utc') > p_since or s.updated_at > p_since))
          or exists (select 1 from auth.refresh_tokens rt
                      where rt.user_id = vc.user_id::text and rt.updated_at > p_since))
   order by vc.created_at
   limit greatest(1, least(coalesce(p_limit, 3), 10));
$$;

revoke all on function public.default_accent_backfill_candidates(timestamptz, int) from public, anon, authenticated;

-- Every 10 minutes, same vault secrets and header as park-idle-voices.
do $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'default accent backfill: pg_cron/pg_net unavailable, not scheduled';
    return;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'cleanup_secret' limit 1;
  if v_url is null or v_secret is null then
    raise notice 'default accent backfill: vault secrets missing, not scheduled';
    return;
  end if;

  perform cron.unschedule('default_accent_backfill')
    where exists (select 1 from cron.job where jobname = 'default_accent_backfill');

  perform cron.schedule(
    'default_accent_backfill', '*/10 * * * *',
    format(
      $cron$select net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Cleanup-Secret', %L
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 150000
      );$cron$,
      v_url || '/functions/v1/default-accent-backfill',
      v_secret
    )
  );
exception when others then
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;
