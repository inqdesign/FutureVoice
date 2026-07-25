-- One credit number everywhere: the invite bonus drops 500 → 300 on BOTH
-- sides (invitee and inviter), matching the 300-credit signup grant
-- (20260703150001), so the whole story is "300 ≈ a week of daily talks".
--
-- Note the referral program is NOT beta-scoped — it outlives the beta as the
-- standing acquisition loop, so this number is also the post-launch cost of
-- an invite: 600 credits/redemption ≈ $4.5 real upstream cost. Revisit here
-- (single edit) when paid billing changes that math.
--
-- Past redemptions keep what they were granted (ledger rows are immutable and
-- the idempotency keys are unchanged, so nothing re-grants or claws back).

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
    p_user_id => v_invitee, p_credits => 300, p_kind => 'grant',
    p_action => 'referral_invitee', p_source_fn => 'redeem_referral',
    p_idempotency_key => 'ref_invitee:' || v_invitee::text,
    p_metadata => jsonb_build_object('code', v_code, 'inviter', v_inviter)
  );

  -- Inviter bonus, capped at the first 10 successful invites.
  select count(*) into v_invite_count
    from referral_redemptions where inviter_id = v_inviter;
  if v_invite_count <= 10 then
    perform public.grant_credits(
      p_user_id => v_inviter, p_credits => 300, p_kind => 'grant',
      p_action => 'referral_inviter', p_source_fn => 'redeem_referral',
      p_idempotency_key => 'ref_inviter:' || v_invitee::text,
      p_metadata => jsonb_build_object('code', v_code, 'invitee', v_invitee)
    );
    v_inviter_rewarded := true;
  end if;

  return jsonb_build_object(
    'balance', v_balance,
    'invitee_bonus', 300,
    'inviter_rewarded', v_inviter_rewarded
  );
end;
$$;
