-- Client-side error breadcrumbs (Talk network failures first). The app has no
-- analytics SDK; this table is the minimal observability channel so we can
-- see WHICH leg fails (gemini upload vs TTS stream), with what error, on what
-- network — and verify the cellular fixes actually move the numbers.
--
-- Write-only for clients; reading is dashboard/service-role work.

create table if not exists public.client_events (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  event       text not null,            -- e.g. 'talk_turn_error', 'talk_audio_rescue'
  properties  jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists client_events_event_created_idx
  on public.client_events(event, created_at desc);

alter table public.client_events enable row level security;
drop policy if exists "client_events: owner insert" on public.client_events;
create policy "client_events: owner insert" on public.client_events
  for insert with check (auth.uid() = user_id);
-- Deliberately no select policy: clients write breadcrumbs, never read them.
