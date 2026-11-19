-- ---------------------------------------------------------------------------
-- Inviting is a subscriber's, and it pays when the friend subscribes
-- (2026-11-18, founder).
--
-- Until now any account's code paid 1,800 seconds to both sides the moment a
-- new account typed it, so two free accounts of one person were worth an
-- hour (20261118150000). Now:
--
--   * a code works only while its OWNER has a plan (any entitled row, comp
--     included); otherwise it answers INVALID_CODE;
--   * typing it pays nothing. The redemption is recorded and waits;
--   * when the friend's first PAID plan starts (active or grace, not a comp),
--     both sides get 1,800 seconds, once. The inviter is paid for the first
--     10 friends who subscribed, as before;
--   * an account that has or had a plan cannot be the friend
--     (ALREADY_SUBSCRIBED), so two subscribers cannot pay each other;
--   * a withheld account still cannot be the friend (20261118160000).
--
-- APPLY WITH THE APP BUILD THAT SAYS SO, not before: builds in the stores
-- print "we both get 30 minutes when you sign up" and "Invite applied ·
-- 30 min", and would say it over a redemption that paid nothing.
--
-- Every redemption on file was already paid under the old rule and is
-- stamped as such; the ledger keys (`ref_invitee:` / `ref_inviter:`) are the
-- same ones, so nothing old can be paid twice either way.
-- ---------------------------------------------------------------------------

alter table public.referral_redemptions
  add column if not exists rewarded_at timestamptz;

update public.referral_redemptions
   set rewarded_at = created_at
 where rewarded_at is null;

-- The one place an invite is paid. Returns whether it paid.
create or replace function public.pay_referral_reward(p_invitee uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row    referral_redemptions%rowtype;
  v_bonus  int := 1800;
  v_paid   int;
begin
  select * into v_row from referral_redemptions
   where invitee_id = p_invitee and rewarded_at is null
   for update;
  if not found then return false; end if;

  perform public.grant_credits(
    p_user_id => v_row.invitee_id, p_credits => v_bonus, p_kind => 'grant',
    p_action => 'referral_invitee', p_source_fn => 'pay_referral_reward',
    p_idempotency_key => 'ref_invitee:' || v_row.invitee_id::text,
    p_metadata => jsonb_build_object('code', v_row.code, 'inviter', v_row.inviter_id)
  );
  perform public.note_expiring_balance(v_row.invitee_id, 'referral_invitee', v_bonus,
                                       'ref_invitee:' || v_row.invitee_id::text);

  select count(*) into v_paid from referral_redemptions
   where inviter_id = v_row.inviter_id and rewarded_at is not null;
  if v_paid < 10 then
    perform public.grant_credits(
      p_user_id => v_row.inviter_id, p_credits => v_bonus, p_kind => 'grant',
      p_action => 'referral_inviter', p_source_fn => 'pay_referral_reward',
      p_idempotency_key => 'ref_inviter:' || v_row.invitee_id::text,
      p_metadata => jsonb_build_object('code', v_row.code, 'invitee', v_row.invitee_id)
    );
    perform public.note_expiring_balance(v_row.inviter_id, 'referral_inviter', v_bonus,
                                         'ref_inviter:' || v_row.invitee_id::text);
  end if;

  update referral_redemptions set rewarded_at = now()
   where invitee_id = v_row.invitee_id;
  return true;
end;
$$;

revoke all on function public.pay_referral_reward(uuid) from public, anon, authenticated;

-- A paid plan starting is what pays. Never allowed to fail the write it
-- rides on: that write is a store webhook recording a purchase.
create or replace function public.pay_referral_on_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('active', 'grace') and new.source is distinct from 'comp' then
    begin
      perform public.pay_referral_reward(new.user_id);
    exception when others then
      raise warning 'pay_referral_reward failed for %: %', new.user_id, sqlerrm;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists user_subscriptions_pay_referral on public.user_subscriptions;
create trigger user_subscriptions_pay_referral
  after insert or update of status, source on public.user_subscriptions
  for each row execute function public.pay_referral_on_subscription();

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
  -- Inviting is a subscriber's (2026-11-18): a code whose owner has no plan
  -- right now is not a code. Comp plans count; they cost the friend nothing.
  if not public.voice_owner_is_entitled(v_inviter) then raise exception 'INVALID_CODE'; end if;
  -- The reward is for a friend who goes on to subscribe, so an account that
  -- already has, or once had, a plan is not that friend.
  if exists (select 1 from user_subscriptions where user_id = v_invitee) then
    raise exception 'ALREADY_SUBSCRIBED';
  end if;
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

  -- Nothing is paid here. Both sides are paid once, when this account's
  -- first paid plan starts (`pay_referral_reward`, from the trigger below).
  select balance into v_balance from user_credits where user_id = v_invitee;

  return jsonb_build_object(
    'balance', coalesce(v_balance, 0),
    'invitee_bonus', 0,
    'inviter_rewarded', false,
    'reward_pending', true,
    'reward_seconds', v_bonus
  );
end;
$function$;
