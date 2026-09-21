-- ---------------------------------------------------------------------------
-- user_directory: the voice beside the person.
--
-- Answering "whose voice is this, and do we still have the recording" meant
-- joining auth.users, voice_clones and the storage columns by hand, every
-- time — and the two questions that actually get asked (is this a real
-- account or a session mid-onboarding? do we hold their original?) were in
-- two different places. Both are one row now.
--
-- Columns are APPENDED — `create or replace view` cannot reorder or drop
-- them, so everything above the new block is the previous definition
-- verbatim (20260912150000).
--
-- ONE ROW PER PERSON: the ACTIVE clone, else their most recent one, so a
-- learner who re-recorded or picked an accent still reads as one line.
-- `voice_takes` says how many they have been through, which is the number
-- that tells you a clone went wrong.
-- ---------------------------------------------------------------------------
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
  p.language                              as persona_language,
  -- appended 2026-09-15 ---------------------------------------------------
  -- An anonymous row is somebody in the middle of onboarding right now, not
  -- a user — it has no email because it has no account yet, which is a
  -- different fact from an Apple sign-in that carried no email claim.
  coalesce(au.is_anonymous, false)        as is_anonymous,
  v.elevenlabs_voice_id                   as voice_id,
  v.name                                  as voice_name,
  v.is_active                             as voice_is_active,
  v.created_at                            as voice_cloned_at,
  -- Null = we do not hold their recording: every clone made before
  -- 20260914120000, every remixed (accent) voice, and anything the one-day
  -- purge has already collected.
  v.original_saved_at                     as voice_original_saved_at,
  v.original_path                         as voice_original_path,
  vc.takes                                as voice_takes
from auth.users au
left join lateral (
  select pp.display_name, pp.location, pp.language
  from public.public_personas pp
  where pp.owner_user_id = au.id and pp.is_active
  order by pp.updated_at desc
  limit 1
) p on true
left join public.user_subscriptions s on s.user_id = au.id
left join lateral (
  select c.elevenlabs_voice_id, c.name, c.is_active, c.created_at,
         c.original_saved_at, c.original_path
  from public.voice_clones c
  where c.user_id = au.id
  order by c.is_active desc, c.created_at desc
  limit 1
) v on true
left join lateral (
  select count(*)::int as takes
  from public.voice_clones c where c.user_id = au.id
) vc on true;

revoke all on public.user_directory from anon, authenticated;
