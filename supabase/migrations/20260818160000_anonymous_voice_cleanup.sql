-- Anonymous voice cleanup.
--
-- The voice-clone onboarding opens an ANONYMOUS session so the learner can
-- hear their fluent voice before being asked for an account. That is the whole
-- point of the reorder — the app's strongest moment stopped sitting behind a
-- sign-up for a thing nobody had heard yet — but it means a real ElevenLabs
-- voice can now exist for a user that will never become an account.
--
-- Those cost money (a slot on a shared account ceiling), so they are collected:
-- the `cleanup-anonymous-voices` edge function asks this function who is stale,
-- deletes their voices upstream, then deletes the users (every user table
-- cascades from auth.users).
--
-- Nothing here decides policy on its own: the grace window and the batch size
-- are the caller's, so they can be changed without a migration.

-- ---------------------------------------------------------------------------
-- 1) Who is still nobody.
--
--    Two conditions, deliberately redundant. `is_anonymous` is the flag GoTrue
--    maintains, and linking Apple to an anonymous user clears it — but the
--    second condition is what makes a mistake impossible: a user with ANY row
--    in auth.identities has an account behind them, whatever the flag says.
--    This function deletes people's voices; it gets to be paranoid.
-- ---------------------------------------------------------------------------

create or replace function public.stale_anonymous_users(
  p_older_than_hours int default 48,
  p_limit int default 100
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
     and u.created_at < now() - make_interval(hours => greatest(p_older_than_hours, 1))
   order by u.created_at
   limit greatest(least(p_limit, 500), 1);
$$;

-- Service role only. This reads auth.users; no client may call it.
revoke all on function public.stale_anonymous_users(int, int) from public, anon, authenticated;
grant execute on function public.stale_anonymous_users(int, int) to service_role;

-- ---------------------------------------------------------------------------
-- 2) Schedule. Same shape as `settle_core_club`: best-effort, and the function
--    stands on its own if the extensions or the secrets aren't there.
--
--    The edge function authenticates on a shared secret rather than a JWT
--    (there is no user to be), so the schedule needs two values that must NOT
--    live in this file. Put them in the vault once, by hand:
--
--      select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--      select vault.create_secret('<random string>',           'cleanup_secret');
--
--    and set the same random string as CLEANUP_SECRET in the function's env.
--    Until both exist this block does nothing and says so.
-- ---------------------------------------------------------------------------

do $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'anonymous voice cleanup: pg_cron/pg_net unavailable, not scheduled';
    return;
  end if;

  create extension if not exists pg_cron;
  create extension if not exists pg_net;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'cleanup_secret' limit 1;

  if v_url is null or v_secret is null then
    raise notice 'anonymous voice cleanup: vault secrets missing, not scheduled';
    return;
  end if;

  perform cron.unschedule('cleanup_anonymous_voices')
    where exists (select 1 from cron.job where jobname = 'cleanup_anonymous_voices');

  -- 03:20 UTC — clear of the Core's 00:05 settlement.
  perform cron.schedule(
    'cleanup_anonymous_voices', '20 3 * * *',
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
  raise notice 'anonymous voice cleanup scheduling skipped: %', sqlerrm;
end $$;
