-- ---------------------------------------------------------------------------
-- "Do we hold this person's recording" is a question about the PERSON.
--
-- 20260915090000 read the original columns off the same row as the voice —
-- the ACTIVE clone — and that row is the wrong one to ask. Picking an accent
-- mints a REMIXED voice, which has no recording of its own: it was generated
-- from a clone, not read aloud. So the two learners whose takes we actually
-- hold in the bucket right now both read "—" in the column built to tell us
-- that, because each had gone on to pick an accent.
--
-- The voice columns still describe the voice in USE. The original columns now
-- describe the person: the most recent clone of theirs that has a recording
-- on file, whichever voice it built.
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
  coalesce(au.is_anonymous, false)        as is_anonymous,
  v.elevenlabs_voice_id                   as voice_id,
  v.name                                  as voice_name,
  v.is_active                             as voice_is_active,
  v.created_at                            as voice_cloned_at,
  -- Per PERSON, not per active voice. Null = no recording of theirs on file:
  -- every clone made before 20260914120000, and anything the one-day purge
  -- has already collected.
  o.original_saved_at                     as voice_original_saved_at,
  o.original_path                         as voice_original_path,
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
  select c.elevenlabs_voice_id, c.name, c.is_active, c.created_at
  from public.voice_clones c
  where c.user_id = au.id
  order by c.is_active desc, c.created_at desc
  limit 1
) v on true
left join lateral (
  select c.original_saved_at, c.original_path
  from public.voice_clones c
  where c.user_id = au.id and c.original_path is not null
  order by c.original_saved_at desc nulls last
  limit 1
) o on true
left join lateral (
  select count(*)::int as takes
  from public.voice_clones c where c.user_id = au.id
) vc on true;

revoke all on public.user_directory from anon, authenticated;
