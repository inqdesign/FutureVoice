-- A voice nobody is paying for is PARKED after 7 days: deleted upstream,
-- remembered here, rebuilt from the phone's recording the day it is wanted.
--
-- Why (2026-09-28): ElevenLabs Pro holds 160 custom voices for the whole
-- account and every learner's clone is one of them. Measured that day: 96
-- used, 87 of them learners' clones — 6 subscribers, 25 lapsed subscribers
-- (20 idle a week), 56 free accounts with minutes left (22 idle a week, 14
-- never talked once). The slots were being held by people who had left, and
-- the next tier (Scale, 660) is $200 a month more for capacity nobody uses.
--
-- The two rules, both 7 days (founder's call):
--   A. Not entitled, nothing left to spend (balance <= 0), and 7 days since
--      the balance was last spent or the subscription last ran.
--   B. Not entitled, free minutes still left, and 7 days with no activity at
--      all. These get their voice back AUTOMATICALLY when they return — the
--      app re-clones from the recording on the phone — because the minutes
--      are theirs and the voice is what they spend them with.
--
-- What parking is NOT:
--   * Not an account deletion. Every row, every talk, every book stays.
--   * Not `is_active = false`. An old build that sees no active row calls
--     `voiceWasDeleted` and walks the learner into re-recording — which would
--     mint a free clone and take the slot straight back. The row stays active
--     and `parked_at` is what the TTS function and the gateway read, so an old
--     build meets a 402 (the paywall) instead.
--   * Not a loss of audio. Everything already synthesized is on the phone
--     (PhraseAudioStore, TurnAudioStore) and keeps playing. Parking stops
--     NEW synthesis, nothing else.

alter table public.voice_clones
  add column if not exists parked_at timestamptz;

comment on column public.voice_clones.parked_at is
  'Set when the voice was deleted upstream because nobody was paying for it '
  '(park-idle-voices). The row stays is_active so old builds hit the 402, not '
  'a re-record. A re-clone inserts a fresh row; this one is then deactivated.';

-- Who is paying right now. The same three statuses consume_metered_seconds
-- treats as entitled, plus the admin `unlimited` flag.
create or replace function public.voice_owner_is_entitled(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
           select 1 from user_subscriptions s
            where s.user_id = p_user_id
              and s.status in ('trialing', 'active', 'grace'))
      or coalesce((select unlimited from user_credits where user_id = p_user_id), false);
$$;

revoke all on function public.voice_owner_is_entitled(uuid) from public, anon, authenticated;
grant execute on function public.voice_owner_is_entitled(uuid) to service_role;

-- Owners of an active, unparked clone that rule A or B says to park.
-- Anonymous users are left to cleanup-anonymous-voices (30 min), which
-- deletes the whole user.
create or replace function public.parkable_voice_owners(
  p_idle_days int default 7,
  p_limit int default 100
)
returns table (user_id uuid, rule text, balance numeric, idle_since timestamptz)
language sql
stable
security definer
set search_path = public, auth
as $$
  with v as (
    select vc.user_id, max(vc.created_at) as cloned_at
      from voice_clones vc
     where vc.is_active and vc.parked_at is null
     group by vc.user_id
  ),
  facts as (
    select v.user_id,
           coalesce(c.balance, 0) as balance,
           -- Last time the free balance or a plan was actually SPENT.
           (select max(l.created_at) from usage_ledger l
             where l.user_id = v.user_id and l.delta < 0) as last_spend,
           -- Last time anything at all happened on the account. Grants are
           -- not activity: the 2026-09-26 top-up wrote a row on every account.
           greatest(
             (select max(l.created_at) from usage_ledger l
               where l.user_id = v.user_id and l.delta <= 0),
             (select max(e.created_at) from client_events e
               where e.user_id = v.user_id)
           ) as last_seen,
           (select max(s.current_period_end) from user_subscriptions s
             where s.user_id = v.user_id) as sub_ended,
           v.cloned_at
      from v
      join auth.users u on u.id = v.user_id
      left join user_credits c on c.user_id = v.user_id
     where not coalesce(u.is_anonymous, false)
       and not public.voice_owner_is_entitled(v.user_id)
  )
  select f.user_id,
         case when f.balance <= 0 then 'spent' else 'idle' end,
         f.balance,
         case when f.balance <= 0
              then greatest(f.last_spend, f.sub_ended, f.cloned_at)
              else greatest(f.last_seen, f.sub_ended, f.cloned_at) end
    from facts f
   where case when f.balance <= 0
              then greatest(f.last_spend, f.sub_ended, f.cloned_at)
              else greatest(f.last_seen, f.sub_ended, f.cloned_at) end
         < now() - make_interval(days => greatest(p_idle_days, 7))
   order by 4
   limit greatest(least(p_limit, 500), 1);
$$;

revoke all on function public.parkable_voice_owners(int, int) from public, anon, authenticated;
grant execute on function public.parkable_voice_owners(int, int) to service_role;

-- May this user mint a new clone? Always, EXCEPT an account whose voice was
-- parked and that has nothing to spend it with — otherwise "re-record" in Me
-- would hand back, for free, the exact slot the sweep just reclaimed. A brand
-- new account has no parked row and is never refused here.
create or replace function public.voice_clone_allowed(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (select 1 from voice_clones
                      where user_id = p_user_id and parked_at is not null)
      or public.voice_owner_is_entitled(p_user_id)
      or coalesce((select balance from user_credits where user_id = p_user_id), 0) > 0;
$$;

revoke all on function public.voice_clone_allowed(uuid) from public, anon, authenticated;
grant execute on function public.voice_clone_allowed(uuid) to service_role;

-- The learner may read their own row's parked_at (voice_clones is already
-- owner-readable). Nothing to grant.

-- Sweep hourly. Same vault-gated pattern as cleanup_anonymous_voices; the
-- function stands on its own if pg_cron or the secrets are absent.
--
-- DEPLOY ORDER: this schedule must NOT run before the app build that knows
-- about parking is live in the App Store, and not before elevenlabs-tts and
-- the gateway read parked_at. So the schedule is created DISABLED here;
-- turn it on by hand:  select cron.alter_job(jobid, active := true)
--                       from cron.job where jobname = 'park_idle_voices';
do $$
declare
  v_url text;
  v_secret text;
  v_job bigint;
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'park idle voices: pg_cron/pg_net unavailable, not scheduled';
    return;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'cleanup_secret' limit 1;
  if v_url is null or v_secret is null then
    raise notice 'park idle voices: vault secrets missing, not scheduled';
    return;
  end if;

  perform cron.unschedule('park_idle_voices')
    where exists (select 1 from cron.job where jobname = 'park_idle_voices');

  select cron.schedule(
    'park_idle_voices', '20 * * * *',
    format(
      $cron$select net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Cleanup-Secret', %L
        ),
        body := '{}'::jsonb
      );$cron$,
      v_url || '/functions/v1/park-idle-voices',
      v_secret
    )
  ) into v_job;

  perform cron.alter_job(v_job, active := false);
exception when others then
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;
