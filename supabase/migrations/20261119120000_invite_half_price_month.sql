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
--     from the `invite-reward` function with no tap. The App Store needs the
--     subscriber's own confirmation: the app asks `invite_reward_code` for a
--     one-time OFFER CODE from the pool (`invite_offer_codes`), Apple's
--     redeem page applies it to the next renewal, and the reward is marked
--     claimed when APPLE says so (the offer on `user_subscriptions`'
--     renewal info, written by `apple-webhook`), never on the app's word.
--     Measured in the sandbox the same day: a signed promotional offer does
--     nothing for an active subscriber through StoreKit 2, an offer code
--     prices the next renewal.
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
  -- Apple product id -> the offer-code offer's NAME (what Apple's renewal
  -- info calls it); Play product id -> offer id.
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

-- The App Store's one-time offer codes, made ahead by scripts/invite-event.py
-- (`codes`) and handed out one per reward. Service role only: no policy.
create table if not exists public.invite_offer_codes (
  code             text primary key,
  apple_product_id text not null,
  expires_on       date not null,
  reward_id        uuid references public.invite_rewards(id) on delete set null,
  assigned_at      timestamptz,
  created_at       timestamptz not null default now()
);

create index if not exists invite_offer_codes_free
  on public.invite_offer_codes (apple_product_id, expires_on) where reward_id is null;
create index if not exists invite_offer_codes_reward on public.invite_offer_codes (reward_id);

alter table public.invite_offer_codes enable row level security;

-- One reward per billing period: the oldest waiting one, unless one was
-- already claimed in this period. THE rule, read by the state, the code
-- hand-out and (in its own words) the `invite-reward` function.
create or replace function public.invite_claimable(p_user uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select (select r.id from invite_rewards r
           where r.user_id = p_user and r.status = 'ready'
           order by r.created_at limit 1)
    from user_subscriptions s
   where s.user_id = p_user
     and s.status in ('trialing', 'active', 'grace')
     and not exists (
       select 1 from invite_rewards c
        where c.user_id = p_user and c.status = 'claimed'
          and c.claimed_at >= coalesce(s.current_period_start, '-infinity'));
$$;

revoke all on function public.invite_claimable(uuid) from public, anon, authenticated;

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

  v_claimable := public.invite_claimable(v_uid);

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

-- The App Store claim, step one: the code for the reward that can be taken
-- now. The same code is answered again until it is redeemed, so a tap that
-- went nowhere costs nothing. Null when there is nothing to take or the
-- pool is empty.
create or replace function public.invite_reward_code()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_reward  uuid;
  v_product text;
  v_code    text;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not coalesce((select enabled from invite_event where id = 1), false) then return null; end if;
  v_reward := public.invite_claimable(v_uid);
  if v_reward is null then return null; end if;

  select p.apple_product_id into v_product
    from user_subscriptions s join subscription_plans p on p.id = s.plan_id
   where s.user_id = v_uid and s.source = 'apple';
  if v_product is null then return null; end if;

  select code into v_code from invite_offer_codes
   where reward_id = v_reward and apple_product_id = v_product and expires_on > current_date
   order by assigned_at desc limit 1;
  if v_code is null then
    update invite_offer_codes set reward_id = v_reward, assigned_at = now()
     where code = (select code from invite_offer_codes
                    where reward_id is null and apple_product_id = v_product
                      and expires_on > current_date + 1
                    order by expires_on, code limit 1
                    for update skip locked)
    returning code into v_code;
  end if;
  if v_code is null then return null; end if;
  return jsonb_build_object('code', v_code, 'reward_id', v_reward);
end;
$$;

revoke all on function public.invite_reward_code() from public, anon;
grant execute on function public.invite_reward_code() to authenticated;

-- Step two is Apple's: once the code is redeemed, the subscription's renewal
-- info names the event's offer (`renewal_offer_type` 3 = offer code,
-- `renewal_offer_id` = the offer's name). That change, and nothing the app
-- says, marks the reward claimed. Only a CHANGE counts: the webhook rewrites
-- these columns on every notification.
create or replace function public.invite_reward_on_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.renewal_offer_type = 3 and new.renewal_offer_id is not null
     and (old.renewal_offer_id is distinct from new.renewal_offer_id
          or old.renewal_offer_type is distinct from 3)
     and exists (select 1 from invite_event e, jsonb_each_text(e.apple_offers) o
                  where e.id = 1 and o.value = new.renewal_offer_id) then
    begin
      update invite_rewards set status = 'claimed', claimed_at = now(), store = 'apple'
       where id = (select r.id from invite_rewards r
                    where r.user_id = new.user_id and r.status = 'ready'
                    -- the one a code was handed out for, else the oldest
                    order by exists (select 1 from invite_offer_codes c where c.reward_id = r.id) desc,
                             r.created_at
                    limit 1);
    exception when others then
      raise warning 'invite_reward_on_offer failed for %: %', new.user_id, sqlerrm;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists user_subscriptions_invite_offer on public.user_subscriptions;
create trigger user_subscriptions_invite_offer
  after update of renewal_offer_id, renewal_offer_type on public.user_subscriptions
  for each row execute function public.invite_reward_on_offer();
