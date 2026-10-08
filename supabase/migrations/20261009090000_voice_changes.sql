-- One voice CHANGE per 30 days (2026-10-09, founder decision).
--
-- ElevenLabs counts every voice added to the account against a monthly
-- allowance (Pro 290) and deleting gives nothing back — on 2026-10-08 the
-- account stood at 274/290 three days before the reset, half of it spent by
-- a few learners re-recording and trying accent after accent. So after a
-- learner's first voice, one change per rolling 30 days: a re-record, a saved
-- accent, or "no accent" (a rebuild). Listening to accent takes is free (a
-- preview adds no voice — measured the same day) and is never counted.
--
-- The edge functions write a row per voice actually made, and ask
-- `voice_change_status` before making one:
--   first    a learner's first clone ever
--   default  the remix the app makes right after a clone (the accent picked
--            in setup) — part of the clone it follows, not a change
--   revival  a parked voice rebuilt (park-idle-voices took it; not theirs)
--   change   everything else — the one that is counted
-- History starts now: nobody has used their change on the day this lands.

create table if not exists public.voice_changes (
  id         bigserial primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  kind       text not null check (kind in ('first', 'default', 'revival', 'change')),
  created_at timestamptz not null default now()
);
create index if not exists voice_changes_user_at on public.voice_changes (user_id, created_at desc);

alter table public.voice_changes enable row level security;
drop policy if exists "own voice changes" on public.voice_changes;
create policy "own voice changes" on public.voice_changes
  for select using (auth.uid() = user_id);

-- { left: changes still allowed now, next_at: when one comes back (null if
-- one is available) }. Callable by the learner for themselves (the app draws
-- the pills from it) and by the service role for anyone.
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
  )
  select jsonb_build_object(
    'left', greatest(0, 1 - (select count(*) from recent)),
    'next_at', case when (select count(*) from recent) >= 1
                    then (select min(created_at) from recent) + interval '30 days' end
  )
  where p_user_id = auth.uid() or auth.role() = 'service_role';
$$;
revoke all on function public.voice_change_status(uuid) from public;
grant execute on function public.voice_change_status(uuid) to authenticated, service_role;
