-- ---------------------------------------------------------------------------
-- A friend who subscribes makes the next month half price, for both
-- (2026-11-19, founder).
--
-- Builds on 20261118170000 (inviting is a subscriber's, and it pays when the
-- friend's first paid plan starts). APPLY THAT ONE FIRST. What changes here
-- is WHAT is paid: while the event is on, a reward row for each side instead
-- of 1,800 seconds. With the event off, the minutes are paid exactly as that
-- migration wrote them.
--
--   * `invite_event`    one row: on/off, the percentage, the months, which
--                       store offer carries it, and every word the app shows
--                       (per language). Nothing about the event is compiled
--                       into the app, so all of it changes without a build
--                       (scripts/invite-event.py).
--   * `invite_rewards`  one row per reward: who, thanks to whom, its terms
--                       AS EARNED (a later change of the percentage never
--                       rewrites one), and where it stands:
--                       ready -> claimed -> used, or revoked.
--   * one reward per friend who subscribes, no cap, spent one billing period
--     at a time (`claimable`).
--   * the stores only carry out what the table says: Stripe gets a coupon
--     from the `invite-reward` function with no tap; the App Store and Play
--     need the subscriber's own confirmation, so the app asks that function
--     for the offer and reports the claim back.
--
-- Nothing here reaches a build that does not know the event: `invite_event`
-- starts OFF, and an older build never calls `invite_event_state`.
-- ---------------------------------------------------------------------------

create table if not exists public.invite_event (
  id               int primary key default 1 check (id = 1),
  enabled          boolean not null default false,
  percent          int not null default 50 check (percent between 1 and 100),
  months           int not null default 1 check (months between 1 and 12),
  -- Raising it shows the announcement sheet once more on every install.
  announce_version int not null default 1,
  -- Apple product id -> promotional offer id; Play product id -> offer id.
  apple_offers     jsonb not null default '{}'::jsonb,
  google_offers    jsonb not null default '{}'::jsonb,
  stripe_coupon_id text,
  -- language -> key -> text. The app falls back to `en`.
  texts            jsonb not null default '{}'::jsonb,
  updated_at       timestamptz not null default now()
);

insert into public.invite_event (id) values (1) on conflict (id) do nothing;

alter table public.invite_event enable row level security;
drop policy if exists invite_event_read on public.invite_event;
create policy invite_event_read on public.invite_event
  for select to anon, authenticated using (true);

create table if not exists public.invite_rewards (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  -- The other person of the pair (no foreign key: their leaving must not
  -- delete a reward already earned).
  other_id    uuid not null,
  role        text not null check (role in ('inviter', 'friend')),
  percent     int not null,
  months      int not null,
  status      text not null default 'ready'
              check (status in ('ready', 'claimed', 'used', 'revoked')),
  store       text,
  created_at  timestamptz not null default now(),
  claimed_at  timestamptz,
  notified_at timestamptz,
  unique (user_id, other_id, role)
);

create index if not exists invite_rewards_user on public.invite_rewards (user_id, status);

alter table public.invite_rewards enable row level security;
drop policy if exists invite_rewards_read_own on public.invite_rewards;
create policy invite_rewards_read_own on public.invite_rewards
  for select to authenticated using (user_id = auth.uid());

-- Tells the `invite-reward` function that these people have something to be
-- told or given. Never allowed to fail the write it rides on.
create or replace function public.invite_reward_notify(p_users uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'cleanup_secret' limit 1;
  if v_url is null or v_secret is null then return; end if;
  perform net.http_post(
    url := v_url || '/functions/v1/invite-reward',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'X-Cleanup-Secret', v_secret),
    body := jsonb_build_object('user_ids', to_jsonb(p_users))
  );
exception when others then
  raise warning 'invite_reward_notify failed: %', sqlerrm;
end;
$$;

revoke all on function public.invite_reward_notify(uuid[]) from public, anon, authenticated;

-- The one place an invite is paid (20261118170000). Returns whether it paid.
create or replace function public.pay_referral_reward(p_invitee uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row    referral_redemptions%rowtype;
  v_event  invite_event%rowtype;
  v_bonus  int := 1800;
  v_paid   int;
begin
  select * into v_row from referral_redemptions
   where invitee_id = p_invitee and rewarded_at is null
   for update;
  if not found then return false; end if;

  select * into v_event from invite_event where id = 1;

  if coalesce(v_event.enabled, false) then
    -- The event: a half-price month for each side, on the terms of today.
    insert into invite_rewards (user_id, other_id, role, percent, months)
    values (v_row.invitee_id, v_row.inviter_id, 'friend', v_event.percent, v_event.months)
    on conflict (user_id, other_id, role) do nothing;
    -- A withheld inviter earns nothing; their friend above still got theirs.
    if not exists (select 1 from free_grant_withheld w where w.user_id = v_row.inviter_id) then
      insert into invite_rewards (user_id, other_id, role, percent, months)
      values (v_row.inviter_id, v_row.invitee_id, 'inviter', v_event.percent, v_event.months)
      on conflict (user_id, other_id, role) do nothing;
    end if;
    update referral_redemptions set rewarded_at = now()
     where invitee_id = v_row.invitee_id;
    perform public.invite_reward_notify(array[v_row.invitee_id, v_row.inviter_id]);
    return true;
  end if;

  -- Event off: the minutes, as 20261118170000 pays them.
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

-- A new billing period is when the NEXT waiting reward can be given: the
-- one before it has been charged by then.
create or replace function public.invite_reward_on_renewal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.current_period_start is distinct from old.current_period_start
     and exists (select 1 from invite_rewards r
                  where r.user_id = new.user_id and r.status in ('ready', 'claimed')) then
    begin
      update invite_rewards set status = 'used'
       where user_id = new.user_id and status = 'claimed'
         and claimed_at < new.current_period_start;
      if exists (select 1 from invite_rewards r
                  where r.user_id = new.user_id and r.status = 'ready') then
        perform public.invite_reward_notify(array[new.user_id]);
      end if;
    exception when others then
      raise warning 'invite_reward_on_renewal failed for %: %', new.user_id, sqlerrm;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists user_subscriptions_invite_reward on public.user_subscriptions;
create trigger user_subscriptions_invite_reward
  after update of current_period_start on public.user_subscriptions
  for each row execute function public.invite_reward_on_renewal();

-- Everything the app draws the event from, in one call.
create or replace function public.invite_event_state()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_event  invite_event%rowtype;
  v_sub    user_subscriptions%rowtype;
  v_plan   subscription_plans%rowtype;
  v_entitled boolean := false;
  v_claimable uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_event from invite_event where id = 1;
  if not coalesce(v_event.enabled, false) then
    return jsonb_build_object('enabled', false);
  end if;

  select * into v_sub from user_subscriptions where user_id = v_uid;
  if found then
    v_entitled := v_sub.status in ('trialing', 'active', 'grace');
    select * into v_plan from subscription_plans where id = v_sub.plan_id;
  end if;

  -- One reward per billing period: the oldest waiting one, unless one was
  -- already claimed in this period.
  if v_entitled and not exists (
       select 1 from invite_rewards r
        where r.user_id = v_uid and r.status = 'claimed'
          and r.claimed_at >= coalesce(v_sub.current_period_start, '-infinity')) then
    select id into v_claimable from invite_rewards
     where user_id = v_uid and status = 'ready'
     order by created_at limit 1;
  end if;

  return jsonb_build_object(
    'enabled', true,
    'percent', v_event.percent,
    'months', v_event.months,
    'announce_version', v_event.announce_version,
    'texts', v_event.texts,
    'can_invite', v_entitled,
    'code', (select code from referral_codes where user_id = v_uid limit 1),
    -- Came through someone's invite and has not subscribed yet.
    'invited', exists (select 1 from referral_redemptions
                        where invitee_id = v_uid and rewarded_at is null),
    'store', case when v_entitled then v_sub.source end,
    'period', case when v_entitled then v_plan.period end,
    'apple_product_id', case when v_entitled then v_plan.apple_product_id end,
    'apple_offer_id', case when v_entitled
                           then v_event.apple_offers ->> v_plan.apple_product_id end,
    'google_product_id', case when v_entitled then v_plan.google_product_id end,
    'google_offer_id', case when v_entitled
                            then v_event.google_offers ->> v_plan.google_product_id end,
    'renews_at', case when v_entitled then v_sub.current_period_end end,
    'claimable', v_claimable,
    'rewards', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'role', r.role, 'status', r.status,
               'percent', r.percent, 'months', r.months,
               'claimed_at', r.claimed_at) order by r.created_at)
        from invite_rewards r where r.user_id = v_uid), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.invite_event_state() from public, anon;
grant execute on function public.invite_event_state() to authenticated;

-- The app's word that the store took the offer (the App Store and Play ask
-- the subscriber; Stripe is marked by the function that applied the coupon).
create or replace function public.invite_reward_claimed(p_id uuid, p_store text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update invite_rewards
     set status = 'claimed', claimed_at = now(), store = p_store
   where id = p_id and user_id = auth.uid() and status = 'ready';
  return found;
end;
$$;

revoke all on function public.invite_reward_claimed(uuid, text) from public, anon;
grant execute on function public.invite_reward_claimed(uuid, text) to authenticated;
