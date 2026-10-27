-- What the app says about a subscription, decided HERE (2026-10-27).
--
-- A Plus subscriber bought Light annual on 10-25. Apple ranks Plus above
-- Light, so that is a downgrade and starts at the renewal (11-02) — and the
-- app said nothing about it: Me → Subscribe still badged Plus as "Current
-- plan", the receipt printed "Next charge ₩149,000" with no plan beside it,
-- and the learner reopened the plans seven times in two days. Everything the
-- answer needs was already on the server (`renewal_product_id` from Apple's
-- renewal info, the catalog's sizes); the app just never read it.
--
-- So the server computes it and the app only draws it, which is the point:
-- a rule about what a pending change means (stamps, sizes, which statuses
-- count) changes here, and every installed build shows the new answer
-- without a release.
--
--   pending — the plan Apple will move this subscription to at the next
--             renewal, with the sizes it will have then. A plan change clears
--             the size stamps (20261012140000), so the catalog row IS what
--             the new plan will carry. Null when nothing changes, when the
--             plan is set to end, or when Apple's product isn't in the
--             catalog (never guess a size).
--   notes   — lines written by hand about subscriptions, per language
--             (`subscription_notes`), for this account or for everyone. The
--             app shows the one in its language, else English, else any.

create table if not exists public.subscription_notes (
  id uuid primary key default gen_random_uuid(),
  -- Null = every subscriber.
  user_id uuid references auth.users(id) on delete cascade,
  -- {"ko": "…", "en": "…"} — the learner's app language picks.
  texts jsonb not null,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.subscription_notes enable row level security;
-- No policies: read only through subscription_summary() below.

create or replace function public.subscription_summary()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select s.plan_id, s.status, s.cancel_at_period_end, s.current_period_end,
           s.renewal_product_id
      from user_subscriptions s
     where s.user_id = auth.uid()
     limit 1
  ),
  pending as (
    select p.id as plan_id, me.current_period_end as starts_at,
           p.monthly_seconds, p.monthly_scenes, p.talk_unlimited
      from me
      join subscription_plans p on p.apple_product_id = me.renewal_product_id
     where me.status in ('active', 'grace', 'trialing')
       and not coalesce(me.cancel_at_period_end, false)
       and p.id <> me.plan_id
       and me.current_period_end is not null
     limit 1
  ),
  notes as (
    select n.texts
      from subscription_notes n
     where (n.user_id = auth.uid() or n.user_id is null)
       and n.starts_at <= now()
       and (n.ends_at is null or n.ends_at > now())
     order by n.user_id nulls last, n.created_at desc
     limit 3
  )
  select jsonb_build_object(
    'pending', (select to_jsonb(pending) from pending),
    'notes', coalesce((select jsonb_agg(texts) from notes), '[]'::jsonb)
  )
  where auth.uid() is not null;
$$;

revoke all on function public.subscription_summary() from public, anon;
grant execute on function public.subscription_summary() to authenticated;
