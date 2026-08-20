-- Operational alerts the OWNER has to hear about while people are using the
-- app, with a dedupe window so one incident pings once instead of once per
-- affected user.
--
-- First user: the ElevenLabs custom-voice ceiling. When the account is out of
-- voice slots, EVERY new user's clone fails at the one step that makes the
-- product theirs — and the only fix is a plan upgrade, which can only happen
-- if the owner learns about it within minutes. The app itself just asks the
-- user to wait (VoiceCapacitySheet); this table is the other half.

create table if not exists public.ops_alerts (
  kind          text not null,          -- 'voice_capacity' | …
  window_key    text not null,          -- dedupe bucket, e.g. '2026-08-20T14' (UTC hour)
  hit_count     integer not null default 0,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  detail        jsonb,                  -- last occurrence's context (user, status, upstream body)
  primary key (kind, window_key)
);
create index if not exists ops_alerts_last_seen_idx on public.ops_alerts(last_seen_at desc);

-- Service-role only: no client ever reads or writes this.
alter table public.ops_alerts enable row level security;

-- Atomic "count this hit, and tell me how many there have been in this
-- window". The count is what makes the alert actionable — one unlucky user
-- and forty blocked signups need different reactions from the owner — and
-- doing it in one statement keeps two concurrent failures from both
-- believing they were the first.
create or replace function public.record_ops_alert(
  p_kind       text,
  p_window_key text,
  p_detail     jsonb default null
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  insert into ops_alerts as a (kind, window_key, hit_count, detail)
  values (p_kind, p_window_key, 1, p_detail)
  on conflict (kind, window_key) do update
    set hit_count    = a.hit_count + 1,
        last_seen_at = now(),
        detail       = coalesce(excluded.detail, a.detail)
  returning a.hit_count into v_count;
  return v_count;
end;
$$;

-- Edge Functions call this with the service-role key; nobody else may.
-- (Postgres grants EXECUTE to PUBLIC by default, so revoking from anon +
-- authenticated alone would leave the door open.)
revoke all on function public.record_ops_alert(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.record_ops_alert(text, text, jsonb) to service_role;

-- Owner queries (Supabase dashboard → SQL editor):
--   select * from ops_alerts order by last_seen_at desc;
--   select sum(hit_count) from ops_alerts
--    where kind = 'voice_capacity' and last_seen_at > now() - interval '1 day';
