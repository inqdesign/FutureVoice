-- Subscription + credit system.
--
-- Design principles:
-- - Credits are the source of truth for "can the user make this call?" — the
--   subscription tier just decides how many credits get granted at each
--   renewal. Edge Functions only care about the balance.
-- - Tier + balance are stored server-side so they can't be tampered with by
--   a jailbroken client. Apple's StoreKit receipt is the entry point for
--   updating them, never iOS UI state.
-- - usage_ledger is append-only for audit + rollback + cost analytics. Every
--   debit gets a row. Idempotency_key prevents double-charging on retry.
--
-- We do NOT model trials as a separate state — Apple's intro_offer handles
-- that. The webhook just grants the same credits as a paid Pro Monthly when
-- trial starts; if user cancels in 3 days, the subscription_status row gets
-- updated to "expired" and the balance becomes irrelevant.

-- 1) Tier definitions. Driven from DB so we can re-tune credits without
--    shipping a new app. Keys match Apple's product IDs (defined separately
--    in App Store Connect — see docs).
create type public.subscription_tier as enum ('pro', 'premium');
create type public.subscription_period as enum ('weekly', 'monthly', 'annual');

create table public.subscription_plans (
  id            text primary key,                 -- e.g. 'pro_monthly'
  tier          public.subscription_tier not null,
  period        public.subscription_period not null,
  credits_per_cycle integer not null,
  apple_product_id text not null unique,          -- e.g. 'com.roro.futurevoice.pro_monthly'
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

insert into public.subscription_plans (id, tier, period, credits_per_cycle, apple_product_id) values
  ('pro_weekly',     'pro',     'weekly',  125,    'com.roro.futurevoice.pro_weekly'),
  ('pro_monthly',    'pro',     'monthly', 500,    'com.roro.futurevoice.pro_monthly'),
  ('pro_annual',     'pro',     'annual',  6500,   'com.roro.futurevoice.pro_annual'),
  ('premium_weekly', 'premium', 'weekly',  375,    'com.roro.futurevoice.premium_weekly'),
  ('premium_monthly','premium', 'monthly', 1500,   'com.roro.futurevoice.premium_monthly'),
  ('premium_annual', 'premium', 'annual',  19500,  'com.roro.futurevoice.premium_annual');

-- 2) Per-user current subscription state. One row per user, upserted by the
--    Apple webhook / subscription-verify Edge Function.
create table public.user_subscriptions (
  user_id                 uuid primary key references auth.users(id) on delete cascade,
  plan_id                 text references public.subscription_plans(id),
  apple_original_tx_id    text,                    -- stable across renewals
  status                  text not null default 'inactive',  -- 'trialing' | 'active' | 'grace' | 'expired' | 'inactive'
  current_period_start    timestamptz,
  current_period_end      timestamptz,
  trial_ends_at           timestamptz,             -- mirrors Apple's intro_offer expiry
  cancel_at_period_end    boolean not null default false,
  updated_at              timestamptz not null default now()
);
create index user_subscriptions_status_idx on public.user_subscriptions(status);

-- 3) Credit balance — separate from subscriptions so credits can be granted
--    by sources other than subscription renewal (top-ups, promo, carryover).
--    `period_start/end` track the current billing cycle for rollover math.
create table public.user_credits (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  balance         integer not null default 0,
  period_start    timestamptz,
  period_end      timestamptz,
  -- How many credits the active plan grants per cycle. Stored here (denormalized
  -- from subscription_plans) so the charge() function doesn't need a join on
  -- the hot path.
  cycle_grant     integer not null default 0,
  updated_at      timestamptz not null default now()
);

-- 4) Append-only usage log. Each debit (and refund / grant) gets a row.
create type public.ledger_kind as enum ('debit', 'grant', 'refund', 'topup', 'carryover');

