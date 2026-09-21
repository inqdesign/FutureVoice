-- ---------------------------------------------------------------------------
-- Ten free minutes replace the 7-day trial (2026-09-21, founder decision).
--
-- Every account gets `free_talk_seconds` of talk; the plans are offered once
-- they are spent, and there is no trial behind them. The trial is removed in
-- App Store Connect only after the build without trial copy is on the store —
-- 1.0.6 draws "7 days free" whether or not an intro offer exists.
--
-- 1. New accounts start at 600 s (was 300 s, 20260920090000).
-- 2. Existing accounts are topped up to the SAME total: 600 s minus what they
--    have already spent of free time. Someone who used 3 minutes of the old
--    5 has 7 left, not 10. "Spent" is talk charged against the balance
--    (`covered_by = 'balance'`); invite minutes, trial and plan time are
--    their own pools and don't count against it. A balance already above the
--    target is left alone — nothing is ever taken back.
--
-- Skipped: anyone who has EVER held a subscription — a subscriber, a trial
-- running or ended, a comp (any `user_subscriptions` row; founder decision,
-- the free minutes are for people who have not tried the paid product) —
-- `unlimited` accounts, and anonymous sessions (an unclaimed onboarding
-- session is collected after 48 h anyway).
--
-- Idempotent: the grant goes through `grant_credits` with a per-user key, so
-- re-running this file grants nobody twice.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
declare
  -- The whole free offer. Keep it a named constant: the welcome sheet reads
  -- the balance, so this is the only place the number lives.
  free_talk_seconds constant integer := 600;
begin
  insert into public.user_credits (user_id, balance, updated_at)
  values (new.id, free_talk_seconds, now())
  on conflict (user_id) do nothing;
  return new;
end;
$$;

do $$
declare
  r record;
begin
  for r in
    with base as (
      select c.user_id,
             c.balance,
             coalesce((select -sum(l.delta)
                         from public.usage_ledger l
                        where l.user_id = c.user_id
                          and l.action = 'talk_time'
                          and l.metadata->>'covered_by' = 'balance'), 0) as used
        from public.user_credits c
        join auth.users u on u.id = c.user_id
       where not coalesce(c.unlimited, false)
         and not coalesce(u.is_anonymous, false)
         and not exists (select 1 from public.user_subscriptions s
                          where s.user_id = c.user_id)
    )
    select user_id, balance, used,
           greatest(0, 600 - used) - balance as top_up
      from base
     where greatest(0, 600 - used) > balance
  loop
    perform public.grant_credits(
      r.user_id, r.top_up::integer, 'grant'::public.ledger_kind,
      'free_talk_topup', 'migration',
      'free_ten_minutes:' || r.user_id::text,
      jsonb_build_object('reason', 'ten free minutes',
                         'used_before', r.used,
                         'balance_before', r.balance,
                         'migration', '20260921120000'));
  end loop;
end $$;
