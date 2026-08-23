-- Cost measurement: turn usage_ledger into something margin can be computed
-- from. Everything here is ADDITIVE — no existing table, function or policy
-- changes behaviour, because this ships days before launch.
--
-- The problem it solves: the ledger already writes one row per provider call
-- (0-delta rows included), but it records what we CHARGED, not what we PAID.
-- ElevenLabs rows carried `chars` without the model — and the fidelity model
-- costs ~2x per char, so characters could not be turned into money. Gemini
-- rows carried nothing at all: no token counts, so "~$0.002/call" was an
-- assumption from before gen-3, before growing conversation history was resent
-- on every turn, and before the transcribe call started attaching audio.
--
-- Three pieces:
--   1) record_provider_usage — lets an Edge Function fill in the cost drivers
--      it only learns AFTER the upstream call returns (token counts).
--   2) provider_rates — units → USD, versioned by date, so a price change is
--      an INSERT and old periods keep being costed at the old rate.
--   3) views that join the two, plus the revenue side from Apple.
--
-- Design rule throughout: a MISSING RATE MUST NOT READ AS ZERO. Unpriced
-- usage surfaces as NULL and is counted by `unpriced_usage`, because a
-- silent zero is how a dashboard tells you your margin is fine.

-- ---------------------------------------------------------------------------
-- 0) Global date index. The existing index is (user_id, created_at) — good
--    for a user's own receipt, useless for "what did last week cost", which
--    is every query on this page.
-- ---------------------------------------------------------------------------

create index if not exists usage_ledger_created_idx
  on public.usage_ledger(created_at desc);

-- ---------------------------------------------------------------------------
-- 1) Late-arriving cost drivers.
--
--    Token counts are known only after the model has answered, and for a
--    streamed turn only after the last SSE event. The ledger row was already
--    written before the upstream call (that ordering is deliberate — it's
--    what makes the charge survive a crash), so the numbers are MERGED into
--    the row it already has, keyed by its unique idempotency_key.
--
--    Merge, never replace: the row's billing metadata is authoritative and
--    must survive. Service-role only, like every other billing primitive.
-- ---------------------------------------------------------------------------

