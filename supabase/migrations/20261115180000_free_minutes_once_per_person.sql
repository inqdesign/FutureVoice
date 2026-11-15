-- ---------------------------------------------------------------------------
-- The free minutes are once per PERSON, not once per account
-- (2026-11-15, founder decision).
--
-- Seen that day: one learner in Veracruz deleted their account from the app
-- and signed up six more times in half an hour from one IP and one Android
-- app: new Gmail addresses, then the deleted one again. Every signup is a new
-- auth.users row, and the free pool (`billing_config.free_talk_seconds`) and
-- the one recharge (`free_recharge:<user>`) are keyed by user id.
--
-- Two witnesses now, either one enough:
--
--   EMAIL   a deletion leaves a SHA-256 of the normalized email and nothing
--           else (`deleted_signup_emails`, no user id). That email arriving
--           again, at signup or when an anonymous onboarding session is
--           linked (the email comes on an UPDATE there), withholds.
--   DEVICE  a build that knows how (Android 1.3.6+) calls
--           `report_signup_device(hash)` once an account owns the session,
--           with a hash of the device's own id (ANDROID_ID, which survives a
--           reinstall). The first account on a device keeps its minutes; a
--           NEW account (under a day old) on a device another account has
--           already used withholds. A build that sends nothing is unchanged.
--
-- Withholding = the signup grant taken off the balance (never below 0,
-- nothing else in the balance touched) and `free_recharge_reason` answering
-- 'returning'. Once per account (`free_grant_withheld`), so both witnesses
-- together still take it once. The account works otherwise: subscribe,
-- codes and invites as usual. Unlimited (admin) rows and accounts with a
-- subscription row are never touched.
--
-- Not covered: a factory reset, a second phone, or a build older than the
-- one that reports.
-- ---------------------------------------------------------------------------

create table if not exists public.deleted_signup_emails (
  email_hash  text primary key,
  deleted_at  timestamptz not null default now()
);

create table if not exists public.signup_devices (
  device_hash    text primary key,
  first_user_id  uuid not null,        -- no FK: must outlive the account
  first_seen_at  timestamptz not null default now(),
  last_user_id   uuid,
  last_seen_at   timestamptz,
  accounts       integer not null default 1
);

create table if not exists public.free_grant_withheld (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  reason      text not null check (reason in ('email', 'device')),
  seconds     integer not null,
  created_at  timestamptz not null default now()
);

alter table public.deleted_signup_emails enable row level security;
alter table public.signup_devices        enable row level security;
alter table public.free_grant_withheld   enable row level security;
revoke all on public.deleted_signup_emails from public, anon, authenticated;
revoke all on public.signup_devices        from public, anon, authenticated;
revoke all on public.free_grant_withheld   from public, anon, authenticated;

create or replace function public.signup_email_hash(p_email text)
returns text
language plpgsql
immutable
as $$
declare
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_local  text;
  v_domain text;
begin
  if v_email = '' or position('@' in v_email) = 0 then return null; end if;
  v_local  := split_part(v_email, '@', 1);
  v_domain := split_part(v_email, '@', 2);
  -- Gmail ignores dots and anything after '+'.
  if v_domain in ('gmail.com', 'googlemail.com') then
    v_local  := replace(split_part(v_local, '+', 1), '.', '');
    v_domain := 'gmail.com';
  end if;
  return encode(extensions.digest(v_local || '@' || v_domain, 'sha256'), 'hex');
end;
$$;

revoke all on function public.signup_email_hash(text) from public, anon, authenticated;

-- The one place a grant is taken back. Returns whether it acted.
create or replace function public.withhold_signup_grant(p_user_id uuid, p_reason text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_grant integer;
begin
  if p_user_id is null then return false; end if;
  if exists (select 1 from free_grant_withheld w where w.user_id = p_user_id) then return false; end if;
  if exists (select 1 from user_credits c where c.user_id = p_user_id and coalesce(c.unlimited, false)) then
    return false;
  end if;
  if exists (select 1 from user_subscriptions s where s.user_id = p_user_id) then return false; end if;

  select coalesce(c.free_talk_seconds, 1200) into v_grant from billing_config c where c.id;
  v_grant := coalesce(v_grant, 1200);

  insert into free_grant_withheld (user_id, reason, seconds)
  values (p_user_id, p_reason, v_grant)
  on conflict (user_id) do nothing;
  if not found then return false; end if;

  update user_credits c
     set balance = greatest(c.balance - v_grant, 0),
         updated_at = now()
   where c.user_id = p_user_id;
  return true;
end;
$$;

revoke all on function public.withhold_signup_grant(uuid, text) from public, anon, authenticated;

-- EMAIL 1) a deletion remembers the email (hash only).
create or replace function public.remember_deleted_signup_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text := public.signup_email_hash(old.email);
begin
  if v_hash is not null then
    insert into public.deleted_signup_emails (email_hash)
    values (v_hash)
    on conflict (email_hash) do update set deleted_at = now();
  end if;
  return old;
