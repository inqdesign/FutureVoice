-- ---------------------------------------------------------------------------
-- The free offer as a SETTING, not a constant (2026-10-21).
--
-- Founder: free minutes, whether there are any, and whether a trial is
-- offered must be changeable at any time without a build. Until now the free
-- minutes were a constant inside `handle_new_user_credits` (a migration per
-- change, five of them since August) and a second copy in the app
-- (`AccountStatus.freeGrantSeconds`), and where a trial is offered was code.
--
-- One row, readable by everyone (it is the offer, not a secret), written only
-- by the founder through `scripts/billing-switch.py`.
--
--   free_talk_seconds  what a NEW account starts with. 0 = no free minutes:
--                      the first paid tap meets the plans. Existing accounts
--                      are never touched by a change here; topping them up is
--                      a separate, deliberate step (see the script).
--   trial_offer_at     where the app offers the store's free trial, when the
--                      store has one switched on:
--                        'after_free'  the plans meet the learner when the
--                                      free minutes run out (today)
--                        'onboarding'  once, right after onboarding, to an
--                                      account under two days old that has
--                                      never subscribed
--                      The trial itself is the store's switch (ASC intro offer,
--                      Play offer), flipped by the same script.
--
-- The defaults ARE today's behaviour: 1200 s, after_free.
-- ---------------------------------------------------------------------------

create table if not exists public.billing_config (
  id                boolean primary key default true check (id),
  free_talk_seconds integer not null default 1200
                    check (free_talk_seconds between 0 and 36000),
  trial_offer_at    text not null default 'after_free'
                    check (trial_offer_at in ('after_free', 'onboarding')),
  updated_at        timestamptz not null default now()
);

insert into public.billing_config (id) values (true) on conflict (id) do nothing;

alter table public.billing_config enable row level security;

drop policy if exists billing_config_read on public.billing_config;
create policy billing_config_read on public.billing_config
  for select to anon, authenticated using (true);

grant select on public.billing_config to anon, authenticated;

-- The signup grant reads the row. A missing row (or a database restored
-- without it) falls back to the last constant, so a sign-up can never fail
-- on a setting.
create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
declare
  free_talk_seconds integer;
begin
  select c.free_talk_seconds into free_talk_seconds
    from public.billing_config c where c.id;
  free_talk_seconds := coalesce(free_talk_seconds, 1200);

  insert into public.user_credits (user_id, balance, updated_at)
  values (new.id, free_talk_seconds, now())
  on conflict (user_id) do nothing;
  return new;
end;
$$;
