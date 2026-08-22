-- Reclaim unclaimed anonymous voice clones FAST (2026-08-22).
--
-- The old grace was 48h and the sweep ran once nightly (03:20 UTC), so an
-- unclaimed clone could hold an ElevenLabs voice slot for up to ~48-72h. That
-- is the window an attacker farms: mint a clone from a throwaway anonymous
-- session, abandon it, repeat — hundreds of slots stay occupied between nightly
-- runs, exhausting the paid voice ceiling and blocking real users.
--
-- A GLOBAL CAP on outstanding unclaimed clones was considered and rejected: it
-- is a shared ceiling, so previous low-intent users who piled up unclaimed
-- clones would block the NEXT willing user — punishing exactly the person we
-- want to let in. Fast reclaim has no shared ceiling; it just shortens each
-- clone's unclaimed lifetime.
--
-- Aggressive reclaim is safe here because the SOURCE RECORDING stays on the
-- device: a returning user rebuilds the clone from it with NO re-recording
-- (FutureVoiceApp.swift `cloneVoice` / "Rebuild the clone from your last
-- recording"). So deleting an abandoned upstream clone costs a returning real
-- user at most a silent few-second rebuild, not their voice.
--
-- The grace CANNOT go to zero, though: the rebuild only rescues someone who
-- LEFT and CAME BACK, not someone still mid-onboarding right now (their live
-- greeting / Meet / daily-call TTS would 404 if we deleted the clone out from
-- under them). So the floor is "longer than one uninterrupted onboarding
-- session" — a few minutes of real conversation plus margin. 30 minutes clears
-- that comfortably while reclaiming abandoners within ~45 min (grace + the
-- 15-minute sweep interval below).

-- Switch the grace unit from HOURS to MINUTES so sub-hour windows are
-- expressible. Same (int, int) arg types, but the parameter is renamed, which
-- create-or-replace refuses — drop and recreate. Signature-level grants are
-- re-applied after.
drop function if exists public.stale_anonymous_users(int, int);

create function public.stale_anonymous_users(
  p_older_than_minutes int default 30,
  p_limit int default 200
)
returns table (user_id uuid, created_at timestamptz)
language sql
security definer
set search_path = public, auth
as $$
  select u.id, u.created_at
    from auth.users u
   where coalesce(u.is_anonymous, false)
     and not exists (select 1 from auth.identities i where i.user_id = u.id)
     -- Floor at 5 minutes: never delete a clone younger than the shortest
     -- possible live onboarding session, whatever a caller passes.
     and u.created_at < now() - make_interval(mins => greatest(p_older_than_minutes, 5))
   order by u.created_at
   limit greatest(least(p_limit, 500), 1);
$$;

revoke all on function public.stale_anonymous_users(int, int) from public, anon, authenticated;
grant execute on function public.stale_anonymous_users(int, int) to service_role;

-- Sweep every 15 minutes instead of once nightly, so a 30-minute grace
-- actually results in ~45-minute reclaim rather than next-day. Best-effort,
-- same vault-gated pattern as the original schedule; the function stands on its
-- own if pg_cron/secrets are absent.
do $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'anonymous voice cleanup: pg_cron/pg_net unavailable, not rescheduled';
    return;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'cleanup_secret' limit 1;
  if v_url is null or v_secret is null then
    raise notice 'anonymous voice cleanup: vault secrets missing, not rescheduled';
    return;
  end if;

  perform cron.unschedule('cleanup_anonymous_voices')
    where exists (select 1 from cron.job where jobname = 'cleanup_anonymous_voices');

  perform cron.schedule(
    'cleanup_anonymous_voices', '*/15 * * * *',
    format(
      $cron$select net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Cleanup-Secret', %L
        ),
        body := '{}'::jsonb
      );$cron$,
      v_url || '/functions/v1/cleanup-anonymous-voices',
      v_secret
    )
  );
exception when others then
  raise notice 'pg_cron rescheduling skipped: %', sqlerrm;
end $$;
