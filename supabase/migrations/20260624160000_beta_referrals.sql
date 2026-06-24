-- Public-beta referral / invite-to-earn-credits.
--
-- No real billing during beta. Every new user gets a fixed free quota, and
-- can EARN more by inviting people. Both inviter and invitee get +500 credits
-- per successful invite; the inviter is rewarded for up to 10 invites.
-- All grants flow through the existing credit system (grant_credits), so they
-- show up in usage_ledger and the Me-tab balance like any other credit.

-- ---------------------------------------------------------------------------
-- A) Lower the per-signup free quota from 1000 → 500 for the public beta.
--    Existing accounts keep whatever they already have (idempotency key is
--    unchanged, so this never re-grants).
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
begin
  perform public.grant_credits(
    p_user_id => new.id,
    p_credits => 500,
    p_kind => 'grant',
    p_action => 'beta_bootstrap',
    p_source_fn => 'auth_trigger',
    p_idempotency_key => 'bootstrap:' || new.id::text,
    p_metadata => jsonb_build_object('reason', 'public beta starting quota')
  );
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- B) Each user's shareable invite code.
-- ---------------------------------------------------------------------------
create table if not exists public.referral_codes (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  code       text not null unique,
  created_at timestamptz not null default now()
);

alter table public.referral_codes enable row level security;

drop policy if exists "referral_codes: owner read" on public.referral_codes;
create policy "referral_codes: owner read" on public.referral_codes
  for select using (auth.uid() = user_id);

-- 6-char code from an unambiguous alphabet (no 0/O/1/I). Retries on collision.
create or replace function public.gen_referral_code()
returns text
language plpgsql
as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  i int;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.referral_codes where code = v_code);
  end loop;
  return v_code;
end;
$$;

create or replace function public.handle_new_user_referral()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.referral_codes(user_id, code)
  values (new.id, public.gen_referral_code())
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_referral on auth.users;
create trigger on_auth_user_created_referral
  after insert on auth.users
  for each row execute function public.handle_new_user_referral();

-- Backfill existing users (loop so each generated code sees prior inserts).
do $$
declare u record;
begin
  for u in
    select id from auth.users
    where id not in (select user_id from public.referral_codes)
  loop
    insert into public.referral_codes(user_id, code)
    values (u.id, public.gen_referral_code())
    on conflict (user_id) do nothing;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- C) Redemptions — one per new user (invitee_id is the primary key).
-- ---------------------------------------------------------------------------
create table if not exists public.referral_redemptions (
  invitee_id uuid primary key references auth.users(id) on delete cascade,
  inviter_id uuid not null references auth.users(id) on delete cascade,
  code       text not null,
  created_at timestamptz not null default now()
);
create index if not exists referral_redemptions_inviter_idx
  on public.referral_redemptions(inviter_id);

alter table public.referral_redemptions enable row level security;

drop policy if exists "referral_redemptions: participant read" on public.referral_redemptions;
create policy "referral_redemptions: participant read" on public.referral_redemptions
  for select using (auth.uid() = inviter_id or auth.uid() = invitee_id);

-- ---------------------------------------------------------------------------
-- D) Redeem an invite code (called by the invitee). SECURITY DEFINER so it can
--    grant credits; all guards live inside.
-- ---------------------------------------------------------------------------
create or replace function public.redeem_referral(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitee uuid := auth.uid();
  v_inviter uuid;
  v_code text := upper(trim(p_code));
  v_invite_count int;
  v_balance int;
  v_inviter_rewarded boolean := false;
begin
  if v_invitee is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if v_code is null or length(v_code) = 0 then raise exception 'INVALID_CODE'; end if;

  select user_id into v_inviter from referral_codes where code = v_code;
  if v_inviter is null then raise exception 'INVALID_CODE'; end if;
  if v_inviter = v_invitee then raise exception 'SELF_REFERRAL'; end if;
  if exists (select 1 from referral_redemptions where invitee_id = v_invitee) then
    raise exception 'ALREADY_REDEEMED';
  end if;

  insert into referral_redemptions(invitee_id, inviter_id, code)
  values (v_invitee, v_inviter, v_code);

  -- Invitee bonus (one-time).
  v_balance := public.grant_credits(
    p_user_id => v_invitee, p_credits => 500, p_kind => 'grant',
    p_action => 'referral_invitee', p_source_fn => 'redeem_referral',
    p_idempotency_key => 'ref_invitee:' || v_invitee::text,
    p_metadata => jsonb_build_object('code', v_code, 'inviter', v_inviter)
  );

  -- Inviter bonus, capped at the first 10 successful invites.
  select count(*) into v_invite_count
    from referral_redemptions where inviter_id = v_inviter;
  if v_invite_count <= 10 then
    perform public.grant_credits(
      p_user_id => v_inviter, p_credits => 500, p_kind => 'grant',
      p_action => 'referral_inviter', p_source_fn => 'redeem_referral',
      p_idempotency_key => 'ref_inviter:' || v_invitee::text,
      p_metadata => jsonb_build_object('code', v_code, 'invitee', v_invitee)
    );
    v_inviter_rewarded := true;
  end if;

  return jsonb_build_object(
    'balance', v_balance,
    'invitee_bonus', 500,
    'inviter_rewarded', v_inviter_rewarded
  );
end;
$$;

revoke all on function public.redeem_referral(text) from public;
grant execute on function public.redeem_referral(text) to authenticated;

-- ---------------------------------------------------------------------------
-- E) Hardening: clients must NOT be able to mint/charge credits directly.
--    Edge Functions use the service_role key (bypasses these grants), and
--    redeem_referral runs as its owner, so both keep working.
-- ---------------------------------------------------------------------------
revoke all on function public.grant_credits(uuid, integer, public.ledger_kind, text, text, text, jsonb) from public;
revoke all on function public.charge_credits(uuid, integer, text, text, text, jsonb) from public;