end;
$$;

drop trigger if exists on_auth_user_deleted_remember_email on auth.users;
create trigger on_auth_user_deleted_remember_email
  before delete on auth.users
  for each row execute function public.remember_deleted_signup_email();

-- EMAIL 2) that email on a new account withholds. AFTER the credits trigger
-- on insert (triggers fire in name order: on_auth_user_created_credits <
-- on_auth_user_email_returning), and on the update that links an anonymous
-- session to a real identity.
create or replace function public.withhold_grant_from_returning_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text := public.signup_email_hash(new.email);
begin
  if v_hash is null then return new; end if;
  if tg_op = 'UPDATE' and public.signup_email_hash(old.email) is not distinct from v_hash then
    return new;
  end if;
  if exists (select 1 from public.deleted_signup_emails d where d.email_hash = v_hash) then
    perform public.withhold_signup_grant(new.id, 'email');
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_returning on auth.users;
create trigger on_auth_user_email_returning
  after insert on auth.users
  for each row execute function public.withhold_grant_from_returning_email();

drop trigger if exists on_auth_user_email_returning_linked on auth.users;
create trigger on_auth_user_email_returning_linked
  after update of email on auth.users
  for each row execute function public.withhold_grant_from_returning_email();

-- DEVICE) called by the app once an account owns the session. The app sends
-- a SHA-256 of its device id; it is hashed again here so the stored value is
-- not the one any client sends. Answers {status}: 'first' (this account owns
-- the device's free minutes), 'known' (seen before for this account),
-- 'returning' (another account had them; this one's were withheld if new),
-- 'skipped' (anonymous, or nothing usable sent).
create or replace function public.report_signup_device(p_device text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_hash     text;
  v_first    uuid;
  v_created  timestamptz;
  v_anon     boolean;
  v_withheld boolean := false;
begin
  if v_uid is null or p_device is null or length(btrim(p_device)) < 16 or length(p_device) > 128 then
    return jsonb_build_object('status', 'skipped');
  end if;
  select coalesce(u.is_anonymous, false), u.created_at into v_anon, v_created
    from auth.users u where u.id = v_uid;
  -- An anonymous onboarding session is swept 30 minutes later if never
  -- linked; letting it claim the device would cost the real signup after it.
  if coalesce(v_anon, true) then return jsonb_build_object('status', 'skipped'); end if;

  v_hash := encode(extensions.digest('nawana-signup-device-v1:' || btrim(p_device), 'sha256'), 'hex');

  insert into signup_devices (device_hash, first_user_id)
  values (v_hash, v_uid)
  on conflict (device_hash) do nothing;
  if found then return jsonb_build_object('status', 'first'); end if;

  select d.first_user_id into v_first from signup_devices d where d.device_hash = v_hash;
  if v_first = v_uid then return jsonb_build_object('status', 'known'); end if;

  update signup_devices d
     set last_user_id = v_uid,
         last_seen_at = now(),
         accounts = d.accounts + case when d.last_user_id is distinct from v_uid then 1 else 0 end
   where d.device_hash = v_hash;

  -- Only a NEW account loses its minutes: an account from before this
  -- existed, reporting for the first time on a shared family phone, keeps
  -- what it has.
  if v_created > now() - interval '1 day' then
    v_withheld := public.withhold_signup_grant(v_uid, 'device');
  end if;
  return jsonb_build_object('status', 'returning', 'withheld', v_withheld);
end;
$$;

revoke all on function public.report_signup_device(text) from public, anon;
grant execute on function public.report_signup_device(text) to authenticated;

-- No recharge for a withheld account either (same body as 20261103150000,
-- plus the 'returning' answer).
create or replace function public.free_recharge_reason(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seconds    integer;
  v_balance    integer;
  v_unlimited  boolean;
  v_anonymous  boolean;
begin
  if p_user_id is null then return 'signed_out'; end if;
  select c.free_recharge_seconds into v_seconds from billing_config c where c.id;
  if coalesce(v_seconds, 0) = 0 then return 'off'; end if;
  if exists (select 1 from usage_ledger
              where idempotency_key = 'free_recharge:' || p_user_id::text) then
    return 'claimed';
  end if;
  select coalesce(u.is_anonymous, false) into v_anonymous from auth.users u where u.id = p_user_id;
  if coalesce(v_anonymous, true) then return 'anonymous'; end if;
  if exists (select 1 from free_grant_withheld w where w.user_id = p_user_id) then
    return 'returning';
  end if;
  select c.balance, coalesce(c.unlimited, false) into v_balance, v_unlimited
    from user_credits c where c.user_id = p_user_id;
  if coalesce(v_unlimited, false) then return 'unlimited'; end if;
  if exists (select 1 from user_subscriptions s where s.user_id = p_user_id) then
    return 'subscribed';
  end if;
  if coalesce(v_balance, 0) >= 60 then return 'not_spent'; end if;
  return null;
end;
$$;

revoke all on function public.free_recharge_reason(uuid) from public, anon, authenticated;
