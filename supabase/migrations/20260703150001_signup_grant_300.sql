-- Beta signup grant: 1000 → 300 credits for NEW signups.
--
-- 300 covers a full one-week beta comfortably (~1h of conversation + a few
-- Watch dialogues + the weekly-report unlock at 15 speaking minutes) while
-- keeping ElevenLabs capacity math sane: 10 testers × 300 = 3,000 worst-case
-- vs 1,000 each = 10,000. See docs/launch-billing.md.
--
-- Existing accounts keep whatever they already received (grants are ledger
-- entries, not entitlements — nothing to claw back). Idempotency prefix
-- changes to 'beta300:' so the ledger distinguishes grant generations.

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
begin
  perform public.grant_credits(
    p_user_id => new.id,
    p_credits => 300,
    p_kind => 'grant',
    p_action => 'beta_signup_grant',
    p_source_fn => 'auth_trigger',
    p_idempotency_key => 'beta300:' || new.id::text,
    p_metadata => jsonb_build_object('reason', 'testflight beta signup grant')
  );
  return new;
end;
$$;
