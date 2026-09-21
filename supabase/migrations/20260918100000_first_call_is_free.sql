-- ---------------------------------------------------------------------------
-- The first call is free — the paywall moves behind it.
--
-- Measured 2026-09-18 over the launch week (37 signups, 9/12–9/17):
--   voice clone finished       37 (100%)
--   reached the Talk tab       36
--   started ONE call           23 (62%)
-- Every one of the 14 who stopped had cloned their voice, heard it speak, and
-- opened Talk; 13 of them have no subscription row at all, and most left
-- within TWO MINUTES of signing up. The hard paywall (20260811180000) asks
-- them to buy before they have said a single word to the fluent self — the
-- one thing the product is. The trial data says the same from the other end:
-- the people who turned auto-renew off had a median of ~2 minutes of talk,
-- the ones who left it on ~25.
--
-- So a new account gets `first_call_seconds` of talk, once, and the paywall
-- arrives after that call's summary instead of before the call. This is NOT
-- a return to the old free pool: 300 s buys one conversation (the launch
-- week's mean call is 3.5 min), it never refills, and every other free
-- surface is unchanged.
--
-- Cost of the grant is ~$0.23 per signup at the measured $0.046/talk-minute —
-- cheaper than the mail we would otherwise send to win one of them back.
--
-- Idempotent twice over: the trigger is `on conflict do nothing`, and the
-- backfill goes through `grant_credits` with a per-user idempotency key, so
-- re-running this file grants nobody a second helping (the 2026-08-11
-- minutes conversion taught that lesson).
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
declare
  -- One call. Keep it a named constant: this is the number the whole
  -- "try it before you buy it" decision rests on.
  first_call_seconds constant integer := 300;
begin
  insert into public.user_credits (user_id, balance, updated_at)
  values (new.id, first_call_seconds, now())
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- The accounts the hard paywall already turned away: still at zero, nothing
-- bought, and never a second of talk. They are exactly the people this change
-- is for, so they get the same 300 s rather than being told to reinstall.
do $$
declare
  r record;
begin
  for r in
    select c.user_id
      from public.user_credits c
     where c.balance = 0
       and not coalesce(c.unlimited, false)
       and not exists (select 1 from public.user_subscriptions s
                        where s.user_id = c.user_id
                          and s.status in ('active', 'trialing'))
       and not exists (select 1 from public.usage_ledger l
                        where l.user_id = c.user_id
                          and l.action = 'talk_time')
  loop
    perform public.grant_credits(
      r.user_id, 300, 'grant'::public.ledger_kind,
      'first_call_grant', 'migration',
      'first_call_grant:' || r.user_id::text,
      jsonb_build_object('reason', 'first call is free',
                         'migration', '20260918100000'));
  end loop;
end $$;