create table public.usage_ledger (
  id              bigserial primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  kind            public.ledger_kind not null,
  -- Negative for debits, positive for grants/refunds/topups. Sum across a
  -- user should equal user_credits.balance (until we periodically prune).
  delta           integer not null,
  action          text,                            -- 'tts' | 'tts_timestamps' | 'voice_clone' | 'gemini' | 'top_up' | 'cycle_grant'
  source_fn       text,                            -- which Edge Function recorded this
  idempotency_key text unique,                     -- prevents double-charging on retry
  metadata        jsonb,                           -- e.g. { "text_chars": 132, "voice_id": "...", "apple_tx_id": "..." }
  created_at      timestamptz not null default now()
);
create index usage_ledger_user_created_idx on public.usage_ledger(user_id, created_at desc);

-- 5) Atomic charge function. Returns the new balance if the debit succeeded,
--    or raises 'INSUFFICIENT_CREDITS' if balance would go negative.
--    Edge Functions call this BEFORE invoking the upstream provider; if the
--    upstream errors out, they call refund() with the same idempotency key.
create or replace function public.charge_credits(
  p_user_id uuid,
  p_credits integer,           -- positive integer; we debit this much
  p_action text,
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_balance integer;
begin
  if p_credits < 0 then raise exception 'p_credits must be >= 0'; end if;

  -- Idempotency: if the same key has already been recorded, return the
  -- balance unchanged. Lets clients safely retry on transient failures.
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_new_balance from user_credits where user_id = p_user_id;
    return coalesce(v_new_balance, 0);
  end if;

  -- Lock the credit row for the duration of the txn.
  update user_credits
     set balance = balance - p_credits,
         updated_at = now()
   where user_id = p_user_id
   returning balance into v_new_balance;

  if v_new_balance is null then
    raise exception 'NO_CREDIT_ROW' using errcode = 'P0002';
  end if;
  if v_new_balance < 0 then
    -- Roll back the update by raising — caller sees INSUFFICIENT_CREDITS.
    raise exception 'INSUFFICIENT_CREDITS' using errcode = 'P0001';
  end if;

  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (p_user_id, 'debit', -p_credits, p_action, p_source_fn, p_idempotency_key, p_metadata);

  return v_new_balance;
end;
$$;

-- 6) Top-up / grant helper (used by webhook + top-up purchases).
create or replace function public.grant_credits(
  p_user_id uuid,
  p_credits integer,            -- positive integer
  p_kind public.ledger_kind,    -- 'grant' | 'topup' | 'carryover' | 'refund'
  p_action text,
  p_source_fn text,
  p_idempotency_key text,
  p_metadata jsonb default null
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_balance integer;
begin
  if p_credits < 0 then raise exception 'p_credits must be >= 0'; end if;

  -- Idempotency
  if p_idempotency_key is not null and exists (
    select 1 from usage_ledger where idempotency_key = p_idempotency_key
  ) then
    select balance into v_new_balance from user_credits where user_id = p_user_id;
    return coalesce(v_new_balance, 0);
  end if;

  insert into user_credits (user_id, balance, updated_at)
  values (p_user_id, p_credits, now())
  on conflict (user_id) do update
    set balance = user_credits.balance + excluded.balance,
        updated_at = now()
  returning balance into v_new_balance;

  insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
  values (p_user_id, p_kind, p_credits, p_action, p_source_fn, p_idempotency_key, p_metadata);

  return v_new_balance;
end;
$$;

-- 7) RLS — users can read their own subscription + credits + ledger.
--    Writes only happen via SECURITY DEFINER functions called from Edge
--    Functions, so no direct write policies needed.
alter table public.user_subscriptions enable row level security;
alter table public.user_credits       enable row level security;
alter table public.usage_ledger       enable row level security;
alter table public.subscription_plans enable row level security;

create policy "user_subscriptions: owner read" on public.user_subscriptions
  for select using (auth.uid() = user_id);
create policy "user_credits: owner read" on public.user_credits
  for select using (auth.uid() = user_id);
create policy "usage_ledger: owner read" on public.usage_ledger
  for select using (auth.uid() = user_id);

-- subscription_plans is publicly readable (no PII) so the paywall UI can
-- fetch the catalog without auth.
create policy "subscription_plans: public read" on public.subscription_plans
  for select using (true);
