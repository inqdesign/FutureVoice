-- ---------------------------------------------------------------------------
-- Twenty free minutes, and no trial behind them (2026-09-26, founder decision).
--
-- The 2026-09-21 rule stays: every account gets `free_talk_seconds` of talk
-- and is offered the plans once it is spent. Only the size moves, 600 → 1200,
-- and the App Store's 3-day intro offer is deleted alongside (by hand, in
-- App Store Connect — the app shows a trial only while an offer exists).
--
-- Why 20, from the numbers on 2026-09-26: of 29 signups since the 10-minute
-- rule, only 8 (28%) reached the wall, and BOTH of the two who subscribed
-- were among them — nobody subscribed before the wall. So the wall converts,
-- and a longer runway costs only the engaged 28%: the average free spend
-- moves from ~$0.20 to ~$0.31 a signup at $0.03/min. Meanwhile 0 of 20
-- trials converted (18 expired, all cancelled) while the four paying
-- subscribers had all bought WITHOUT a trial, and the trial's own 35-minute
-- talk pool was a second, hidden limit under "3 days free". One number is
-- honest; two were confusing.
--
-- 1. New accounts start at 1200 s.
-- 2. Existing accounts are topped up to the SAME total: 1200 s minus what
--    they have already spent of free time (`covered_by = 'balance'`). A
--    balance already above the target is left alone — nothing is ever taken
--    back. Same skips as 20260921120000: anyone who has EVER held a
--    subscription, `unlimited` accounts, anonymous sessions.
--
-- The app is untouched by construction — the welcome sheet and the paywall
-- read the balance — except `AccountStatus.freeGrantSeconds`, the ring's
-- scale, which follows in the next build; an older build draws a fresh
-- account's ring as full for its first ten minutes, and nothing else.
--
-- Idempotent: the grant goes through `grant_credits` with a per-user key.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
declare
  -- The whole free offer. Keep it a named constant: the welcome sheet reads
  -- the balance, so this is the only place the number lives.
  free_talk_seconds constant integer := 1200;
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
           greatest(0, 1200 - used) - balance as top_up
      from base
     where greatest(0, 1200 - used) > balance
  loop
    perform public.grant_credits(
      r.user_id, r.top_up::integer, 'grant'::public.ledger_kind,
      'free_talk_topup', 'migration',
      'free_twenty_minutes:' || r.user_id::text,
      jsonb_build_object('reason', 'twenty free minutes',
                         'used_before', r.used,
                         'balance_before', r.balance,
                         'migration', '20260926100000'));
  end loop;
end $$;
