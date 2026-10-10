-- ---------------------------------------------------------------------------
-- A standing Plus comp for the Google Play review account.
--
-- Play reviewers cannot buy, cannot start a trial and cannot use their own
-- account (Play Console → Sign in details says so outright), so the account
-- handed to them in Sign in details has to reach every feature on its own.
-- `nawana.review@gmail.com` was created for that on 2026-10-06 and signed into
-- the Android app once, which is what made the auth row this reads.
--
-- Standing (`cancel_at_period_end = false`): `expire_comp_subscriptions` rolls
-- it forward a month at a time instead of ending it, because every future
-- Play review signs in with the same account. Keyed by email so the file says
-- whose seat it is; it inserts nothing if that account does not exist.
-- ---------------------------------------------------------------------------

insert into public.user_subscriptions
  (user_id, plan_id, status, source, cancel_at_period_end,
   current_period_start, current_period_end, started_at, updated_at)
select u.id, 'plus_monthly', 'active', 'comp', false,
       now(), now() + interval '1 month', now(), now()
  from auth.users u
 where u.email = 'nawana.review@gmail.com'
on conflict (user_id) do update
   set plan_id              = excluded.plan_id,
       status               = excluded.status,
       source               = excluded.source,
       cancel_at_period_end = excluded.cancel_at_period_end,
       current_period_start = excluded.current_period_start,
       current_period_end   = excluded.current_period_end,
       updated_at           = now();
