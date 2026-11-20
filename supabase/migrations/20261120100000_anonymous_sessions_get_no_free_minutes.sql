-- ---------------------------------------------------------------------------
-- An anonymous session holds no free minutes; they arrive with the account
-- (2026-11-20).
--
-- Seen that morning: a script in Jammu, India (Python websockets, then a
-- browser and okhttp) signed up anonymous users with the public anon key —
-- 21 in 25 minutes, 11 of them in one second — and opened gateway calls on
-- each one's 1200 free seconds. Every new auth.users row got the signup
-- grant, anonymous or not, so each request was a fresh 20 minutes.
--
-- The gateway refuses anonymous sessions since the same day (verifyUser).
-- This closes the balance side: the apps only use an anonymous session to
-- clone and hear the greeting before the sign-up step, and both of those
-- are free entry purposes in `tts` / `voice-clone`, so nothing a real
-- learner does before the account needs the balance.
--
--   INSERT, anonymous   balance 0, and a row in `signup_grant_pending`.
--   UPDATE is_anonymous true → false (Apple/Google/email linked to the
--                        session): the pending grant is paid, once.
--                        Fires before the returning-email withhold
--                        (trigger names sort "on_auth_user_claimed…" <
--                        "on_auth_user_email…"), so a returning email still
--                        takes it back; and a grant already withheld is not
--                        paid at all.
--   INSERT, not anonymous   unchanged (handle_new_user_credits).
--
-- Anonymous users that exist now: those still holding exactly the grant are
-- set to 0 and marked pending, so a learner mid-onboarding gets it on link.
-- ---------------------------------------------------------------------------

create table if not exists public.signup_grant_pending (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

alter table public.signup_grant_pending enable row level security;
revoke all on public.signup_grant_pending from public, anon, authenticated;

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  free_talk_seconds integer;
begin
  if coalesce(new.is_anonymous, false) then
    insert into public.user_credits (user_id, balance, updated_at)
    values (new.id, 0, now())
    on conflict (user_id) do nothing;
    insert into public.signup_grant_pending (user_id)
    values (new.id)
    on conflict (user_id) do nothing;
    return new;
  end if;

  select c.free_talk_seconds into free_talk_seconds
    from public.billing_config c where c.id;
  free_talk_seconds := coalesce(free_talk_seconds, 1200);

  insert into public.user_credits (user_id, balance, updated_at)
  values (new.id, free_talk_seconds, now())
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create or replace function public.pay_signup_grant_on_claim()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_grant integer;
begin
  if not (coalesce(old.is_anonymous, false) and not coalesce(new.is_anonymous, false)) then
    return new;
  end if;
  delete from public.signup_grant_pending p where p.user_id = new.id;
  if not found then return new; end if;
  if exists (select 1 from public.free_grant_withheld w where w.user_id = new.id) then
    return new;
  end if;

  select coalesce(c.free_talk_seconds, 1200) into v_grant from public.billing_config c where c.id;
  v_grant := coalesce(v_grant, 1200);

  insert into public.user_credits (user_id, balance, updated_at)
  values (new.id, v_grant, now())
  on conflict (user_id) do update
    set balance = public.user_credits.balance + v_grant,
        updated_at = now();
  return new;
end;
$$;

revoke all on function public.pay_signup_grant_on_claim() from public, anon, authenticated;

drop trigger if exists on_auth_user_claimed_grant on auth.users;
create trigger on_auth_user_claimed_grant
  after update of is_anonymous on auth.users
  for each row execute function public.pay_signup_grant_on_claim();

-- Anonymous users already on file.
with grant_size as (
  select coalesce((select c.free_talk_seconds from public.billing_config c where c.id), 1200) as s
), anon as (
  select u.id
    from auth.users u
    join public.user_credits c on c.user_id = u.id, grant_size g
   where coalesce(u.is_anonymous, false)
     and not coalesce(c.unlimited, false)
     and c.balance = g.s
), marked as (
  insert into public.signup_grant_pending (user_id)
  select id from anon
  on conflict (user_id) do nothing
  returning user_id
)
update public.user_credits c
   set balance = 0, updated_at = now()
 where c.user_id in (select id from anon);
