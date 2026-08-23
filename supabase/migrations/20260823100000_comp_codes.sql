-- ---------------------------------------------------------------------------
-- Comp codes: hand someone a subscription before they have an account.
--
-- The waitlist is a list of EMAILS, and a subscription is a row keyed on
-- `auth.users(id)` — so there is nothing to write until they sign up. The
-- obvious bridge (a pending grant keyed on email, redeemed by a trigger when
-- the account appears) does not survive contact with this app's only sign-in:
-- **5 of the 7 accounts that have an email at all are Apple private relay**
-- addresses. Someone who taps "Hide My Email" arrives as a stranger, and the
-- grant we promised them sits unclaimed against a gmail nobody will ever
-- authenticate with. An email is not an identity here.
--
-- A CODE is, because the person carries it. It also lands at the right MOMENT:
-- the Welcome screen already has "Have an invite code?", and `AuthService`
-- redeems whatever was typed there the instant the session exists — before
-- the voice clone, and long before `OnboardingPaywallView`. That step asks
-- `BillingGate.blocks()` and steps aside silently for anyone with nothing to
-- buy, so a comped learner never sees a paywall at all. Redeeming later from
-- Me → Invite works identically; they'd just have dismissed the pitch once.
--
-- Codes ride on `redeem_referral` rather than getting an RPC of their own:
-- the field, the pending-code hand-off through sign-in, and the error mapping
-- all exist there, and a second code entry point would be a second thing to
-- explain. The comp branch runs FIRST and returns early — a comp code is not
-- a referral and grants nobody a bonus.
--
-- What a comp is NOT: a trial. `status = 'active'` on purpose — a trialing
-- row is metered at a pro-rated 7/30 of the pool (20260811180000), and a gift
-- that quietly hands over a fifth of what it names isn't one.
-- ---------------------------------------------------------------------------

-- `user_subscriptions.source` is NOT NULL DEFAULT 'apple' and checked against
-- ('apple','stripe') (20260703120000). A comp left to the default files itself
-- as an Apple purchase — a row claiming a receipt that does not exist. It gets
-- its own value instead, which then serves as the marker the expiry sweep and
-- the "don't overwrite a real subscription" guard key on. Nothing reads
-- `source` to branch on — only the two webhooks write it — so widening it is
-- safe.
alter table public.user_subscriptions
  drop constraint if exists user_subscriptions_source_check;
alter table public.user_subscriptions
  add constraint user_subscriptions_source_check
  check (source in ('apple', 'stripe', 'comp'));

create table if not exists public.comp_codes (
  code             text primary key,                                  -- uppercase; the client upper()s input
  plan_id          text not null references public.subscription_plans(id),
  months           integer not null default 1 check (months between 1 and 24),
  max_redemptions  integer not null default 1 check (max_redemptions >= 1),
  redeemed_count   integer not null default 0,
  note             text,                                              -- who it was for, and why
  expires_at       timestamptz,                                       -- the CODE stops working; null = never
  created_at       timestamptz not null default now()
);

comment on table public.comp_codes is
  'Codes that grant a comped subscription on redemption. Issued by hand; '
  'redeemed through redeem_referral. One code per person by default.';

create table if not exists public.comp_redemptions (
  code          text not null references public.comp_codes(code) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  plan_id       text not null,
  granted_until timestamptz not null,
  created_at    timestamptz not null default now(),
  primary key (code, user_id)
);

-- Neither table is ever read by a client: the comp shows up as an ordinary
-- `user_subscriptions` row, which is what every surface already reads. No
-- policies, so RLS denies everything that isn't service_role or a
-- security-definer function.
alter table public.comp_codes       enable row level security;
alter table public.comp_redemptions enable row level security;
revoke all on public.comp_codes       from anon, authenticated;
revoke all on public.comp_redemptions from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Expiry.
--
-- `consume_metered_seconds` looks at `status` and never at
-- `current_period_end`, deliberately — a lagging Apple webhook must not cut
-- off someone who has paid. A comp has no webhook behind it, so nothing would
-- ever end it: the row would stay 'active' forever with a pool that never
-- refills (`billing_period_start` is `max(current_period_start)`), which is
-- the worst of both — an account that can't be sold to and can't talk either.
-- A nightly sweep flips only the rows this file created.
-- ---------------------------------------------------------------------------

create or replace function public.expire_comp_subscriptions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  update user_subscriptions
     set status = 'expired', updated_at = now()
   where source = 'comp'
     and status in ('active', 'trialing', 'grace')
     and current_period_end is not null
     and current_period_end < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.expire_comp_subscriptions() from public, anon, authenticated;
grant execute on function public.expire_comp_subscriptions() to service_role;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule('expire_comp_subscriptions')
      where exists (select 1 from cron.job where jobname = 'expire_comp_subscriptions');
    perform cron.schedule('expire_comp_subscriptions', '25 0 * * *',
                          $cron$select public.expire_comp_subscriptions();$cron$);
  end if;
exception when others then
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- Redemption. Everything below the comp branch is the 20260818100000 body,
-- unchanged.
-- ---------------------------------------------------------------------------

