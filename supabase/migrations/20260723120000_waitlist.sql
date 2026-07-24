-- Waitlist / beta-tester signups collected on the coming-soon landing page.
--
-- Anonymous visitors may only INSERT (join). There is no SELECT/UPDATE/DELETE
-- policy for anon, so the collected emails are never publicly readable — only
-- the service_role key (Edge Functions) or the dashboard can read them.

create table if not exists public.waitlist (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  wants_beta  boolean not null default false,   -- opted in as a beta tester
  source      text,                             -- e.g. 'coming_soon'
  referrer    text,
  user_agent  text,
  invited_at  timestamptz,                      -- set when you invite them to TestFlight
  notified_at timestamptz,                      -- set when you email them at launch
  created_at  timestamptz not null default now()
);

-- One row per email (case-insensitive).
create unique index if not exists waitlist_email_lower_idx
  on public.waitlist (lower(email));

alter table public.waitlist enable row level security;

drop policy if exists "anon can join waitlist" on public.waitlist;
create policy "anon can join waitlist"
  on public.waitlist
  for insert
  to anon, authenticated
  with check (true);

grant insert on public.waitlist to anon, authenticated;