create or replace function public.record_provider_usage(
  p_idempotency_key text,
  p_usage jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_idempotency_key is null or p_usage is null then return; end if;
  update public.usage_ledger
     set metadata = coalesce(metadata, '{}'::jsonb) || p_usage
   where idempotency_key = p_idempotency_key;
end;
$$;

-- Server-only, like every other billing primitive (20260814140000). The
-- service_role grant is not optional: revoke-from-public strips it too, and
-- the Edge Function calls this through billingClient() — without the grant
-- the token capture would fail silently and the ledger would look exactly as
-- empty as it does today.
revoke all on function public.record_provider_usage(text, jsonb) from public, anon, authenticated;
grant execute on function public.record_provider_usage(text, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 2) Rate card.
--
--    (provider, model, unit) → USD, versioned. `effective_from` is what makes
--    a provider price change safe: yesterday is still costed at yesterday's
--    rate instead of being quietly rewritten.
-- ---------------------------------------------------------------------------

create table if not exists public.provider_rates (
  provider       text not null,          -- 'elevenlabs' | 'gemini' | 'apple'
  model          text not null,          -- model id, or '*' where the rate is model-blind
  unit           text not null,          -- 'char' | 'input_token' | 'output_token' | …
  usd_per_unit   numeric(24,14) not null,
  effective_from timestamptz not null default now(),
  note           text,
  primary key (provider, model, unit, effective_from)
);

alter table public.provider_rates enable row level security;
-- Our cost structure. No client has any business reading it.
revoke all on public.provider_rates from anon, authenticated;

comment on table public.provider_rates is
  'Upstream unit prices in USD, versioned by effective_from. VERIFY THE SEEDED '
  'VALUES against the current ElevenLabs plan and Google pricing page before '
  'trusting any margin number — they are seeded as a starting point, not as '
  'measured fact.';

-- ElevenLabs bills in CREDITS, and the per-credit price is a property of our
-- subscription tier, not of the model. The model only decides credits/char:
-- multilingual_v2 is 1.0, turbo/flash are 0.5. Keeping that ratio in one
-- place means a tier upgrade is one function call, not three hand-edited rows
-- that can drift apart.
create or replace function public.set_elevenlabs_usd_per_credit(
  p_usd_per_credit numeric,
  p_effective_from timestamptz default now(),
  p_note text default null
) returns void
language sql
as $$
  insert into public.provider_rates (provider, model, unit, usd_per_unit, effective_from, note)
  values
    ('elevenlabs', 'eleven_multilingual_v2', 'char', p_usd_per_credit * 1.0, p_effective_from, p_note),
    ('elevenlabs', 'eleven_turbo_v2_5',      'char', p_usd_per_credit * 0.5, p_effective_from, p_note),
    ('elevenlabs', 'eleven_flash_v2_5',      'char', p_usd_per_credit * 0.5, p_effective_from, p_note)
  on conflict (provider, model, unit, effective_from) do update
    set usd_per_unit = excluded.usd_per_unit, note = excluded.note;
$$;

revoke all on function public.set_elevenlabs_usd_per_credit(numeric, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.set_elevenlabs_usd_per_credit(numeric, timestamptz, text)
  to service_role;

-- Seed. effective_from is deliberately far in the past so every historical
-- ledger row gets costed by it.
--
-- ElevenLabs: seeded at the Creator tier ($22 / 100k credits = $0.00022 per
-- credit). Re-run set_elevenlabs_usd_per_credit() the day the tier changes.
select public.set_elevenlabs_usd_per_credit(
  0.00022, timestamptz '2026-01-01', 'seed: Creator tier $22/100k credits — VERIFY');

-- Gemini. Prices are per TOKEN (list prices are per 1M).
--   * `thought_token` is billed at the output rate.
--   * `audio_input_token` is a separate, higher input rate — this is the one
--     that matters here, because the per-turn transcribe call attaches audio
--     and audio runs ~32 tokens per second of speech.
-- gen-3 figures are seeded from the 2.5-flash card as a STAND-IN. Replace
-- them with the real numbers before reading any margin off this.
insert into public.provider_rates (provider, model, unit, usd_per_unit, effective_from, note) values
  ('gemini','gemini-3.6-flash','input_token',        0.30/1000000, timestamptz '2026-01-01','seed from 2.5-flash — VERIFY'),
  ('gemini','gemini-3.6-flash','output_token',       2.50/1000000, timestamptz '2026-01-01','seed from 2.5-flash — VERIFY'),
  ('gemini','gemini-3.6-flash','thought_token',      2.50/1000000, timestamptz '2026-01-01','thinking billed as output — VERIFY'),
  ('gemini','gemini-3.6-flash','audio_input_token',  1.00/1000000, timestamptz '2026-01-01','seed from 2.5-flash — VERIFY'),
  ('gemini','gemini-3.6-flash','cached_input_token', 0.075/1000000,timestamptz '2026-01-01','seed from 2.5-flash — VERIFY'),
  ('gemini','gemini-3.1-flash-lite','input_token',       0.10/1000000, timestamptz '2026-01-01','seed from 2.5-flash-lite — VERIFY'),
  ('gemini','gemini-3.1-flash-lite','output_token',      0.40/1000000, timestamptz '2026-01-01','seed from 2.5-flash-lite — VERIFY'),
  ('gemini','gemini-3.1-flash-lite','thought_token',     0.40/1000000, timestamptz '2026-01-01','thinking billed as output — VERIFY'),
  ('gemini','gemini-3.1-flash-lite','audio_input_token', 0.30/1000000, timestamptz '2026-01-01','seed from 2.5-flash-lite — VERIFY'),
  ('gemini','gemini-3.1-flash-lite','cached_input_token',0.025/1000000,timestamptz '2026-01-01','seed from 2.5-flash-lite — VERIFY'),
  ('gemini','gemini-2.5-flash','input_token',        0.30/1000000, timestamptz '2026-01-01','list price'),
  ('gemini','gemini-2.5-flash','output_token',       2.50/1000000, timestamptz '2026-01-01','list price'),
  ('gemini','gemini-2.5-flash','thought_token',      2.50/1000000, timestamptz '2026-01-01','thinking billed as output'),
  ('gemini','gemini-2.5-flash','audio_input_token',  1.00/1000000, timestamptz '2026-01-01','list price'),
  ('gemini','gemini-2.5-flash','cached_input_token', 0.075/1000000,timestamptz '2026-01-01','list price'),
  -- Apple's cut, as a fraction of gross. 0.15 = Small Business Program.
  ('apple','*','commission_fraction', 0.15, timestamptz '2026-01-01','Small Business Program — 0.30 if not enrolled')
on conflict (provider, model, unit, effective_from) do nothing;

-- ---------------------------------------------------------------------------
-- 3) Revenue: what Apple actually charged, per transaction.
--
--    apple-webhook already verifies signedTransactionInfo and then throws the
--    money away. `price` (milliunits of `currency`) is the only honest revenue
--    figure we can get — it survives storefront pricing, intro offers and
--    currency, none of which a hardcoded plan price knows about.
-- ---------------------------------------------------------------------------

create table if not exists public.subscription_transactions (
  transaction_id          text primary key,
  original_transaction_id text,
  user_id                 uuid references auth.users(id) on delete set null,
  plan_id                 text references public.subscription_plans(id),
  apple_product_id        text,
  price_milliunits        bigint,        -- Apple's `price`: 9990 == 9.99
  currency                text,          -- ISO 4217
  purchase_date           timestamptz,
  expires_date            timestamptz,
  is_trial                boolean not null default false,
  is_upgrade              boolean not null default false,
  revocation_date         timestamptz,
  notification_type       text,
  subtype                 text,
  environment             text,          -- 'Sandbox' | 'Production'
  created_at              timestamptz not null default now()
);
create index if not exists subscription_transactions_user_idx
  on public.subscription_transactions(user_id, purchase_date desc);
create index if not exists subscription_transactions_purchase_idx
  on public.subscription_transactions(purchase_date desc);

alter table public.subscription_transactions enable row level security;
revoke all on public.subscription_transactions from anon, authenticated;

-- How many seconds of talk one `talk_time` ledger row represents. See the
-- comment in `user_daily_usage` for why there are two answers.
create or replace function public.talk_row_seconds(p_metadata jsonb, p_delta integer)
returns numeric
language sql
immutable
as $$
  select case
    when jsonb_typeof(p_metadata->'seconds') = 'number'
      then (p_metadata->>'seconds')::numeric
    when p_delta < 0 then (-p_delta)::numeric
    else 0
  end;
$$;

-- ---------------------------------------------------------------------------
-- 4) Cost views.
-- ---------------------------------------------------------------------------

