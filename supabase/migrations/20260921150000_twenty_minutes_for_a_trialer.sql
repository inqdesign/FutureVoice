-- ---------------------------------------------------------------------------
-- Twenty more minutes for one trialer who is using the trial for real.
--
-- vptjrknp2b@privaterelay.appleid.com: Plus trial since 2026-09-16, 1,768 of
-- the trial's 2,100 s spoken with two days left (ends 2026-09-23 07:46 UTC,
-- auto-renew on). The founder's call: let them keep talking until the plan
-- starts instead of meeting the trial wall first.
--
-- Balance pays BEFORE the trial pool (`consume_metered_seconds` step 1,
-- "invite minutes first"), so 1,200 s here is 20 minutes on top of what the
-- trial has left, and `talk_allowance().bonus` shows it. Idempotent per user.
-- ---------------------------------------------------------------------------

do $$
declare
  v_uid uuid;
begin
  select id into v_uid from auth.users
   where email = 'vptjrknp2b@privaterelay.appleid.com';
  if v_uid is null then
    raise notice 'twenty minutes: user not found, nothing granted';
    return;
  end if;
  perform public.grant_credits(
    v_uid, 1200, 'grant'::public.ledger_kind,
    'goodwill_grant', 'migration',
    'goodwill_trial_twenty:' || v_uid::text,
    jsonb_build_object('reason', 'active trialer, keep talking until the plan starts',
                       'migration', '20260921150000'));
end $$;
