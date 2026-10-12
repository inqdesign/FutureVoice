-- A Cartesia voice has no change limit (2026-10-12).
--
-- One voice change per 30 days (20261009090000_voice_changes) exists to save
-- ElevenLabs' monthly voice allowance and its 160 slots. A Cartesia clone
-- spends neither — Cartesia keeps instant clones without a limit, and an
-- accent pick on it creates nothing (supabase/functions/_shared/cartesia.ts).
-- Found on the first Cartesia signup: a re-record during onboarding counted as
-- the month's change, and every accent pill went grey.
--
-- Cartesia voice ids are UUIDs, optionally carrying an accent ("<uuid>:british").
-- Same signature, so this replaces the function rather than overloading it.

create or replace function public.voice_change_status(p_user_id uuid default auth.uid())
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  with recent as (
    select created_at from public.voice_changes
    where user_id = p_user_id and kind = 'change'
      and created_at > now() - interval '30 days'
  ),
  on_cartesia as (
    select exists (
      select 1 from public.voice_clones
      where user_id = p_user_id and is_active
        and elevenlabs_voice_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(:[a-z-]+)?$'
    ) as yes
  )
  select case when (select yes from on_cartesia)
    then jsonb_build_object('left', 1, 'next_at', null)
    else jsonb_build_object(
      'left', greatest(0, 1 - (select count(*) from recent)),
      'next_at', case when (select count(*) from recent) >= 1
                      then (select min(created_at) from recent) + interval '30 days' end
    )
  end
  where p_user_id = auth.uid() or auth.role() = 'service_role';
$$;