-- One row per (ledger row × cost driver). A ledger row fans out into several
-- components — a Gemini call has input, output, thinking and audio tokens,
-- each at its own rate — which is why cost cannot be a column on the ledger.
--
-- Candidates are emitted unconditionally and filtered by whether the driver
-- is actually present in the metadata, so a new source_fn writing recognized
-- keys is picked up with no change here. `jsonb_typeof(...) = 'number'` is
-- the cast guard: a malformed string can never abort the whole view.
create or replace view public.usage_cost_component as
select
  l.id                                          as ledger_id,
  l.user_id,
  l.created_at,
  l.action,
  l.source_fn,
  coalesce(l.metadata->>'purpose', 'unknown')   as purpose,
  c.provider,
  c.model,
  c.unit,
  c.qty,
  r.usd_per_unit,
  c.qty * r.usd_per_unit                        as usd
from public.usage_ledger l
cross join lateral (
  values
    -- ElevenLabs characters. `model_id` was only added to the metadata on
    -- 2026-08-23, so older rows are back-filled from the purpose using the
    -- SAME rule the function applies (FIDELITY_PURPOSES in
    -- supabase/functions/elevenlabs-tts). This is not a detail: the fidelity
    -- model bills 1 credit/char against turbo's 0.5, so defaulting everything
    -- to turbo halved the measured cost of every Watch scene — the most
    -- expensive thing the product does per unit.
    ('elevenlabs',
     coalesce(
       l.metadata->>'model_id',
       case when l.metadata->>'purpose' in ('scene','greeting','voice_comparison')
            then 'eleven_multilingual_v2'
            else 'eleven_turbo_v2_5' end),
     'char',
     case when jsonb_typeof(l.metadata->'chars') = 'number'
          then (l.metadata->>'chars')::numeric end),
    ('gemini', coalesce(l.metadata->>'model','unknown'), 'input_token',
     case when jsonb_typeof(l.metadata->'prompt_tokens') = 'number'
          then (l.metadata->>'prompt_tokens')::numeric end),
    ('gemini', coalesce(l.metadata->>'model','unknown'), 'output_token',
     case when jsonb_typeof(l.metadata->'output_tokens') = 'number'
          then (l.metadata->>'output_tokens')::numeric end),
    ('gemini', coalesce(l.metadata->>'model','unknown'), 'thought_token',
     case when jsonb_typeof(l.metadata->'thought_tokens') = 'number'
          then (l.metadata->>'thought_tokens')::numeric end),
    ('gemini', coalesce(l.metadata->>'model','unknown'), 'audio_input_token',
     case when jsonb_typeof(l.metadata->'audio_input_tokens') = 'number'
          then (l.metadata->>'audio_input_tokens')::numeric end),
    ('gemini', coalesce(l.metadata->>'model','unknown'), 'cached_input_token',
     case when jsonb_typeof(l.metadata->'cached_input_tokens') = 'number'
          then (l.metadata->>'cached_input_tokens')::numeric end)
) as c(provider, model, unit, qty)
left join lateral (
  select pr.usd_per_unit
  from public.provider_rates pr
  where pr.provider = c.provider
    and pr.model = c.model
    and pr.unit = c.unit
    and pr.effective_from <= l.created_at
  order by pr.effective_from desc
  limit 1
) r on true
where c.qty is not null and c.qty > 0;

