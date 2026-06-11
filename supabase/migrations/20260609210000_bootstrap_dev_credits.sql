-- TEMPORARY: until RevenueCat integration is live, every new user gets
-- a one-shot 1000-credit bootstrap on signup so they can actually use the
-- credit-gated Edge Functions during TestFlight beta. The grant_credits
-- function is idempotent on the (user_id + 'bootstrap') key, so this won't
-- double-grant if the trigger fires twice.
--
-- BEFORE PRODUCTION LAUNCH:
--   1. Drop this trigger
--   2. Replace with RC-webhook-driven grant on trial start
-- Both are tracked in usage_ledger so you can audit who got bootstrap
-- credits vs. real entitlement credits later.

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
begin
  perform public.grant_credits(
    p_user_id => new.id,
    p_credits => 1000,
    p_kind => 'grant',
    p_action => 'dev_bootstrap',
    p_source_fn => 'auth_trigger',
    p_idempotency_key => 'bootstrap:' || new.id::text,
    p_metadata => jsonb_build_object('reason', 'pre-RC dev bootstrap, remove for prod')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_credits on auth.users;
create trigger on_auth_user_created_credits
  after insert on auth.users
  for each row execute function public.handle_new_user_credits();

-- Also retro-grant any users who already exist (i.e. you, who signed up
-- during the earlier development today). Idempotency key dedupes if rerun.
do $$
declare
  u record;
begin
  for u in select id from auth.users loop
    perform public.grant_credits(
      p_user_id => u.id,
      p_credits => 1000,
      p_kind => 'grant',
      p_action => 'dev_bootstrap',
      p_source_fn => 'migration',
      p_idempotency_key => 'bootstrap:' || u.id::text,
      p_metadata => jsonb_build_object('reason', 'retro-grant existing accounts')
    );
  end loop;
end;
$$;
