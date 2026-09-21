-- ---------------------------------------------------------------------------
-- The clone recording is kept for ONE DAY.
--
-- 20260914120000 started saving it because ElevenLabs' copy dies with the
-- voice and an accent pick deletes the voice seconds later — so a clone that
-- came out wrong could not be looked at even minutes after the complaint.
-- That is the whole purpose, and it is a purpose measured in hours: long
-- enough to survive a night so a problem reported in the morning still has
-- something to listen to, short enough to say in one sentence on the consent
-- screen. Keeping it longer would make this a voice corpus, which is not what
-- anybody agreed to.
--
-- Storage has no TTL and deleting the `storage.objects` row alone orphans the
-- file in the backing store, so the delete has to go through the Storage API:
-- this function only FINDS them, `purge-voice-originals` removes them hourly.
-- ---------------------------------------------------------------------------

create or replace function public.expired_voice_originals(
  p_older_than_hours int default 24,
  p_limit int default 500
)
returns table (path text, folder text)
language sql
security definer
set search_path = public, storage
as $$
  select o.name,
         -- `<user_id>/<voice_id>` — what voice_clones.original_path holds.
         regexp_replace(o.name, '/[^/]*$', '')
    from storage.objects o
   where o.bucket_id = 'voice-originals'
     -- Floor at 1 hour: a caller must not be able to delete a recording out
     -- from under the clone that is still being built from it.
     and o.created_at < now() - make_interval(hours => greatest(p_older_than_hours, 1))
   order by o.created_at
   limit greatest(least(p_limit, 2000), 1);
$$;

revoke all on function public.expired_voice_originals(int, int) from public, anon, authenticated;
grant execute on function public.expired_voice_originals(int, int) to service_role;

-- Hourly sweep. Same vault-gated pattern as the anonymous-voice cleanup; the
-- function stands on its own if pg_cron or the secrets are absent.
do $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'voice originals purge: pg_cron/pg_net unavailable, not scheduled';
    return;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'cleanup_secret' limit 1;
  if v_url is null or v_secret is null then
    raise notice 'voice originals purge: vault secrets missing, not scheduled';
    return;
  end if;

  perform cron.unschedule('purge_voice_originals')
    where exists (select 1 from cron.job where jobname = 'purge_voice_originals');

  perform cron.schedule(
    'purge_voice_originals', '35 * * * *',
    format(
      $cron$select net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Cleanup-Secret', %L
        ),
        body := '{}'::jsonb
      );$cron$,
      v_url || '/functions/v1/purge-voice-originals',
      v_secret
    )
  );
exception when others then
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;
