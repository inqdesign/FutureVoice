-- The invite bonus becomes 30 minutes a side (1800 s), down from 66.
--
-- 66 min was never chosen for the invite — it was the SIGNUP grant's size,
-- copied so the whole story could be one number. That grant is gone (hard
-- paywall, 20260811180000), so the invite is now the only free talk time in
-- the product and has to be priced on its own: enough to have real calls and
-- feel what the app does, not so much that a code is a free month. 30 min is
-- six days at the Daily plan's 5 min/day.
--
-- Both sides stay equal and the inviter's 10-redemption cap is unchanged, so
-- a fully-worked code is 300 min given away instead of 660.
--
-- Idempotency keys are UNCHANGED, so nobody re-grants and nobody is clawed
-- back: past redemptions keep the 66 min they were given.

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
  v_bonus int := 1800;          -- seconds, both sides
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
$$;

revoke all on function public.redeem_referral(text) from public;
grant execute on function public.redeem_referral(text) to authenticated;
