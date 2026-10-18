-- ---------------------------------------------------------------------------
-- A subscription waiting on the learner's consent to be charged (2026-10-18).
--
-- Korean law (KFTC, in force 2025-02-14) asks for a SECOND consent before a
-- free trial or a discounted offer turns into the regular price. Apple runs
-- it as a price-increase consent: email, push and an in-app sheet, opened 24 h
-- after the trial starts. A trialer who never answers is not charged and the
-- subscription simply ends (`expirationIntent 3`) with auto-renew still ON.
-- Measured 2026-09-23: six Korean trialers reached their renewal, all six were
-- asked, four never answered and lapsed. Four of the seven people who ever
-- paid us had been asked the same question and said yes.
--
-- Apple tells us about it (`PRICE_INCREASE` / `PENDING`, then `ACCEPTED`) and
-- the webhook dropped both: `statusFor` treats the notification as saying
-- nothing about standing (right) and nothing else read it (wrong), and the
-- transaction ledger is keyed on transaction_id, so a later notification on
-- the same transaction overwrote the PENDING row. Nobody could see who was
-- waiting, so nobody could say anything to them.
--
-- Two columns, written by `apple-webhook` and read by `consent-reminder`
-- (the push two days before the charge), the admin console and the app's
-- own check (the app reads StoreKit's `priceIncreaseStatus` directly; these
-- are for the server side, which cannot).
--
--   price_consent_pending_since  set when Apple starts asking, cleared when
--                                the learner agrees, the plan renews, or it ends
--   price_consent_due_at         the renewal that will not happen without it
-- ---------------------------------------------------------------------------

alter table public.user_subscriptions
  add column if not exists price_consent_pending_since timestamptz,
  add column if not exists price_consent_due_at timestamptz;

-- The reminder job reads only waiting rows.
create index if not exists user_subscriptions_price_consent_idx
  on public.user_subscriptions (price_consent_due_at)
  where price_consent_pending_since is not null;

-- Hourly. Vault-gated like owner_watch and the voice cleanup: nothing here may
-- fail the migration, and without pg_cron or the secrets the function still
-- stands and can be called by hand.
do $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'consent reminder: pg_cron/pg_net unavailable, not scheduled';
    return;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'cleanup_secret' limit 1;
  if v_url is null or v_secret is null then
    raise notice 'consent reminder: vault secrets missing, not scheduled';
    return;
  end if;

  perform cron.unschedule('consent_reminder')
    where exists (select 1 from cron.job where jobname = 'consent_reminder');

  perform cron.schedule(
    'consent_reminder', '17 * * * *',
    format(
      $cron$select net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Cleanup-Secret', %L
        ),
        body := '{}'::jsonb
      );$cron$,
      v_url || '/functions/v1/consent-reminder',
      v_secret
    )
  );
exception when others then
  raise notice 'consent reminder scheduling skipped: %', sqlerrm;
end $$;
