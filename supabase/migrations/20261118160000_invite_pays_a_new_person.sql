-- ---------------------------------------------------------------------------
-- An invite pays a NEW person, not a second account of the same one
-- (2026-11-18, founder).
--
-- Seen that day: one phone made three accounts, the free minutes of two
-- were withheld, and the third redeemed the second's invite code: 1,800
-- seconds each, more than the 1,200 withheld. `redeem_referral` refused an
-- anonymous session, one's own code and a second redemption, and nothing
-- else.
--
-- Two lines added, the rest of the function is the live body unchanged
-- (signature unchanged, so no overload):
--   * a withheld account cannot be the INVITEE ('SELF_REFERRAL');
--   * a withheld INVITER earns nothing, and a real friend they invite still
--     gets the bonus.
-- Comp codes (the branch above) are untouched.
--
-- Not covered: what `free_grant_withheld` does not see (a second phone, a
-- factory reset, an iOS build, which reports no device).
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

    -- A code that replaces the free minutes takes the balance to zero: the
    -- month IS the offer, not the month on top of the signup grant. Done
    -- through an ordinary balance update, so the expiring-balance trigger
    -- keeps its rows in step, and logged as a debit.
    if v_comp.replaces_free_minutes then
      select balance into v_balance from user_credits
       where user_id = v_invitee for update;
      if coalesce(v_balance, 0) > 0 then
        update user_credits set balance = 0, updated_at = now()
         where user_id = v_invitee;
        insert into usage_ledger (user_id, kind, delta, action, source_fn, idempotency_key, metadata)
        values (v_invitee, 'debit', -v_balance, 'comp_replaces_free', 'redeem_referral',
                'comp_free:' || v_code || ':' || v_invitee::text,
                jsonb_build_object('code', v_code, 'cleared_seconds', v_balance))
        on conflict (idempotency_key) do nothing;
      end if;
    end if;

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
  -- A person who has been here before is not a new friend (2026-11-18): an
  -- account whose free minutes were withheld (same email after a deletion, or
  -- a device another account already used) cannot be the invitee. Answered as
  -- the self-referral it is, which every build has words for.
  if exists (select 1 from free_grant_withheld w where w.user_id = v_invitee) then
    raise exception 'SELF_REFERRAL';
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
  -- A withheld inviter earns nothing; their friend above still got theirs.
  if v_invite_count <= 10
     and not exists (select 1 from free_grant_withheld w where w.user_id = v_inviter) then
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
