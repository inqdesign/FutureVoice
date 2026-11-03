-- ---------------------------------------------------------------------------
-- The free minutes come in two halves (2026-11-03, founder decision).
--
-- A new account still starts with `billing_config.free_talk_seconds` (20 min).
-- When that is spent, the trial report's last card offers "recharge 20 min
-- free" beside "subscribe": one tap, once per account, and the learner talks
-- on; the second wall meets the plans with no report. The founder's framing:
-- the trial continues, without a store trial. The store's 3-day intro offer
-- is deleted alongside (`scripts/billing-switch.py trial off`): of every
-- trial-eligible purchase attempt since 10-22, all were cancelled at Apple's
-- own sheet, and the two purchases were made by accounts with no trial.
--
--   free_recharge_seconds   what the one recharge gives. 0 = no recharge:
--                           the apps draw no button (they ask the server,
--                           never a build constant). Changed by
--                           `scripts/billing-switch.py recharge N`.
--
-- `free_recharge_offer()` says whether THIS account may take it, and why not
-- otherwise; `claim_free_recharge()` grants it through `grant_credits` under
-- the key `free_recharge:<user>`, so a second tap — or a second device —
-- returns the same answer and grants nothing. Who may: a signed-up account
-- that never had a subscription row (a lapsed subscriber's empty pool is not
-- a trial), not `unlimited`, with its pool SPENT (under the 60 s floor
-- `consume_metered_seconds` closes a call at) — "once the 20 minutes are
-- used", literally, so a learner who finds the RPC early gains nothing.
-- ---------------------------------------------------------------------------

-- `billing_config` itself (20261021120000_billing_config) never reached
-- production: three files share that version and the one recorded was
-- another of them, so this file carries the table too, statement for
-- statement, idempotent. The signup grant it installs reads the row and
-- falls back to the constant it replaces (1200), so nothing changes for a
-- new account until the row is edited.

create table if not exists public.billing_config (
  id                boolean primary key default true check (id),
  free_talk_seconds integer not null default 1200
                    check (free_talk_seconds between 0 and 36000),
  trial_offer_at    text not null default 'after_free'
                    check (trial_offer_at in ('after_free', 'onboarding')),
  updated_at        timestamptz not null default now()
);

insert into public.billing_config (id) values (true) on conflict (id) do nothing;

alter table public.billing_config enable row level security;

drop policy if exists billing_config_read on public.billing_config;
create policy billing_config_read on public.billing_config
  for select to anon, authenticated using (true);

grant select on public.billing_config to anon, authenticated;

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
declare
  free_talk_seconds integer;
begin
  select c.free_talk_seconds into free_talk_seconds
    from public.billing_config c where c.id;
  free_talk_seconds := coalesce(free_talk_seconds, 1200);

  insert into public.user_credits (user_id, balance, updated_at)
  values (new.id, free_talk_seconds, now())
  on conflict (user_id) do nothing;
  return new;
end;
$$;

alter table public.billing_config
  add column if not exists free_recharge_seconds integer not null default 1200
    check (free_recharge_seconds between 0 and 36000);

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

-- What the report's last card draws: `available` + `seconds`. `reason` is for
-- the console and a debug build, never shown to a learner.
create or replace function public.free_recharge_offer()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_seconds integer;
  v_reason  text;
begin
  select coalesce(c.free_recharge_seconds, 0) into v_seconds from billing_config c where c.id;
  v_reason := public.free_recharge_reason(v_uid);
  return jsonb_build_object('seconds', coalesce(v_seconds, 0),
                            'available', v_reason is null,
                            'reason', v_reason);
end;
$$;

create or replace function public.claim_free_recharge()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_seconds integer;
  v_reason  text;
  v_balance integer;
begin
  select coalesce(c.free_recharge_seconds, 0) into v_seconds from billing_config c where c.id;
  v_reason := public.free_recharge_reason(v_uid);
  if v_reason is not null then
    select balance into v_balance from user_credits where user_id = v_uid;
    return jsonb_build_object('applied', false, 'reason', v_reason,
                              'seconds', coalesce(v_seconds, 0),
                              'balance', coalesce(v_balance, 0));
  end if;
  v_balance := public.grant_credits(
    v_uid, v_seconds, 'grant'::public.ledger_kind,
    'free_recharge', 'claim_free_recharge',
    'free_recharge:' || v_uid::text,
    jsonb_build_object('reason', 'free recharge after the free minutes',
                       'migration', '20261103150000'));
  return jsonb_build_object('applied', true, 'reason', null,
                            'seconds', v_seconds, 'balance', v_balance);
end;
$$;

revoke all on function public.free_recharge_offer() from public, anon;
revoke all on function public.claim_free_recharge() from public, anon;
grant execute on function public.free_recharge_offer() to authenticated, service_role;
grant execute on function public.claim_free_recharge() to authenticated, service_role;
