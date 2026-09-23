-- ---------------------------------------------------------------------------
-- A comp code can be STANDING — and the comp branch comes back, because
-- production has been without it since the day it shipped.
--
-- What was found on 2026-09-23, asked for a code to give family:
--
--   * `public.redeem_referral(text)` in production is the body from
--     `20260822100000_prelaunch_security` — the anonymous-session guard, and
--     NO comp branch. `20260823100000_comp_codes` is recorded as applied and
--     its tables are there with rows in them, but the function it re-created
--     is not what the database holds. So every comp code ever issued has
--     fallen through to the referral lookup and raised INVALID_CODE: the
--     waitlist code of 2026-08-23 and the five tester codes of 2026-09-13 are
--     all still `redeemed_count = 0`, which until now read as "nobody used
--     them" and actually meant "nobody could".
--     The lesson is in `create or replace` itself: two migrations that both
--     rewrite one function are not commutative, and applying them out of
--     order silently reverts the newer one. This file therefore restores the
--     comp branch ON TOP of the live body rather than re-applying the old
--     file, and any future edit to this function must start from
--     `pg_get_functiondef` in production, never from the last migration that
--     happens to mention it.
--
--   * A comp CODE always ends. `20260910120000` made `cancel_at_period_end`
--     the difference between the two kinds of comp — true = a gift of N
--     months that the nightly sweep expires, false = a standing comp the
--     same sweep rolls forward a month at a time, forever — but only a hand
--     written row could ever be the second kind. Family is the second kind:
--     it is not a gift with a date on it, and `months` maxes out at 24 so
--     "long enough" cannot be spelled as a number anyway.
--
--     `comp_codes.standing` says which kind the code mints. It defaults to
--     false, so every code already on file keeps the meaning it was issued
--     with; a standing code takes `months` as the length of its FIRST period
--     only, and one month is right for the same reason a real subscription
--     renews monthly — the pool refills at the boundary.
--
-- Nothing in the app changes. The client posts a code to this RPC and reads
-- the ordinary `user_subscriptions` row that comes out of it, and a standing
-- comp is a row whose period end moves — which is exactly what the surfaces
-- already say ("Refills on …", because `cancel_at_period_end` is false).
-- ---------------------------------------------------------------------------

alter table public.comp_codes
  add column if not exists standing boolean not null default false;

comment on column public.comp_codes.standing is
  'false: the comp ends after `months` (a gift). true: `months` is only the '
  'first period and expire_comp_subscriptions rolls it forward forever '
  '(family, and anyone else kept indefinitely).';

-- ---------------------------------------------------------------------------
-- The live body, with the comp branch restored between the anonymous guard
-- and the referral lookup. Comp is checked FIRST and returns early: a comp
-- code is not a referral and pays nobody a bonus.
--
-- The anonymous guard stays in FRONT of it, deliberately. `AuthService` only
-- redeems a pending code once `isSignedIn`, so no real client reaches here
-- anonymously, and a subscription granted to a session that dies with the
-- install would be spent on a user nobody can sign into again.
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
-- Five standing Plus comps, for family.
--
-- `plus_monthly` for the same reason the testers got it: Plus is the tier
-- with no talk ceiling, so the gift cannot run out mid-call. Scenes are still
-- counted (120 a month), which is the one limit they can actually meet.
--
-- One redemption each — a shared string is a free subscription for whoever it
-- leaks to. The CODE lapses in a year if it is never used; the subscription it
-- mints does not lapse at all. Fill in the note as they are handed out: it is
-- the only record of who got which.
-- ---------------------------------------------------------------------------
insert into public.comp_codes (code, plan_id, months, max_redemptions, standing, note, expires_at)
values
  ('W5A6C5TA', 'plus_monthly', 1, 1, true, 'family 1 (unassigned)', now() + interval '1 year'),
  ('E55HJT94', 'plus_monthly', 1, 1, true, 'family 2 (unassigned)', now() + interval '1 year'),
  ('8XWWYBJY', 'plus_monthly', 1, 1, true, 'family 3 (unassigned)', now() + interval '1 year'),
  ('Q4AXXFPK', 'plus_monthly', 1, 1, true, 'family 4 (unassigned)', now() + interval '1 year'),
  ('UMTGXGM2', 'plus_monthly', 1, 1, true, 'family 5 (unassigned)', now() + interval '1 year')
on conflict (code) do nothing;
