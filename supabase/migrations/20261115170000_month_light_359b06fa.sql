-- One month of Light for 359b06fa-623b-4b92-a4b8-de1d03a1777e (founder,
-- 2026-11-15). Signed up today, spent the free minutes, no subscription.
-- Granted directly, the way redeem_referral's comp branch does it, through a
-- one-person code that is marked redeemed here so the record reads like every
-- other comp (comp_redemptions, ledger audit). Ends by itself in a month.
-- Balance is already 0, so nothing to clear.

insert into public.comp_codes (code, plan_id, months, max_redemptions, replaces_free_minutes, note, expires_at)
values ('GIFT359B06FA', 'light_monthly', 1, 1, true, 'month free (direct): 359b06fa', now() + interval '1 day')
on conflict (code) do nothing;

do $$
declare
  v_user uuid := '359b06fa-623b-4b92-a4b8-de1d03a1777e';
  v_until timestamptz := now() + interval '1 month';
begin
  if exists (select 1 from public.comp_redemptions where user_id = v_user) then
    raise notice 'already comped, skipping';
    return;
  end if;
  if exists (select 1 from public.user_subscriptions
              where user_id = v_user and status in ('trialing','active','grace')
                and source <> 'comp') then
    raise notice 'already subscribed, skipping';
    return;
  end if;

  insert into public.user_subscriptions (
    user_id, plan_id, source, status,
    current_period_start, current_period_end, cancel_at_period_end, updated_at)
  values (v_user, 'light_monthly', 'comp', 'active', now(), v_until, true, now())
  on conflict (user_id) do update
    set plan_id = excluded.plan_id, source = 'comp',
        apple_original_tx_id = null, stripe_subscription_id = null,
        trial_ends_at = null, status = excluded.status,
        current_period_start = excluded.current_period_start,
        current_period_end = excluded.current_period_end,
        cancel_at_period_end = true,
        renewal_offer_type = null, renewal_offer_id = null,
        renewal_price_milliunits = null, renewal_currency = null,
        renewal_product_id = null, updated_at = now();

  insert into public.comp_redemptions (code, user_id, plan_id, granted_until)
  values ('GIFT359B06FA', v_user, 'light_monthly', v_until);

  update public.comp_codes set redeemed_count = redeemed_count + 1
   where code = 'GIFT359B06FA';

  insert into public.usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (v_user, 'grant', 0, 'comp_subscription', 'migration',
          'comp:GIFT359B06FA:' || v_user::text,
          jsonb_build_object('code', 'GIFT359B06FA', 'plan_id', 'light_monthly',
                             'months', 1, 'until', v_until, 'note', 'direct grant'))
  on conflict (idempotency_key) do nothing;
end $$;
