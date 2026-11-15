-- ---------------------------------------------------------------------------
-- A deleted account's email does not get the free minutes again
-- (2026-11-15, founder decision).
--
-- Seen that day: one learner in Veracruz deleted their account from the app,
-- signed up with two other Gmail addresses and then with the deleted one
-- again, all from one IP within half an hour. Every signup is a new
-- auth.users row, and the free pool (`billing_config.free_talk_seconds`) and
-- the one recharge (`free_recharge:<user>`) are keyed by user id, which the
-- deletion erased together with any record that the email had had them.
--
-- So a deletion now leaves ONE thing behind: a SHA-256 of the normalized
-- email, with no user id and nothing else (`deleted_signup_emails`). An
-- account that gets that email again, at signup or when an anonymous
-- onboarding session is linked to Google/Apple (the email arrives on an
-- UPDATE there, after the grant was already made), loses the signup grant,
-- and `free_recharge_reason` answers 'returning'. Nothing else about the
-- account changes: it can subscribe, redeem codes and invites as usual.
--
-- Not covered, on purpose: a NEW Gmail address on the same phone. That
-- needs a device id from the apps.
--
-- Gmail ignores dots and anything after '+', so those are folded for
-- gmail.com / googlemail.com; Apple relay addresses are stable per app and
-- need nothing.
-- ---------------------------------------------------------------------------

create table if not exists public.deleted_signup_emails (
  email_hash  text primary key,
  deleted_at  timestamptz not null default now()
);

alter table public.deleted_signup_emails enable row level security;
revoke all on public.deleted_signup_emails from public, anon, authenticated;

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
  if v_domain in ('gmail.com', 'googlemail.com') then
    v_local  := replace(split_part(v_local, '+', 1), '.', '');
    v_domain := 'gmail.com';
  end if;
  return encode(extensions.digest(v_local || '@' || v_domain, 'sha256'), 'hex');
end;
$$;

revoke all on function public.signup_email_hash(text) from public, anon, authenticated;

-- 1) A deletion remembers the email (hash only).
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

-- 2) That email arriving on a new account takes the signup grant back.
--    AFTER the credits trigger on insert (names sort: on_auth_user_created_credits
--    < on_auth_user_email_returning), and on the update that links an
--    anonymous session to a real identity.
create or replace function public.withhold_grant_from_returning_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash  text := public.signup_email_hash(new.email);
  v_grant integer;
begin
  if v_hash is null then return new; end if;
  if tg_op = 'UPDATE' and public.signup_email_hash(old.email) is not distinct from v_hash then
    return new;
  end if;
  if not exists (select 1 from public.deleted_signup_emails d where d.email_hash = v_hash) then
    return new;
  end if;

  select coalesce(c.free_talk_seconds, 1200) into v_grant from public.billing_config c where c.id;
  v_grant := coalesce(v_grant, 1200);

  -- Only the signup grant goes: whatever else is in the balance (an invite,
  -- a code) stays. Unlimited (admin) rows are never touched.
  update public.user_credits c
     set balance = greatest(c.balance - v_grant, 0),
         updated_at = now()
   where c.user_id = new.id
     and not coalesce(c.unlimited, false);
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

-- 3) No recharge for a returning email either (same body as
--    20261103150000, plus the 'returning' answer).
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
  v_email      text;
begin
  if p_user_id is null then return 'signed_out'; end if;
  select c.free_recharge_seconds into v_seconds from billing_config c where c.id;
  if coalesce(v_seconds, 0) = 0 then return 'off'; end if;
  if exists (select 1 from usage_ledger
              where idempotency_key = 'free_recharge:' || p_user_id::text) then
    return 'claimed';
  end if;
  select coalesce(u.is_anonymous, false), u.email into v_anonymous, v_email
    from auth.users u where u.id = p_user_id;
  if coalesce(v_anonymous, true) then return 'anonymous'; end if;
  if exists (select 1 from deleted_signup_emails d
              where d.email_hash = public.signup_email_hash(v_email)) then
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