revoke all on public.usage_cost_component from anon, authenticated;

-- Per ledger row. `has_unpriced` is load-bearing: sum() skips NULLs, so a row
-- whose model has no rate would otherwise look cheap rather than unknown.
create or replace view public.usage_cost as
select
  ledger_id, user_id, created_at, action, source_fn, purpose,
  sum(usd)                       as usd,
  bool_or(usd_per_unit is null)  as has_unpriced
from public.usage_cost_component
group by 1,2,3,4,5,6;

revoke all on public.usage_cost from anon, authenticated;

-- Anything being consumed that we have no price for. Should be empty. If it
-- isn't, every margin number below is understated by exactly this much.
create or replace view public.unpriced_usage as
select provider, model, unit,
       count(*)     as rows,
       sum(qty)     as units,
       min(created_at) as first_seen,
       max(created_at) as last_seen
from public.usage_cost_component
where usd_per_unit is null
group by 1,2,3
order by units desc;

revoke all on public.unpriced_usage from anon, authenticated;

-- The daily fact table everything else reads. Cost, the usage that caused it,
-- and the talk seconds we actually charged for — side by side, so cost per
-- delivered minute is a division rather than a join.
create or replace view public.user_daily_usage as
with cost as (
  select user_id, created_at::date as day,
    sum(usd) filter (where provider = 'elevenlabs')        as elevenlabs_usd,
    sum(usd) filter (where provider = 'gemini')            as gemini_usd,
    sum(usd)                                               as total_usd,
    bool_or(usd_per_unit is null)                          as has_unpriced,
    sum(qty) filter (where unit = 'char')                  as tts_chars,
    sum(qty) filter (where unit = 'input_token')           as gemini_input_tokens,
    sum(qty) filter (where unit = 'output_token')          as gemini_output_tokens,
    sum(qty) filter (where unit = 'thought_token')         as gemini_thought_tokens,
    sum(qty) filter (where unit = 'audio_input_token')     as gemini_audio_tokens
  from public.usage_cost_component
  group by 1,2
),
talk as (
  -- The ledger, not talk_seconds_by_language: that table is only written when
  -- the client sends a language, so it under-counts by construction.
  --
  -- Two ways a talk_time row states its seconds, and both are needed. An
  -- ENTITLED account's row carries metadata.seconds (consume_metered_seconds
  -- writes it); a free / legacy-balance account falls through to
  -- charge_credits, which records the spend only as a negative delta — and
  -- since the balance IS denominated in seconds, that delta is the same
  -- number. Reading only the first missed most accounts on the tier that
  -- still has a balance.
  select user_id, created_at::date as day,
         sum(public.talk_row_seconds(metadata, delta)) as talk_seconds
  from public.usage_ledger
  where action = 'talk_time'
  group by 1,2
),
scenes as (
  select user_id, day, count(*) as scenes
  from public.scene_plays
  group by 1,2
)
select
  coalesce(c.user_id, t.user_id, s.user_id)   as user_id,
  coalesce(c.day, t.day, s.day)               as day,
  coalesce(c.elevenlabs_usd, 0)               as elevenlabs_usd,
  coalesce(c.gemini_usd, 0)                   as gemini_usd,
  coalesce(c.total_usd, 0)                    as total_usd,
  coalesce(c.has_unpriced, false)             as has_unpriced,
  coalesce(c.tts_chars, 0)                    as tts_chars,
  coalesce(c.gemini_input_tokens, 0)          as gemini_input_tokens,
  coalesce(c.gemini_output_tokens, 0)         as gemini_output_tokens,
  coalesce(c.gemini_thought_tokens, 0)        as gemini_thought_tokens,
  coalesce(c.gemini_audio_tokens, 0)          as gemini_audio_tokens,
  coalesce(t.talk_seconds, 0)                 as talk_seconds,
  coalesce(s.scenes, 0)                       as scenes