create or replace function public.redeem_referral(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_invitee uuid := auth.uid();
  v_inviter uuid;
  v_code text := upper(trim(p_code));
  v_invite_count int;
  v_balance int;
  v_inviter_rewarded boolean := false;
  v_bonus int := 1800;          -- seconds, both sides
  v_comp record;
  v_until timestamptz;
begin
  if v_invitee is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if v_code is null or length(v_code) = 0 then raise exception 'INVALID_CODE'; end if;

  -- ---- Comp code: grants a subscription, returns early. -------------------
  select * into v_comp from comp_codes where code = v_code for update;
  if found then
    if v_comp.expires_at is not null and v_comp.expires_at < now() then
      raise exception 'INVALID_CODE';
    end if;
    if v_comp.redeemed_count >= v_comp.max_redemptions then
      raise exception 'INVALID_CODE';
    end if;
    if exists (select 1 from comp_redemptions where user_id = v_invitee) then
      raise exception 'ALREADY_REDEEMED';
    end if;
    -- Never overwrite something they are paying for. A comp on top of a real
    -- subscription would replace the plan they bought with the one we chose.
    if exists (
      select 1 from user_subscriptions
       where user_id = v_invitee
         and status in ('trialing', 'active', 'grace')
         and source <> 'comp'
    ) then
      raise exception 'ALREADY_SUBSCRIBED';
    end if;

    v_until := now() + make_interval(months => v_comp.months);

    -- Which code granted it lives in `comp_redemptions`, so the Apple and
    -- Stripe id columns are cleared rather than borrowed: a comp has no
    -- receipt anywhere, and a leftover id from an old lapsed subscription
    -- would make this row look like a renewal of it.
    insert into user_subscriptions (
      user_id, plan_id, source, status,
      current_period_start, current_period_end, cancel_at_period_end, updated_at)
    values (
      v_invitee, v_comp.plan_id, 'comp', 'active',
      now(), v_until, true, now())
    on conflict (user_id) do update
      set plan_id = excluded.plan_id,
          source = 'comp',
          apple_original_tx_id = null,
          stripe_subscription_id = null,
          trial_ends_at = null,
          status = excluded.status,
          current_period_start = excluded.current_period_start,
          current_period_end = excluded.current_period_end,
          cancel_at_period_end = true,
          updated_at = now();

    insert into comp_redemptions (code, user_id, plan_id, granted_until)
    values (v_code, v_invitee, v_comp.plan_id, v_until);

    update comp_codes set redeemed_count = redeemed_count + 1 where code = v_code;

    -- Audit only: a comp moves no seconds, so the delta is 0.
    insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
    values (v_invitee, 'grant', 0, 'comp_subscription', 'redeem_referral',
            'comp:' || v_code || ':' || v_invitee::text,
            jsonb_build_object('code', v_code, 'plan_id', v_comp.plan_id,
                               'months', v_comp.months, 'until', v_until,
                               'note', v_comp.note))
    on conflict (idempotency_key) do nothing;

    select balance into v_balance from user_credits where user_id = v_invitee;

    return jsonb_build_object(
      'balance', coalesce(v_balance, 0),
      'invitee_bonus', 0,
      'inviter_rewarded', false,
      'comp_plan', v_comp.plan_id,
      'comp_until', v_until
    );
  end if;
  -- ---- /comp --------------------------------------------------------------

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
    p_user_id => v_invitee, p_credits => v_bonus, p_kind => 'grant',
    p_action => 'referral_invitee', p_source_fn => 'redeem_referral',
    p_idempotency_key => 'ref_invitee:' || v_invitee::text,
    p_metadata => jsonb_build_object('code', v_code, 'inviter', v_inviter)
  );

  -- Inviter bonus, capped at the first 10 successful invites.
  select count(*) into v_invite_count
    from referral_redemptions where inviter_id = v_inviter;
  if v_invite_count <= 10 then
    perform public.grant_credits(
      p_user_id => v_inviter, p_credits => v_bonus, p_kind => 'grant',
      p_action => 'referral_inviter', p_source_fn => 'redeem_referral',
      p_idempotency_key => 'ref_inviter:' || v_invitee::text,
      p_metadata => jsonb_build_object('code', v_code, 'invitee', v_invitee)
    );
    v_inviter_rewarded := true;
  end if;

  return jsonb_build_object(
    'balance', v_balance,
    'invitee_bonus', v_bonus,
    'inviter_rewarded', v_inviter_rewarded
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- The first one: a beta-waitlist signup (public.waitlist
-- 211b84e3-decb-425d-aa35-776869499f8f, joined 2026-08-12), one month of
-- Light. Single use, and the code itself lapses in 90 days so an unclaimed
-- gift doesn't sit redeemable forever.
-- ---------------------------------------------------------------------------
insert into public.comp_codes (code, plan_id, months, max_redemptions, note, expires_at)
values ('WLL8NM5T', 'light_monthly', 1, 1,
        'waitlist 211b84e3-decb-425d-aa35-776869499f8f', now() + interval '90 days')
on conflict (code) do nothing;
