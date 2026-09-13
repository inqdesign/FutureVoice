-- user_directory: say what the subscription is DOING, not just what it is.
--
-- The view listed plan_id + status, so a trial that was cancelled the same
-- hour it started read "trialing" — the same word as a trial still running.
-- Two people did exactly that on 2026-09-12 and the only way to tell was
-- to join user_subscriptions by hand. Columns are APPENDED (create or
-- replace cannot reorder or drop view columns), and `subscription_state`
-- folds the four booleans/dates into one word so the Table Editor row is
-- readable without a legend:
--
--   none            no subscription row
--   trial           trial running, will convert
--   trial·cancelled trial running, auto-renew off → ends at trial_ends_at
--   active          paid, renews
--   cancelled       paid, auto-renew off → ends at current_period_end
--   <status>        anything else (past_due, expired, …) verbatim
create or replace view public.user_directory as
select
  au.id                                   as user_id,
  au.email,
  p.display_name,
  coalesce(
    nullif(p.display_name, ''),
    nullif(split_part(coalesce(au.email, ''), '@', 1), ''),
    left(au.id::text, 8)
  )                                       as label,
  (au.email like '%@privaterelay.appleid.com') as email_is_relay,
  au.created_at                           as signed_up_at,
  s.plan_id,
  s.status                                as subscription_status,
  -- appended 2026-09-12
  case
    when s.user_id is null                                        then 'none'
    when s.status = 'trialing' and s.cancel_at_period_end         then 'trial·cancelled'
    when s.status = 'trialing'                                    then 'trial'
    when s.status = 'active'   and s.cancel_at_period_end         then 'cancelled'
    when s.status = 'active'                                      then 'active'
    else s.status
  end                                     as subscription_state,
  s.cancel_at_period_end,
  s.started_at                            as subscribed_at,
  s.trial_ends_at,
  s.current_period_end,
  s.source                                as subscription_source,
  s.updated_at                            as subscription_updated_at,
  au.last_sign_in_at,
  p.location,
  p.language                              as persona_language
from auth.users au
left join lateral (
  select pp.display_name, pp.location, pp.language
  from public.public_personas pp
  where pp.owner_user_id = au.id and pp.is_active
  order by pp.updated_at desc
  limit 1
) p on true
left join public.user_subscriptions s on s.user_id = au.id;

revoke all on public.user_directory from anon, authenticated;
