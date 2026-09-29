-- ---------------------------------------------------------------------------
-- 30 more minutes for 2bda6067, as goodwill (2026-09-27, founder's call).
--
-- NOT because they ran out. At the time this was written they had ~130 of the
-- trial's 140 minutes left (the trial pool is the stamped plan pro-rated 7/30,
-- and `20260926150000` re-stamped them onto today's Plus, so 600 × 7/30 = 140
-- where the day before it was Light's 35). `user_credits.balance` reading 0 is
-- the INVITE pool, which is a different pool and was spent on 09-25's grant —
-- their calls since have been `covered_by = trial`.
--
-- So this is a gift on top, and it keeps its value after the trial converts on
-- 09-28: `consume_metered_seconds` spends the balance BEFORE the plan's pool
-- (step 1), so these 1,800 seconds sit in front of the 600-minute month rather
-- than expiring with the trial.
--
-- Idempotent per user, and deliberately a DIFFERENT key from the 09-25 grant
-- (`trial_topup_30min:…`) so it lands once rather than being swallowed.
-- ---------------------------------------------------------------------------

do $$
declare
  v_uid uuid := '2bda6067-5324-4ad2-ae9b-adbca2592800';
begin
  if not exists (select 1 from auth.users where id = v_uid) then
    raise notice 'goodwill: user not found, nothing granted';
    return;
  end if;
  perform public.grant_credits(
    v_uid, 1800, 'grant'::public.ledger_kind,
    'goodwill_grant', 'migration',
    'goodwill_30min_20260927:' || v_uid::text,
    jsonb_build_object('reason', 'goodwill, on top of the trial pool',
                       'migration', '20260927100000'));
end $$;