from cost c
full join talk t   on t.user_id = c.user_id and t.day = c.day
full join scenes s on s.user_id = coalesce(c.user_id, t.user_id)
                  and s.day = coalesce(c.day, t.day);

revoke all on public.user_daily_usage from anon, authenticated;

-- Who a user_id belongs to, for the analysis page.
--
-- Sign-in is Apple, so `auth.users.email` is almost always a private-relay
-- address — `chjnp8wmyg@privaterelay.appleid.com` identifies nobody. Apple
-- returns a real name exactly once, on first authorization, and the app keeps
-- it on the DEVICE (AuthService.appleNameKey) to prefill persona setup; it is
-- never sent here, and it should stay that way.
--
-- So the server-side name is the one the learner published themselves:
-- `public_personas.display_name`, auto-synced from their onboarding persona.
-- It costs nothing, needs no app change, and works for every existing account.
-- Where there is no persona the label degrades to the email's local part and
-- finally to a short id, so a row always has something a human can read.
create or replace view public.user_directory as
select
  au.id                                   as user_id,
  au.email,
  p.display_name,
  coalesce(
    nullif(p.display_name, ''),
    nullif(split_part(coalesce(au.email, ''), '@', 1), ''),
    left(au.id::text, 8)
  )                                       as label,
  -- A relay address is not a way to reach anyone; say so rather than letting
  -- the page imply we have a mailbox.
  (au.email like '%@privaterelay.appleid.com') as email_is_relay,
  au.created_at                           as signed_up_at,
  s.plan_id,
  s.status                                as subscription_status
from auth.users au
left join lateral (
  -- Newest active persona. A learner with several target languages has one
  -- row per language and the same name on each, so which one wins is moot.
  select pp.display_name
  from public.public_personas pp
  where pp.owner_user_id = au.id and pp.is_active
  order by pp.updated_at desc
  limit 1
) p on true
left join public.user_subscriptions s on s.user_id = au.id;

