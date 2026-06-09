-- FutureVoice initial schema.
-- Phase 1 sync scope: only what hurts to lose on reinstall/device change.
-- voice_clones is the critical one — without it the user re-records on every
-- new device. personas is small but tied to language-pair config. Everything
-- else (counterparts, scenarios, dialogues, attempts, drill cards) stays
-- local-only for the first TestFlight; we'll add tables here if/when we
-- discover users want cross-device for those too.

-- 1) profiles — 1:1 with auth.users, holds language config.
-- We do NOT mirror auth fields (email, name) here; the iOS app reads those
-- from the Apple Sign-In response directly. This table is only for app config.
create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  native_language text not null default 'ko',
  target_language text not null default 'en',
  proficiency     text not null default 'b1',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 2) voice_clones — ElevenLabs voice_id mapping per user.
-- Most users only ever have one active clone, but we model it as a list so
-- re-record onboarding can stage a new one alongside the old one before
-- the old one is deleted from ElevenLabs (mirrors the pendingDelete pattern
-- already in AppState.swift).
create table public.voice_clones (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  elevenlabs_voice_id text not null,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now()
);
create index voice_clones_user_id_idx on public.voice_clones(user_id);
-- One active clone per user — enforces "switching to new clone deactivates old".
create unique index voice_clones_user_active_idx
  on public.voice_clones(user_id)
  where is_active;

-- 3) personas — JSONB blob mirroring UserPersona in Models.swift.
-- Stored as JSON so the iOS-side struct can evolve freely without migrations
-- for every added field. Schema-on-read; the iOS decoder is the source of truth.
create table public.personas (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  payload    jsonb not null,
  updated_at timestamptz not null default now()
);

-- updated_at triggers
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger personas_updated_at
  before update on public.personas
  for each row execute function public.set_updated_at();

-- RLS — each user can only see/modify their own row.
alter table public.profiles     enable row level security;
alter table public.voice_clones enable row level security;
alter table public.personas     enable row level security;

create policy "profiles: owner read"    on public.profiles
  for select using (auth.uid() = id);
create policy "profiles: owner write"   on public.profiles
  for all    using (auth.uid() = id) with check (auth.uid() = id);

create policy "voice_clones: owner read"  on public.voice_clones
  for select using (auth.uid() = user_id);
create policy "voice_clones: owner write" on public.voice_clones
  for all    using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "personas: owner read"  on public.personas
  for select using (auth.uid() = user_id);
create policy "personas: owner write" on public.personas
  for all    using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Auto-create a profile row on signup. Apple Sign-In hits auth.users directly,
-- so without this trigger the iOS app would have to do a separate insert
-- on first launch (more round-trips, more error paths).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
