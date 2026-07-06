-- Beta monitoring: per-user usage visibility for the owner, credit-depletion
-- alerts, and in-app beta reviews (the unified feedback modal writes here).

-- 1) Beta reviews — written by the app's BetaFeedbackSheet at milestones
--    (first conversation, first Watch listen-through, credits depleted).
create table if not exists public.beta_reviews (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  context     text not null,                 -- 'first_talk' | 'first_watch' | 'credits_depleted'
  rating      integer check (rating between 1 and 5),
  body        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists beta_reviews_created_idx on public.beta_reviews(created_at desc);

alter table public.beta_reviews enable row level security;
drop policy if exists "beta_reviews: owner insert" on public.beta_reviews;
create policy "beta_reviews: owner insert" on public.beta_reviews
  for insert with check (auth.uid() = user_id);
drop policy if exists "beta_reviews: owner read" on public.beta_reviews;
create policy "beta_reviews: owner read" on public.beta_reviews
  for select using (auth.uid() = user_id);

-- 2) Depletion alerts — one row per user, written by the credit gate
--    (_shared/credits.ts recordDepletion) the first time a charge fails with
--    INSUFFICIENT_CREDITS. Service-role only; no client policies.
create table if not exists public.credit_depletion_alerts (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  depleted_at timestamptz not null default now(),
  source_fn   text
);
alter table public.credit_depletion_alerts enable row level security;

-- 3) Owner usage report — everything about beta usage in one view.
--    Dashboard/service-role only (joins auth.users), revoked from clients.
create or replace view public.beta_user_usage as
select
  au.id                       as user_id,
  au.email,
  au.created_at               as signed_up_at,
  coalesce(c.balance, 0)      as balance,
  coalesce(gr.granted, 0)     as granted,
  coalesce(sp.spent, 0)       as spent,
  act.last_activity,
  da.depleted_at,
  coalesce(rv.review_count, 0) as review_count
from auth.users au
left join public.user_credits c on c.user_id = au.id
left join lateral (
  select sum(delta) as granted from public.usage_ledger
  where user_id = au.id and delta > 0
) gr on true
left join lateral (
  select sum(-delta) as spent from public.usage_ledger
  where user_id = au.id and kind = 'debit'
) sp on true
left join lateral (
  select max(created_at) as last_activity from public.usage_ledger
  where user_id = au.id
) act on true
left join public.credit_depletion_alerts da on da.user_id = au.id
left join lateral (
  select count(*) as review_count from public.beta_reviews
  where user_id = au.id
) rv on true;

revoke all on public.beta_user_usage from anon, authenticated;

-- Owner queries (Supabase dashboard → SQL editor):
--   select * from beta_user_usage order by spent desc;
--   select email, context, rating, body, created_at
--     from beta_reviews r join auth.users u on u.id = r.user_id
--     order by r.created_at desc;