revoke all on public.user_directory from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) The three numbers a subscription tier is actually designed from.
-- ---------------------------------------------------------------------------

-- (a) What one delivered talk minute costs us, by month. Talk-attributable
--     spend only — scene audio is excluded on both sides so the two products
--     don't launder each other's cost.
create or replace view public.cost_per_talk_minute as
with talk_cost as (
  select date_trunc('month', created_at)::date as month,
         sum(usd)                              as talk_usd,
         bool_or(usd_per_unit is null)         as has_unpriced
  from public.usage_cost_component
  where purpose <> 'scene' and action <> 'tts_scene'
  group by 1
),
talk_min as (
  select date_trunc('month', created_at)::date              as month,
         sum(public.talk_row_seconds(metadata, delta))/60.0 as talk_minutes
  from public.usage_ledger
  where action = 'talk_time'
  group by 1
)
select
  coalesce(c.month, m.month)                  as month,
  coalesce(c.talk_usd, 0)                     as talk_usd,
  coalesce(m.talk_minutes, 0)                 as talk_minutes,
  c.talk_usd / nullif(m.talk_minutes, 0)      as usd_per_talk_minute,
  coalesce(c.has_unpriced, false)             as has_unpriced
from talk_cost c
full join talk_min m on m.month = c.month
order by 1 desc;

revoke all on public.cost_per_talk_minute from anon, authenticated;

-- (b) What one Watch scene costs us. A scene is claimed once and can play
--     many lines, so the denominator is scene_plays, not TTS calls.
create or replace view public.cost_per_scene as
with scene_cost as (
  select date_trunc('month', created_at)::date as month,
         sum(usd)                              as scene_usd,
         bool_or(usd_per_unit is null)         as has_unpriced
  from public.usage_cost_component
  where purpose = 'scene' or action = 'tts_scene'
  group by 1
),
scene_count as (
  select date_trunc('month', created_at)::date as month,
         count(*)                              as scenes
  from public.scene_plays
  group by 1
)
select
  coalesce(c.month, n.month)              as month,
  coalesce(c.scene_usd, 0)                as scene_usd,
  coalesce(n.scenes, 0)                   as scenes,
  c.scene_usd / nullif(n.scenes, 0)       as usd_per_scene,
  coalesce(c.has_unpriced, false)         as has_unpriced
from scene_cost c
full join scene_count n on n.month = c.month
order by 1 desc;

revoke all on public.cost_per_scene from anon, authenticated;

-- (c) The distribution, per plan. A tier is priced against its TAIL, not its
--     mean — the p95 user is the one who decides whether the plan loses money,
--     and an average hides them completely.
create or replace view public.usage_distribution_by_plan as
with monthly as (
  select u.user_id,
         date_trunc('month', u.day)::date as month,
         coalesce(s.plan_id, 'free')      as plan_id,
         sum(u.talk_seconds) / 60.0       as talk_minutes,
         sum(u.scenes)                    as scenes,
         sum(u.total_usd)                 as usd
  from public.user_daily_usage u
  left join public.user_subscriptions s on s.user_id = u.user_id
  group by 1,2,3
)
select
  month, plan_id,
  count(*)                                                              as users,
  round(avg(talk_minutes)::numeric, 1)                                  as talk_min_avg,
  round(percentile_cont(0.5) within group (order by talk_minutes)::numeric, 1)  as talk_min_p50,
  round(percentile_cont(0.9) within group (order by talk_minutes)::numeric, 1)  as talk_min_p90,
  round(percentile_cont(0.95) within group (order by talk_minutes)::numeric, 1) as talk_min_p95,
  round(max(talk_minutes)::numeric, 1)                                  as talk_min_max,
  round(percentile_cont(0.5) within group (order by scenes)::numeric, 1)        as scenes_p50,
  round(percentile_cont(0.95) within group (order by scenes)::numeric, 1)       as scenes_p95,
  round(avg(usd)::numeric, 4)                                           as usd_avg,
  round(percentile_cont(0.95) within group (order by usd)::numeric, 4)  as usd_p95,
  round(max(usd)::numeric, 4)                                           as usd_max
