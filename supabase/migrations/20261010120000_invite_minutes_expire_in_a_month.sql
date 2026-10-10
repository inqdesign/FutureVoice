-- ---------------------------------------------------------------------------
-- Invite minutes expire one month after they are granted (2026-10-09,
-- founder decision).
--
-- `redeem_referral` grants 30 min a side into `user_credits.balance`, the
-- inviter for their first 10 friends — up to 300 min — and until now that
-- balance never expired. It is also spent with no plan behind it, which is how
-- five lapsed accounts were still talking on old balances on 2026-09-29
-- (`20260929170000`, trimmed by hand). A month is long enough to use 30
-- minutes and short enough that an invite is a reason to talk now.
--
-- The balance is ONE integer that also holds the signup grant, top-up packs
-- and admin grants, none of which expire. So the expiring part is tracked
-- beside it, per grant, in `expiring_balance`:
--
--   * `redeem_referral` notes a row for each invite grant (both sides).
--   * Spending comes off the expiring rows FIRST, soonest expiry first — a
--     trigger on `user_credits`, so every path that lowers the balance
--     (`charge_credits`, the meter's last-tick zeroing, a hand trim) is
--     covered without touching `consume_metered_seconds`. Spending what
--     expires first is the order that loses the learner the least.
--   * `expire_invite_minutes()` (hourly) removes what is left of a grant
--     past its date, never more than the balance holds, with a `debit`
--     ledger row (`invite_minutes_expired`) per grant.
--   * `talk_allowance()` gains `bonus_expires_at` / `bonus_expiring`, so the
--     app can say when; an older build ignores the keys.
--
-- Invariant: sum(remaining) of a user's open rows <= their balance. It holds
-- at insert (the grant just raised the balance by at least that much) and the
-- trigger takes every decrease off the rows first.
--
-- Existing grants (four, 2026-10-05 … 10-08) get the same rule from their own
-- grant date: all are still inside the month. What is left of each is the
-- grant minus what that account has spent since, capped by the balance —
-- the same expiring-first order the trigger applies from now on.
-- ---------------------------------------------------------------------------

create table if not exists public.expiring_balance (
  id               bigserial primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  source           text not null,
  granted_seconds  integer not null check (granted_seconds > 0),
  remaining        integer not null check (remaining >= 0),
  granted_at       timestamptz not null default now(),
  expires_at       timestamptz not null,
  settled_at       timestamptz,
  idempotency_key  text unique
);

create index if not exists expiring_balance_open_by_user
  on public.expiring_balance (user_id, expires_at)
  where remaining > 0 and settled_at is null;
create index if not exists expiring_balance_open_by_date
  on public.expiring_balance (expires_at)
  where remaining > 0 and settled_at is null;

-- Server-only. No policies: nothing on the client reads or writes it directly.
alter table public.expiring_balance enable row level security;

-- ---------------------------------------------------------------------------
-- Note a grant that expires. Called right after the grant itself.
-- ---------------------------------------------------------------------------
create or replace function public.note_expiring_balance(
  p_user_id uuid,
  p_source text,
  p_seconds integer,
  p_idempotency_key text
) returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if p_seconds is null or p_seconds <= 0 then return; end if;
  insert into expiring_balance (user_id, source, granted_seconds, remaining,
                                granted_at, expires_at, idempotency_key)
  values (p_user_id, p_source, p_seconds, p_seconds,
          now(), now() + interval '1 month', p_idempotency_key)
  on conflict (idempotency_key) do nothing;
end;
$function$;

revoke all on function public.note_expiring_balance(uuid, text, integer, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Every decrease of the balance comes off the expiring rows first.
-- The expiry job itself sets `fv.expiring_balance` so its own debit is not
-- counted twice.
-- ---------------------------------------------------------------------------
create or replace function public.spend_expiring_balance()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_left integer := old.balance - new.balance;
  v_take integer;
  r record;
begin
  if coalesce(current_setting('fv.expiring_balance', true), '') = 'on' then
    return new;
  end if;
  for r in
    select id, remaining from expiring_balance
     where user_id = new.user_id and remaining > 0 and settled_at is null
     order by expires_at, id
     for update
  loop
    exit when v_left <= 0;
    v_take := least(v_left, r.remaining);
    update expiring_balance set remaining = remaining - v_take where id = r.id;
    v_left := v_left - v_take;
  end loop;
  return new;
end;
$function$;

drop trigger if exists user_credits_spend_expiring on public.user_credits;
create trigger user_credits_spend_expiring
  after update of balance on public.user_credits
  for each row
  when (new.balance < old.balance)
  execute function public.spend_expiring_balance();

-- ---------------------------------------------------------------------------
-- Remove what is left of every grant past its date.
-- ---------------------------------------------------------------------------
create or replace function public.expire_invite_minutes()
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  r record;
  v_balance integer;
  v_take integer;
  v_count integer := 0;
begin
  for r in
    select * from expiring_balance
     where settled_at is null and expires_at <= now()
     order by expires_at, id
     for update skip locked
  loop
    select balance into v_balance from user_credits
     where user_id = r.user_id for update;
    v_take := least(r.remaining, greatest(coalesce(v_balance, 0), 0));

    if v_take > 0 then
      perform set_config('fv.expiring_balance', 'on', true);
      update user_credits set balance = balance - v_take, updated_at = now()
       where user_id = r.user_id;
      perform set_config('fv.expiring_balance', 'off', true);

      insert into usage_ledger (user_id, kind, delta, action, source_fn,
                                idempotency_key, metadata)
      values (r.user_id, 'debit', -v_take, 'invite_minutes_expired',
              'expire_invite_minutes', 'invite_expired:' || r.id,
              jsonb_build_object('source', r.source,
                                 'granted_seconds', r.granted_seconds,
                                 'granted_at', r.granted_at,
                                 'expires_at', r.expires_at,
                                 'expired_seconds', v_take))
      on conflict (idempotency_key) do nothing;
    end if;

    update expiring_balance set remaining = 0, settled_at = now() where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.expire_invite_minutes() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Grants made before this migration.
-- ---------------------------------------------------------------------------
insert into public.expiring_balance (user_id, source, granted_seconds, remaining,
                                     granted_at, expires_at, idempotency_key)
select l.user_id, l.action, l.delta,
       greatest(0, least(
         l.delta + coalesce((select sum(d.delta) from public.usage_ledger d
                              where d.user_id = l.user_id
                                and d.delta < 0
                                and d.created_at > l.created_at), 0),
         coalesce((select c.balance from public.user_credits c
                    where c.user_id = l.user_id), 0))),
       l.created_at, l.created_at + interval '1 month', l.idempotency_key
  from public.usage_ledger l
 where l.action in ('referral_invitee', 'referral_inviter')
   and l.kind = 'grant' and l.delta > 0
on conflict (idempotency_key) do nothing;

-- ---------------------------------------------------------------------------
-- redeem_referral: unchanged except the two note_expiring_balance calls.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.redeem_referral(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- An anonymous session is not a real account; a referral must not pay out to
  -- (or on behalf of) one, or the bonus becomes farmable N sessions at a time.
  if exists (
    select 1 from auth.users
     where id = v_invitee and coalesce(is_anonymous, false)
  ) then
    raise exception 'ANON_NOT_ALLOWED';
  end if;
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
    -- would make this row look like a renewal of it. The `renewal_*` columns
    -- (20260918100000, added after the comp branch was written) are cleared
    -- for exactly the same reason: they describe what Apple will charge next,
    -- and on a comp the answer is nothing -- left behind, a lapsed offer code
    -- would have the app tell a comped account it is on half price.
    insert into user_subscriptions (
      user_id, plan_id, source, status,
      current_period_start, current_period_end, cancel_at_period_end, updated_at)
    values (
      v_invitee, v_comp.plan_id, 'comp', 'active',
      now(), v_until, not v_comp.standing, now())
    on conflict (user_id) do update
      set plan_id = excluded.plan_id,
          source = 'comp',
          apple_original_tx_id = null,
          stripe_subscription_id = null,
          trial_ends_at = null,
          status = excluded.status,
          current_period_start = excluded.current_period_start,
          current_period_end = excluded.current_period_end,
          cancel_at_period_end = excluded.cancel_at_period_end,
          renewal_offer_type = null,
          renewal_offer_id = null,
          renewal_price_milliunits = null,
          renewal_currency = null,
          renewal_product_id = null,
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
                               'standing', v_comp.standing,
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
  perform public.note_expiring_balance(v_invitee, 'referral_invitee', v_bonus,
                                       'ref_invitee:' || v_invitee::text);

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
    perform public.note_expiring_balance(v_inviter, 'referral_inviter', v_bonus,
                                         'ref_inviter:' || v_invitee::text);
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
-- talk_allowance: + bonus_expires_at / bonus_expiring.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.talk_allowance()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid       uuid := auth.uid();
  v_cap       integer;
  v_unlimited boolean := false;
  v_entitled  boolean := false;
  v_bonus     integer;
  v_used      integer;
  v_start     date;
  v_end       date;
  v_exp_at    timestamptz;
  v_exp_secs  integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select balance into v_bonus from user_credits where user_id = v_uid;

  -- The next batch of invite minutes to lapse (20261010120000): when, and how
  -- much of the balance goes with it. Null when nothing is waiting to expire.
  select e.expires_at, sum(e.remaining)::integer
    into v_exp_at, v_exp_secs
    from expiring_balance e
   where e.user_id = v_uid and e.remaining > 0 and e.settled_at is null
     and e.expires_at = (select min(expires_at) from expiring_balance
                          where user_id = v_uid and remaining > 0 and settled_at is null)
   group by e.expires_at;

  -- The row's stamp outranks the plan (2026-09-26) — the same read the meter
  -- makes in `consume_metered_seconds`, so the number on screen is the
  -- number the wall is judged by.
  select true,
         s.status <> 'trialing' and coalesce(s.talk_unlimited, p.talk_unlimited, false),
         case when s.status = 'trialing'
              then coalesce(s.monthly_seconds,
                            (select min(monthly_seconds) from subscription_plans
                              where tier = 'light'), p.monthly_seconds) * 7 / 30
              else coalesce(s.monthly_seconds, p.monthly_seconds) end,
         s.current_period_end::date
    into v_entitled, v_unlimited, v_cap, v_end
    from user_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid
     and s.status in ('trialing', 'active', 'grace');

  if not coalesce(v_entitled, false) or (v_cap is null and not v_unlimited) then
    return jsonb_build_object('used', 0, 'cap', null, 'bonus', coalesce(v_bonus, 0),
                              'period_start', null, 'period_end', null,
                              'metered_by', 'balance',
                              'bonus_expires_at', v_exp_at,
                              'bonus_expiring', v_exp_secs);
  end if;

  v_start := public.billing_period_start(v_uid);
  v_used := public.plan_period_seconds(v_uid);

  return jsonb_build_object('used', v_used,
                            'cap', case when v_unlimited then null else v_cap end,
                            'unlimited', v_unlimited,
                            'bonus', coalesce(v_bonus, 0),
                            'period_start', v_start,
                            'period_end', coalesce(v_end, (v_start + interval '1 month')::date),
                            'metered_by', 'plan',
                            'bonus_expires_at', v_exp_at,
                            'bonus_expiring', v_exp_secs);
end;
$function$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule('expire_invite_minutes')
      where exists (select 1 from cron.job where jobname = 'expire_invite_minutes');
    perform cron.schedule('expire_invite_minutes', '50 * * * *',
                          $cron$select public.expire_invite_minutes();$cron$);
  end if;
exception when others then
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;