from monthly
group by 1,2
order by 1 desc, 2;

revoke all on public.usage_distribution_by_plan from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6) Margin. Revenue net of Apple's cut, minus measured cost.
-- ---------------------------------------------------------------------------

-- Apple's cut is looked up per TRANSACTION (at its purchase date) before any
-- aggregation, so a commission change — enrolling in the Small Business
-- Program, or leaving it — splits cleanly down the middle of a month.
create or replace view public.paid_transaction as
select
  t.*,
  coalesce(r.usd_per_unit, 0.15)                              as commission,
  t.price_milliunits / 1000.0                                 as gross,
  t.price_milliunits / 1000.0 * (1 - coalesce(r.usd_per_unit, 0.15)) as net
from public.subscription_transactions t
left join lateral (
  select pr.usd_per_unit
  from public.provider_rates pr
  where pr.provider = 'apple' and pr.unit = 'commission_fraction'
    and pr.effective_from <= t.purchase_date
  order by pr.effective_from desc
  limit 1
) r on true
where t.revocation_date is null
  and coalesce(t.environment, 'Production') = 'Production'
  and not t.is_trial;

revoke all on public.paid_transaction from anon, authenticated;

create or replace view public.revenue_by_month as
select
  date_trunc('month', purchase_date)::date as month,
  plan_id,
  currency,
  count(*)     as transactions,
  sum(gross)   as gross,
  sum(net)     as net
from public.paid_transaction
group by 1,2,3
order by 1 desc;

revoke all on public.revenue_by_month from anon, authenticated;

-- Per user, per month. `net_revenue` is in the transaction's own CURRENCY —
-- deliberately not converted to USD, because there is no FX rate here and an
-- invented one would make margin look precise while being wrong. Filter to a
-- single currency, or add an fx table later.
create or replace view public.margin_by_user_month as
with cost as (
  select user_id, date_trunc('month', day)::date as month,
         sum(total_usd)          as cost_usd,
         sum(talk_seconds)/60.0  as talk_minutes,
         sum(scenes)             as scenes,
         bool_or(has_unpriced)   as has_unpriced
  from public.user_daily_usage
  group by 1,2
),
rev as (
  select user_id, date_trunc('month', purchase_date)::date as month,
         min(currency) as currency,
         sum(net)      as net_revenue
  from public.paid_transaction
  group by 1,2
)
select
  coalesce(c.user_id, r.user_id)  as user_id,
  coalesce(c.month, r.month)      as month,
  coalesce(r.net_revenue, 0)      as net_revenue,
  r.currency,
  coalesce(c.cost_usd, 0)         as cost_usd,
  coalesce(r.net_revenue, 0) - coalesce(c.cost_usd, 0) as margin,
  coalesce(c.talk_minutes, 0)     as talk_minutes,
  coalesce(c.scenes, 0)           as scenes,
  coalesce(c.has_unpriced, false) as has_unpriced
from cost c
full join rev r on r.user_id = c.user_id and r.month = c.month;

revoke all on public.margin_by_user_month from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7) Waste: spend that bought nothing.
--
--    A speculative reply that isn't adopted still cost Gemini tokens. It is
--    latency bought with money, and the exchange rate should be visible
--    rather than assumed — `spec` is tagged by the client on the turn call.
-- ---------------------------------------------------------------------------

create or replace view public.speculative_waste as
select
  date_trunc('day', l.created_at)::date as day,
  count(*) filter (where l.metadata->>'spec' = 'true')  as spec_calls,
  count(*) filter (where l.metadata->>'spec' is null
                      or l.metadata->>'spec' = 'false') as normal_calls,
  sum(uc.usd) filter (where l.metadata->>'spec' = 'true') as spec_usd
from public.usage_ledger l
left join public.usage_cost uc on uc.ledger_id = l.id
where l.source_fn = 'gemini' and l.metadata->>'purpose' = 'turn'
group by 1
order by 1 desc;

revoke all on public.speculative_waste from anon, authenticated;
