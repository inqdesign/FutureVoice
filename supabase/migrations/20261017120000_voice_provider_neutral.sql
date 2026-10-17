-- The voice provider is Cartesia, and the schema stops naming the one before
-- it (2026-10-17).
--
-- 1. `voice_clones.voice_id` is the provider's voice id. The old column stays
--    for builds already in the store, which read it by name, and a trigger
--    keeps the two equal whichever one a writer sets. Drop the old column
--    once no build below the first one that reads `voice_id` is in use.
-- 2. TTS ledger rows written before `model_id` was recorded get the model the
--    server used for them, so the cost view needs no guess.
-- 3. Cartesia gets a rate. Every TTS row since 2026-10-12 says `sonic-3.6`,
--    and with no rate for it the cost view priced them at nothing.
-- 4. The cost views name the provider from `provider_rates` and report
--    `tts_usd`; `admin_raw` follows.
-- 5. The default-accent backfill and its rate setter are gone with the code
--    that called them.

-- 1 ---------------------------------------------------------------------------
alter table public.voice_clones add column if not exists voice_id text;
update public.voice_clones set voice_id = elevenlabs_voice_id where voice_id is null;

create or replace function public.voice_clones_sync_voice_id()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.voice_id := coalesce(new.voice_id, new.elevenlabs_voice_id);
  elsif new.voice_id is not distinct from old.voice_id
        and new.elevenlabs_voice_id is distinct from old.elevenlabs_voice_id then
    new.voice_id := new.elevenlabs_voice_id;   -- an older writer moved the old name
  end if;
  new.elevenlabs_voice_id := new.voice_id;
  return new;
end $$;

drop trigger if exists voice_clones_sync_voice_id on public.voice_clones;
create trigger voice_clones_sync_voice_id
  before insert or update on public.voice_clones
  for each row execute function public.voice_clones_sync_voice_id();

alter table public.voice_clones alter column voice_id set not null;
create index if not exists voice_clones_voice_id_idx on public.voice_clones (voice_id);

create or replace view public.user_directory as
 SELECT au.id AS user_id,
    au.email,
    p.display_name,
    COALESCE(NULLIF(p.display_name, ''::text), NULLIF(split_part(COALESCE(au.email, ''::character varying)::text, '@'::text, 1), ''::text), "left"(au.id::text, 8)) AS label,
    au.email::text ~~ '%@privaterelay.appleid.com'::text AS email_is_relay,
    au.created_at AS signed_up_at,
    s.plan_id,
    s.status AS subscription_status,
        CASE
            WHEN s.user_id IS NULL THEN 'none'::text
            WHEN s.status = 'trialing'::text AND s.cancel_at_period_end THEN 'trial·cancelled'::text
            WHEN s.status = 'trialing'::text THEN 'trial'::text
            WHEN s.status = 'active'::text AND s.cancel_at_period_end THEN 'cancelled'::text
            WHEN s.status = 'active'::text THEN 'active'::text
            ELSE s.status
        END AS subscription_state,
    s.cancel_at_period_end,
    s.started_at AS subscribed_at,
    s.trial_ends_at,
    s.current_period_end,
    s.source AS subscription_source,
    s.updated_at AS subscription_updated_at,
    au.last_sign_in_at,
    p.location,
    p.language AS persona_language,
    COALESCE(au.is_anonymous, false) AS is_anonymous,
    v.voice_id,
    v.name AS voice_name,
    v.is_active AS voice_is_active,
    v.created_at AS voice_cloned_at,
    o.original_saved_at AS voice_original_saved_at,
    o.original_path AS voice_original_path,
    vc.takes AS voice_takes
   FROM auth.users au
     LEFT JOIN LATERAL ( SELECT pp.display_name,
            pp.location,
            pp.language
           FROM public_personas pp
          WHERE pp.owner_user_id = au.id AND pp.is_active
          ORDER BY pp.updated_at DESC
         LIMIT 1) p ON true
     LEFT JOIN user_subscriptions s ON s.user_id = au.id
     LEFT JOIN LATERAL ( SELECT c.voice_id,
            c.name,
            c.is_active,
            c.created_at
           FROM voice_clones c
          WHERE c.user_id = au.id
          ORDER BY c.is_active DESC, c.created_at DESC
         LIMIT 1) v ON true
     LEFT JOIN LATERAL ( SELECT c.original_saved_at,
            c.original_path
           FROM voice_clones c
          WHERE c.user_id = au.id AND c.original_path IS NOT NULL
          ORDER BY c.original_saved_at DESC NULLS LAST
         LIMIT 1) o ON true
     LEFT JOIN LATERAL ( SELECT count(*)::integer AS takes
           FROM voice_clones c
          WHERE c.user_id = au.id) vc ON true;

-- 2 ---------------------------------------------------------------------------
-- The rule the old cost view applied at read time, written down once.
update public.usage_ledger
   set metadata = metadata || jsonb_build_object('model_id',
         case when metadata->>'purpose' in ('scene', 'greeting', 'voice_comparison')
              then 'eleven_multilingual_v2' else 'eleven_turbo_v2_5' end)
 where jsonb_typeof(metadata->'chars') = 'number'
   and not (metadata ? 'model_id');

-- 3 ---------------------------------------------------------------------------
-- Cartesia bills one credit per character, clones included (measured
-- 2026-10-11); Startup is $39 per million.
insert into public.provider_rates (provider, model, unit, usd_per_unit, effective_from, note)
values ('cartesia', 'sonic-3.6', 'char', 0.000039, '2026-10-01 00:00:00+00',
        'Startup $39 / 1M chars, 1 credit/char incl. clones (measured 2026-10-11)')
on conflict (provider, model, unit, effective_from) do nothing;

-- 4 ---------------------------------------------------------------------------
create or replace view public.usage_cost_component as
 SELECT l.id AS ledger_id,
    l.user_id,
    l.created_at,
    l.action,
    l.source_fn,
    COALESCE(l.metadata ->> 'purpose'::text, 'unknown'::text) AS purpose,
    c.provider,
    c.model,
    c.unit,
    c.qty,
    r.usd_per_unit,
    c.qty * r.usd_per_unit AS usd
   FROM usage_ledger l
     CROSS JOIN LATERAL ( VALUES
                (COALESCE(( SELECT pr.provider FROM provider_rates pr
                             WHERE pr.unit = 'char'::text AND pr.model = (l.metadata ->> 'model_id'::text)
                             LIMIT 1), 'tts'::text),
                 COALESCE(l.metadata ->> 'model_id'::text, 'unknown'::text),'char'::text,
                CASE
                    WHEN jsonb_typeof(l.metadata -> 'chars'::text) = 'number'::text THEN (l.metadata ->> 'chars'::text)::numeric
                    ELSE NULL::numeric
                END), ('gemini'::text,COALESCE(l.metadata ->> 'model'::text, 'unknown'::text),'input_token'::text,
                CASE
                    WHEN jsonb_typeof(l.metadata -> 'prompt_tokens'::text) = 'number'::text THEN (l.metadata ->> 'prompt_tokens'::text)::numeric
                    ELSE NULL::numeric
                END), ('gemini'::text,COALESCE(l.metadata ->> 'model'::text, 'unknown'::text),'output_token'::text,
                CASE
                    WHEN jsonb_typeof(l.metadata -> 'output_tokens'::text) = 'number'::text THEN (l.metadata ->> 'output_tokens'::text)::numeric
                    ELSE NULL::numeric
                END), ('gemini'::text,COALESCE(l.metadata ->> 'model'::text, 'unknown'::text),'thought_token'::text,
                CASE
                    WHEN jsonb_typeof(l.metadata -> 'thought_tokens'::text) = 'number'::text THEN (l.metadata ->> 'thought_tokens'::text)::numeric
                    ELSE NULL::numeric
                END), ('gemini'::text,COALESCE(l.metadata ->> 'model'::text, 'unknown'::text),'audio_input_token'::text,
                CASE
                    WHEN jsonb_typeof(l.metadata -> 'audio_input_tokens'::text) = 'number'::text THEN (l.metadata ->> 'audio_input_tokens'::text)::numeric
                    ELSE NULL::numeric
                END), ('gemini'::text,COALESCE(l.metadata ->> 'model'::text, 'unknown'::text),'cached_input_token'::text,
                CASE
                    WHEN jsonb_typeof(l.metadata -> 'cached_input_tokens'::text) = 'number'::text THEN (l.metadata ->> 'cached_input_tokens'::text)::numeric
                    ELSE NULL::numeric
                END)) c(provider, model, unit, qty)
     LEFT JOIN LATERAL ( SELECT pr.usd_per_unit
           FROM provider_rates pr
          WHERE pr.provider = c.provider AND pr.model = c.model AND pr.unit = c.unit AND pr.effective_from <= l.created_at
          ORDER BY pr.effective_from DESC
         LIMIT 1) r ON true
  WHERE c.qty IS NOT NULL AND c.qty > 0::numeric;

-- A column is renamed, so the view and the two built on it are remade.
drop view if exists public.usage_distribution_by_plan;
drop view if exists public.margin_by_user_month;
drop view if exists public.user_daily_usage;

create view public.user_daily_usage as
 WITH cost AS (
         SELECT usage_cost_component.user_id,
            usage_cost_component.created_at::date AS day,
            sum(usage_cost_component.usd) FILTER (WHERE usage_cost_component.unit = 'char'::text) AS tts_usd,
            sum(usage_cost_component.usd) FILTER (WHERE usage_cost_component.provider = 'gemini'::text) AS gemini_usd,
            sum(usage_cost_component.usd) AS total_usd,
            bool_or(usage_cost_component.usd_per_unit IS NULL) AS has_unpriced,
            sum(usage_cost_component.qty) FILTER (WHERE usage_cost_component.unit = 'char'::text) AS tts_chars,
            sum(usage_cost_component.qty) FILTER (WHERE usage_cost_component.unit = 'input_token'::text) AS gemini_input_tokens,
            sum(usage_cost_component.qty) FILTER (WHERE usage_cost_component.unit = 'output_token'::text) AS gemini_output_tokens,
            sum(usage_cost_component.qty) FILTER (WHERE usage_cost_component.unit = 'thought_token'::text) AS gemini_thought_tokens,
            sum(usage_cost_component.qty) FILTER (WHERE usage_cost_component.unit = 'audio_input_token'::text) AS gemini_audio_tokens
           FROM usage_cost_component
          GROUP BY usage_cost_component.user_id, (usage_cost_component.created_at::date)
        ), talk AS (
         SELECT usage_ledger.user_id,
            usage_ledger.created_at::date AS day,
            sum(talk_row_seconds(usage_ledger.metadata, usage_ledger.delta)) AS talk_seconds
           FROM usage_ledger
          WHERE usage_ledger.action = 'talk_time'::text
          GROUP BY usage_ledger.user_id, (usage_ledger.created_at::date)
        ), scenes AS (
         SELECT scene_plays.user_id,
            scene_plays.day,
            count(*) AS scenes
           FROM scene_plays
          GROUP BY scene_plays.user_id, scene_plays.day
        )
 SELECT COALESCE(c.user_id, t.user_id, s.user_id) AS user_id,
    COALESCE(c.day, t.day, s.day) AS day,
    COALESCE(c.tts_usd, 0::numeric) AS tts_usd,
    COALESCE(c.gemini_usd, 0::numeric) AS gemini_usd,
    COALESCE(c.total_usd, 0::numeric) AS total_usd,
    COALESCE(c.has_unpriced, false) AS has_unpriced,
    COALESCE(c.tts_chars, 0::numeric) AS tts_chars,
    COALESCE(c.gemini_input_tokens, 0::numeric) AS gemini_input_tokens,
    COALESCE(c.gemini_output_tokens, 0::numeric) AS gemini_output_tokens,
    COALESCE(c.gemini_thought_tokens, 0::numeric) AS gemini_thought_tokens,
    COALESCE(c.gemini_audio_tokens, 0::numeric) AS gemini_audio_tokens,
    COALESCE(t.talk_seconds, 0::numeric) AS talk_seconds,
    COALESCE(s.scenes, 0::bigint) AS scenes
   FROM cost c
     FULL JOIN talk t ON t.user_id = c.user_id AND t.day = c.day
     FULL JOIN scenes s ON s.user_id = COALESCE(c.user_id, t.user_id) AND s.day = COALESCE(c.day, t.day);

create view public.margin_by_user_month as
 WITH cost AS (
         SELECT user_daily_usage.user_id,
            (date_trunc('month'::text, (user_daily_usage.day)::timestamp with time zone))::date AS month,
            sum(user_daily_usage.total_usd) AS cost_usd,
            (sum(user_daily_usage.talk_seconds) / 60.0) AS talk_minutes,
            sum(user_daily_usage.scenes) AS scenes,
            bool_or(user_daily_usage.has_unpriced) AS has_unpriced
           FROM user_daily_usage
          GROUP BY user_daily_usage.user_id, ((date_trunc('month'::text, (user_daily_usage.day)::timestamp with time zone))::date)
        ), rev AS (
         SELECT paid_transaction.user_id,
            (date_trunc('month'::text, paid_transaction.purchase_date))::date AS month,
            min(paid_transaction.currency) AS currency,
            sum(paid_transaction.net) AS net_revenue
           FROM paid_transaction
          GROUP BY paid_transaction.user_id, ((date_trunc('month'::text, paid_transaction.purchase_date))::date)
        )
 SELECT COALESCE(c.user_id, r.user_id) AS user_id,
    COALESCE(c.month, r.month) AS month,
    COALESCE(r.net_revenue, (0)::numeric) AS net_revenue,
    r.currency,
    COALESCE(c.cost_usd, (0)::numeric) AS cost_usd,
    (COALESCE(r.net_revenue, (0)::numeric) - COALESCE(c.cost_usd, (0)::numeric)) AS margin,
    COALESCE(c.talk_minutes, (0)::numeric) AS talk_minutes,
    COALESCE(c.scenes, (0)::numeric) AS scenes,
    COALESCE(c.has_unpriced, false) AS has_unpriced
   FROM (cost c
     FULL JOIN rev r ON (((r.user_id = c.user_id) AND (r.month = c.month))));

create view public.usage_distribution_by_plan as
 WITH monthly AS (
         SELECT u.user_id,
            (date_trunc('month'::text, (u.day)::timestamp with time zone))::date AS month,
            COALESCE(s.plan_id, 'free'::text) AS plan_id,
            (sum(u.talk_seconds) / 60.0) AS talk_minutes,
            sum(u.scenes) AS scenes,
            sum(u.total_usd) AS usd
           FROM (user_daily_usage u
             LEFT JOIN user_subscriptions s ON ((s.user_id = u.user_id)))
          GROUP BY u.user_id, ((date_trunc('month'::text, (u.day)::timestamp with time zone))::date), COALESCE(s.plan_id, 'free'::text)
        )
 SELECT month,
    plan_id,
    count(*) AS users,
    round(avg(talk_minutes), 1) AS talk_min_avg,
    round((percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((talk_minutes)::double precision)))::numeric, 1) AS talk_min_p50,
    round((percentile_cont((0.9)::double precision) WITHIN GROUP (ORDER BY ((talk_minutes)::double precision)))::numeric, 1) AS talk_min_p90,
    round((percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((talk_minutes)::double precision)))::numeric, 1) AS talk_min_p95,
    round(max(talk_minutes), 1) AS talk_min_max,
    round((percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((scenes)::double precision)))::numeric, 1) AS scenes_p50,
    round((percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((scenes)::double precision)))::numeric, 1) AS scenes_p95,
    round(avg(usd), 4) AS usd_avg,
    round((percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((usd)::double precision)))::numeric, 4) AS usd_p95,
    round(max(usd), 4) AS usd_max
   FROM monthly
  GROUP BY month, plan_id
  ORDER BY month DESC, plan_id;

-- Server-only, like the views they replace.
revoke all on public.user_daily_usage, public.margin_by_user_month,
              public.usage_distribution_by_plan from anon, authenticated;
grant select on public.user_daily_usage, public.margin_by_user_month,
                public.usage_distribution_by_plan to service_role;

CREATE OR REPLACE FUNCTION public.admin_raw()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with
-- Everything on this page starts the day Talk became the unit of account.
-- 2026-08-10 is where the first `talk_time`, the first `tts_scene` and the
-- first `free_usage_daily` rows all appear. The cost window starts later,
-- when scene_plays began being written — before it, per-scene cost is
-- inflated by scene audio whose plays were never recorded.
w as (select date '2026-09-12' as start,         -- launch day: ACTIVITY
             date '2026-08-14' as cost_start,    -- unit economics
             date '2026-08-10' as cost_history), -- spend + per-user totals

-- First and last reply call per user: "did they ever talk, and when".
talk_bounds as (
  select user_id, min(created_at) as first_talk_at, max(created_at) as last_talk_at
  from public.usage_ledger
  where source_fn = 'gemini' and metadata->>'purpose' = 'turn'
    and coalesce(metadata->>'spec','false') <> 'true'
  group by 1
),


users_raw as (
  select u.id::text                                  as id,
         u.email,
         -- An onboarding session that has not reached Apple sign-in yet (the
         -- voice is cloned and heard BEFORE the account is asked for), or one
         -- that stopped there. No email, no identity; swept 30 min after
         -- creation by cleanup-anonymous-voices. The page marks these so a row
         -- without an email reads as "didn't sign up" rather than as a signup
         -- that somehow lost its address.
         coalesce(u.is_anonymous, false)             as anonymous,
         u.created_at::date::text                    as signed_up,
         s.plan_id, s.status as sub_status,
         s.trial_ends_at::date::text                 as trial_ends,
         c.balance,
         (vc.id is not null)                         as clone,
         va.name                                     as voice_name,
         va.voice_id                                 as voice_id,
         va.created_at                               as voice_at,
         p.display_name, p.occupation, p.location, p.interests, p.intro,
         wl.email                                    as real_email,
         wl.referrer                                 as channel,
         wl.user_agent,
         wl.created_at::date::text                   as waitlist_at,
         -- appended 2026-09-12 (launch watch)
         u.created_at                                as signed_up_at,
         u.raw_app_meta_data->>'provider'            as provider,
         u.last_sign_in_at,
         s.cancel_at_period_end,
         s.source                                    as sub_source,
         s.started_at                                as sub_started,
         s.current_period_end                        as period_end,
         s.trial_ends_at,
         vc.created_at                               as clone_at,
         tb.first_talk_at, tb.last_talk_at,
         u.created_at                                as sort_at
  from auth.users u
  left join public.user_subscriptions s on s.user_id = u.id
  left join public.user_credits c       on c.user_id = u.id
  left join lateral (select id, created_at from public.voice_clones v
                      where v.user_id = u.id order by created_at limit 1) vc on true
  -- The voice they are USING now, not the first one they made.
  left join lateral (select v.name, v.voice_id, v.created_at
                       from public.voice_clones v
                      where v.user_id = u.id
                      order by v.is_active desc, v.created_at desc limit 1) va on true
  left join talk_bounds tb on tb.user_id = u.id
  left join lateral (select pp.display_name, pp.occupation, pp.location,
                            pp.interests, pp.intro
                       from public.public_personas pp
                      where pp.owner_user_id = u.id and pp.is_active
                      order by pp.updated_at desc limit 1) p on true
  left join lateral (select l.email, l.referrer, l.user_agent, l.created_at
                       from public.user_waitlist_mapping m
                       join public.waitlist l on l.email = m.waitlist_email
                      where m.user_id = u.id limit 1) wl on true
),

cells as (
  select user_id::text as id, created_at::date::text as d,
         count(*)                                              as rows,
         -- One conversation turn = one reply call. NOT every Gemini call: a
         -- turn also fires a transcribe call, and TTS splits a reply into two
         -- requests, so counting those double- or triple-counts the turn.
         -- Speculative replies carry purpose='turn' too but are frequently
         -- thrown away, so a tagged one is excluded; rows written before the
         -- tag existed have no `spec` key and still count, which is correct.
         count(*) filter (where source_fn = 'gemini'
                            and metadata->>'purpose' = 'turn'
                            and coalesce(metadata->>'spec','false') <> 'true')
                                                               as turns,
         coalesce(sum(public.talk_row_seconds(metadata, delta))
                  filter (where action = 'talk_time'), 0)::int  as secs,
         -- The learner's own voice inside those seconds. NULL, not 0, on a
         -- day no tick measured it (see the header) — "unknown" and "said
         -- nothing" must not print the same.
         sum((metadata->>'learner_seconds')::int)
           filter (where action = 'talk_time'
                     and metadata ? 'learner_seconds')::int     as spoke
  from public.usage_ledger, w
  where created_at >= w.start
    and kind is distinct from 'grant'   -- see the header
  group by 1, 2
),

scenes as (
  select user_id::text as id, day::text as d, count(*) as n
  from public.scene_plays, w where created_at >= w.start group by 1, 2
),

sessions as (
  select user_id::text as id, min(created_at)::date::text as d,
         sum(public.talk_row_seconds(metadata, delta))::int as secs
  from public.usage_ledger, w
  where action = 'talk_time' and metadata->>'session_id' is not null
    and created_at >= w.start
  group by user_id, metadata->>'session_id'
),

-- The last two weeks of talk sessions, one row each. Turns are counted from
-- the reply calls inside the session's own time span (the reply row carries
-- no session_id), and a session is "summarized" if a summary call landed in
-- the five minutes after its last tick — approximate on purpose, it only
-- has to say whether the wrap-up worked.
recent_sessions as (
  select user_id, metadata->>'session_id' as sid,
         min(created_at) as started, max(created_at) as ended,
         sum(public.talk_row_seconds(metadata, delta))::int as secs,
         max(metadata->>'language') as lang
  from public.usage_ledger
  where action = 'talk_time' and metadata->>'session_id' is not null
    and created_at >= now() - interval '14 days'
  group by 1, 2
),
recent_sessions_full as (
  select rs.user_id::text as id, rs.sid, rs.started, rs.ended, rs.secs, rs.lang,
         (select count(*) from public.usage_ledger t
           where t.user_id = rs.user_id
             and t.source_fn = 'gemini' and t.metadata->>'purpose' = 'turn'
             and coalesce(t.metadata->>'spec','false') <> 'true'
             and t.created_at between rs.started - interval '60 seconds'
                                  and rs.ended + interval '90 seconds')::int as turns,
         exists (select 1 from public.usage_ledger t
                  where t.user_id = rs.user_id and t.action = 'gemini_summary'
                    and t.created_at between rs.ended - interval '60 seconds'
                                         and rs.ended + interval '5 minutes') as summarized
  from recent_sessions rs
),

errors as (
  select created_at::date::text as d, count(*) as n
  from public.client_events, w
  where (event ilike '%error%' or event ilike '%fail%')
    and created_at >= w.start
  group by 1
),

-- The unit economics the 비용 tab is built from: chars of conversation TTS
-- per metered talk minute, and chars of scene TTS per scene actually played.
mech as (
  select (select sum(public.talk_row_seconds(metadata, delta))/60.0
            from public.usage_ledger, w
           where action = 'talk_time' and created_at >= w.cost_start)::float8 as talk_min,
         (select sum((metadata->>'chars')::numeric)
            from public.usage_ledger, w
           where action = 'tts' and metadata->>'purpose' = 'turn'
             and created_at >= w.cost_start)::float8 as turn_chars,
         (select sum((metadata->>'chars')::numeric)
            from public.usage_ledger, w
           where metadata->>'purpose' = 'scene'
             and created_at >= w.cost_start)::float8 as scene_chars,
         (select count(*) from public.scene_plays, w
           where created_at >= w.cost_start)::float8 as plays
)

select jsonb_build_object(
  'today',       current_date::text,
  'windowStart', (select start::text from w),
  'liveAt',      to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),

  'users', (select coalesce(jsonb_agg(to_jsonb(x) - 'sort_at' order by x.sort_at), '[]'::jsonb)
              from users_raw x),

  -- languages actually practised — see the header for why not `profiles`
  'langs', (select coalesce(jsonb_agg(jsonb_build_object(
                     'id', user_id::text,
                     'langs', langs)), '[]'::jsonb)
              from (select user_id, array_agg(distinct language order by language) as langs
                      from (
                        select user_id, language from public.talk_seconds_by_language
                        union
                        select user_id, metadata->>'language' from public.usage_ledger
                         where metadata ? 'language' and nullif(metadata->>'language','') is not null
                        union
                        select owner_user_id, language from public.public_personas
                         where owner_user_id is not null
                      ) u group by 1) l),

  -- What they CHOSE in onboarding, where the app has reported it.
  -- `setup_at is null` means the row is still the signup trigger's defaults
  -- ('ko'/'en'/'b1') and says nothing — those rows are simply not returned,
  -- so the page can say "아직 안 들어옴" instead of printing English.
  'setup', (select coalesce(jsonb_agg(jsonb_build_object(
                     'id', id::text, 'target', target_language,
                     'native', native_language, 'level', proficiency,
                     'at', setup_at)), '[]'::jsonb)
              from public.profiles where setup_at is not null),

  -- Per user AND per language: how much was spoken, and which sources know
  -- about it. `secs` is all-time, like the Core's ledger it comes from — what
  -- someone is learning is not a launch-window fact.
  'user_langs', (select coalesce(jsonb_agg(jsonb_build_object(
                   'id', user_id::text, 'lang', language,
                   'secs', secs, 'days', days, 'src', srcs)
                 order by secs desc), '[]'::jsonb)
                   from (
                     select user_id, language,
                            coalesce(sum(secs), 0)::int          as secs,
                            coalesce(sum(days), 0)::int          as days,
                            array_agg(distinct src order by src) as srcs
                       from (
                         select user_id, language, sum(seconds)::int as secs,
                                count(distinct day)::int as days, 'talk' as src
                           from public.talk_seconds_by_language group by 1, 2
                         union all
                         select user_id, metadata->>'language', 0, 0, 'ledger'
                           from public.usage_ledger
                          where metadata ? 'language'
                            and nullif(metadata->>'language','') is not null
                         union all
                         select owner_user_id, language, 0, 0, 'persona'
                           from public.public_personas
                          where owner_user_id is not null
                       ) s
                      where language is not null
                      group by 1, 2
                   ) x),



  'reviews', (select coalesce(jsonb_agg(jsonb_build_object(
                       'id', user_id::text, 'context', context, 'rating', rating,
                       'body', body, 'd', created_at::date::text,
                       'at', created_at)
                     order by created_at), '[]'::jsonb)
                from public.beta_reviews),

  -- When talking happens, by UTC hour of day and by user. See the header.
  'hours', (select coalesce(jsonb_agg(jsonb_build_object(
                     'id', user_id::text, 'h', h,
                     'secs', secs, 'talk', talk, 'events', events,
                     'days', days)), '[]'::jsonb)
              from (select user_id,
                           extract(hour from created_at at time zone 'UTC')::int as h,
                           coalesce(sum(public.talk_row_seconds(metadata, delta))
                                    filter (where action = 'talk_time'), 0)::int as secs,
                           count(*) filter (where action = 'talk_time')::int     as talk,
                           count(*)::int                                         as events,
                           count(distinct (created_at at time zone 'UTC')::date)::int as days
                      from public.usage_ledger, w
                     where created_at >= w.start
                       and kind is distinct from 'grant'
                     group by 1, 2) hx),

  -- 요일별·주별·월별을 만드는 하나의 계열: (사람, 날짜, 시) 별로 통화 초와
  -- 서버 호출 수. 날짜만이 아니라 '시'까지 들고 내려보내는 이유는 하나 —
  -- 페이지는 시간대(베를린·서울·UTC)를 고를 수 있고, UTC 날짜로 미리 묶어
  -- 버리면 자정 근처의 통화가 하루씩, 따라서 요일도 한 칸씩 밀린다. 묶는
  -- 일은 읽는 쪽에서 해야 정확하다.
  --
  -- `hours`(출시 이후, 시각별)와 `cells`(출시 이후, 날짜별)는 출시 창을 쓰지만
  -- 이건 `w.cost_history`(2026-08-10, Talk이 과금 단위가 된 날 = 통화 초가
  -- 기록되기 시작한 날)부터 본다: 주와 달을 물어보려면 아흐레로는 답이 안
  -- 나오고, 그 앞은 통화 초가 0이라 빈 달만 그려진다. 180일 상한이 같이 붙어
  -- 있어서 시작일은 언젠가 저절로 굴러간다.
  -- 2026-09-20 기준 전체 635행 — 사람이 늘어 이게 수만 행이 되는 날에는
  -- 서버에서 요일/주/월로 접어야 한다. 접는 순간 사람 단위 필터(본인·테스트
  -- 계정 제외)가 사라지므로, 그때는 그 필터도 서버로 같이 내려가야 한다.
  'day_hours', (select coalesce(jsonb_agg(jsonb_build_object(
                         'id', user_id::text, 'd', d::text, 'h', h,
                         'secs', secs, 'events', events, 'spoke', spoke)), '[]'::jsonb)
                  from (select user_id,
                               (created_at at time zone 'UTC')::date                 as d,
                               extract(hour from created_at at time zone 'UTC')::int as h,
                               coalesce(sum(public.talk_row_seconds(metadata, delta))
                                        filter (where action = 'talk_time'), 0)::int as secs,
                               count(*)::int                                         as events,
                               sum((metadata->>'learner_seconds')::int)
                                 filter (where action = 'talk_time'
                                           and metadata ? 'learner_seconds')::int as spoke
                          from public.usage_ledger, w
                         where created_at >= greatest(w.cost_history, current_date - 180)
                           and kind is distinct from 'grant'
                         group by 1, 2, 3) dh),

  'cells',    (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from cells x),
  'scenes',   (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from scenes x),
  'sessions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from sessions x),
  'errors',   (select coalesce(jsonb_agg(to_jsonb(x) order by x.d), '[]'::jsonb) from errors x),

  'features', (select coalesce(jsonb_agg(jsonb_build_object(
                        'purpose', purpose, 'total', total, 'users', users)
                      order by total desc), '[]'::jsonb)
                 from (select purpose, sum("count")::int as total,
                              count(distinct user_id) as users
                         from public.free_usage_daily, w
                        where day >= w.start group by 1) f),

  'builds', (select coalesce(jsonb_agg(jsonb_build_object(
                      'build', build, 'users', users, 'last_seen', last_seen)
                    order by last_seen desc, users desc), '[]'::jsonb)
               from (select coalesce(properties->>'build','(unknown)') as build,
                            count(distinct user_id) as users,
                            max(created_at)::date::text as last_seen
                       from public.client_events
                      where created_at >= current_date - 30
                      group by 1) b),

  'waitlist', (select jsonb_build_object(
                 'total', count(*),
                 'wants_beta', count(*) filter (where wants_beta),
                 'converted', (select count(*) from public.user_waitlist_mapping))
                 from public.waitlist),

  'channels', (select coalesce(jsonb_agg(jsonb_build_object(
                        'name', name, 'n', n, 'beta', beta) order by n desc), '[]'::jsonb)
                 from (select coalesce(referrer,'(없음)') as name, count(*) as n,
                              count(*) filter (where wants_beta) as beta
                         from public.waitlist group by 1) c),

  'cost_daily', (select coalesce(jsonb_agg(jsonb_build_object(
                          'd', d::text, 'tts', tts, 'gm', gm) order by d), '[]'::jsonb)
                   from (select day as d,
                                round(sum(tts_usd)::numeric,4)::float8 as tts,
                                round(sum(gemini_usd)::numeric,4)::float8     as gm
                           from public.user_daily_usage, w
                          where day >= w.cost_history group by day) cd),

  'cost_user', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                  select jsonb_build_object(
                    'id', user_id::text,
                    'usd', round(sum(total_usd)::numeric,4)::float8,
                    'tts', round(sum(tts_usd)::numeric,4)::float8,
                    'gm',  round(sum(gemini_usd)::numeric,4)::float8,
                    'chars', round(sum(tts_chars)::numeric)::float8,
                    'unpriced', bool_or(has_unpriced)) as x
                  from public.user_daily_usage, w where day >= w.cost_history group by user_id) y),

  -- Same figures cut by calendar month, so the table can be read a month at a
  -- time. Talk and scenes ride along: a cost column filtered to August beside
  -- a talk column counting everything invites the wrong comparison.
  'cost_month', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                   select jsonb_build_object(
                     'month', to_char(day,'YYYY-MM'),
                     'id', user_id::text,
                     'usd', round(sum(total_usd)::numeric,4)::float8,
                     'tts', round(sum(tts_usd)::numeric,4)::float8,
                     'gm',  round(sum(gemini_usd)::numeric,4)::float8,
                     'chars', round(sum(tts_chars)::numeric)::float8,
                     'talk_secs', sum(talk_seconds)::int,
                     'scenes', sum(scenes)::int) as x
                   from public.user_daily_usage, w where day >= w.cost_history
                   group by to_char(day,'YYYY-MM'), user_id) y),

  'rates', (select coalesce(jsonb_agg(jsonb_build_object(
                     'provider', provider, 'model', model, 'unit', unit,
                     'usd', usd_per_unit::float8,
                     'since', effective_from::date::text, 'note', note)
                   order by provider, model, unit), '[]'::jsonb)
              from public.provider_rates),

  'unpriced', (select coalesce(jsonb_agg(jsonb_build_object(
                        'provider', provider, 'model', model, 'unit', unit,
                        'rows', rows::int, 'units', units::float8)), '[]'::jsonb)
                 from public.unpriced_usage),

  -- Who crossed the fair-use line on an uncapped plan this period. NOT a wall
  -- — talking is only stopped far above it (`subscription_plans.abuse_seconds`)
  -- — so this list is the whole enforcement mechanism: a person looks at it.
  'fair_use', (select coalesce(jsonb_agg(jsonb_build_object(
                        'id', f.user_id::text, 'since', f.period_start::text,
                        'secs', f.seconds::int, 'at', f.updated_at::text,
                        'plan', s.plan_id, 'line', p.monthly_seconds::int,
                        'stop', p.abuse_seconds::int)
                      order by f.seconds desc), '[]'::jsonb)
                 from public.fair_use_flags f
                 join public.user_subscriptions s on s.user_id = f.user_id
                 join public.subscription_plans p on p.id = s.plan_id),

  'plans', (select coalesce(jsonb_agg(jsonb_build_object(
                     'id', id, 'tier', tier, 'period', period,
                     'monthly_seconds', monthly_seconds,
                     'monthly_scenes', monthly_scenes,
                     'talk_unlimited', talk_unlimited)
                   order by tier, period), '[]'::jsonb)
              from public.subscription_plans where is_active),

  'mech', (select to_jsonb(m) from mech m),
  'cost_window', (select cost_start::text from w),

  -- $ per synthesized character, the voice provider's current rate
  'tts_rate', (select usd_per_unit::float8 from public.provider_rates
                where provider = 'cartesia' and unit = 'char'
                order by effective_from desc limit 1),
  'commission', (select usd_per_unit::float8 from public.provider_rates
                  where provider = 'apple' and unit = 'commission_fraction'
                  order by effective_from desc limit 1)
,

  -- ---------------------------------------------------------------- launch
  'sub_events', (select coalesce(jsonb_agg(jsonb_build_object(
                          'id', user_id::text, 'at', created_at, 'purchase', purchase_date,
                          'type', notification_type, 'subtype', subtype,
                          'plan', plan_id, 'trial', is_trial,
                          'price', price_milliunits / 1000.0, 'currency', currency,
                          'revoked', revocation_date is not null, 'offer', offer_type)
                        order by created_at desc), '[]'::jsonb)
                   from public.subscription_transactions
                  where environment = 'Production'),

  'recent_sessions', (select coalesce(jsonb_agg(to_jsonb(x) order by x.started desc), '[]'::jsonb)
                        from recent_sessions_full x),

  'recent_events', (select coalesce(jsonb_agg(to_jsonb(x) order by x.last desc), '[]'::jsonb) from (
                      select user_id::text as id, event,
                             nullif(properties->>'code','') as code,
                             count(*)::int as n,
                             max(created_at) as last,
                             max(properties->>'build') as build,
                             max(coalesce(nullif(properties->>'error',''),
                                          nullif(properties->>'detail',''),
                                          nullif(properties->>'message',''))) as detail
                        from public.client_events
                       where created_at >= now() - interval '7 days'
                         and event not in ('talk_turn_timing', 'talk_asr_upgrade',
                                           'talk_rt_session')
                       group by 1, 2, 3) x),

  'free_recent', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', user_id::text, 'd', day::text,
                           'purpose', purpose, 'n', "count")), '[]'::jsonb)
                    from public.free_usage_daily
                   where day >= current_date - 14),

  -- ------------------------------------------------- realtime call records
  -- One row per finished call, newest first. `reason` is the gateway's own
  -- word for why it ended: hangup · idle · client_gone · transcriber ·
  -- socket_closed · a wall code. Anything that is not `hangup` is a call the
  -- learner did not choose to end.
  'rt_sessions', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', user_id::text, 'at', created_at, 'src', src,
                           'reason', reason,
                           'turns', coalesce(nullif(properties->>'turns','')::int, 0),
                           'secs', coalesce(nullif(properties->>'speech_s','')::int, 0),
                           'ms', coalesce(nullif(properties->>'duration_ms','')::int, 0),
                           'p50', nullif(properties->>'voice_first_p50_ms','')::int,
                           'max', nullif(properties->>'voice_first_max_ms','')::int,
                           'warnings', coalesce(nullif(properties->>'warnings','')::int, 0),
                           'detail', left(properties->>'message', 120),
                           'build', properties->>'build')
                         order by created_at desc), '[]'::jsonb)
                    from (select user_id, created_at, properties,
                                 case event when 'talk_rt_session' then 'ended' else 'failed' end as src,
                                 case event when 'talk_rt_session' then properties->>'reason'
                                            else coalesce(nullif(properties->>'code',''), 'gateway') end as reason
                            from public.client_events
                           where event in ('talk_rt_session', 'talk_rt_failed')
                             and created_at >= now() - interval '14 days'
                           order by created_at desc limit 400) e),

  -- --------------------------------------------------- plan usage + renewal
  'plan_usage', (select coalesce(jsonb_agg(jsonb_build_object(
                   'id', x.user_id::text,
                   'plan', x.plan_id, 'tier', x.tier, 'status', x.status,
                   'source', x.source, 'ends', x.cancel_at_period_end,
                   'period_start', x.period_start::text,
                   'period_end', x.current_period_end,
                   'trial', x.is_trial,
                   'talk_used', x.talk_used, 'talk_cap', x.talk_cap,
                   'scenes_used', x.scenes_used, 'scenes_cap', x.scenes_cap,
                   'unlimited', x.talk_unlimited,
                   'bonus', x.bonus)
                 order by x.current_period_end), '[]'::jsonb)
                  from (
                    select s.user_id, s.plan_id, p.tier, s.status, s.source,
                           s.cancel_at_period_end, s.current_period_end,
                           (s.status = 'trialing')                        as is_trial,
                           public.billing_period_start(s.user_id)         as period_start,
                           (s.status <> 'trialing'
                             and coalesce(s.talk_unlimited,
                                          p.talk_unlimited, false))       as talk_unlimited,
                           case when s.status = 'trialing'
                                then coalesce(s.monthly_seconds,
                                              (select min(monthly_seconds)
                                                 from public.subscription_plans
                                                where tier = 'light'),
                                              p.monthly_seconds) * 7 / 30
                                else coalesce(s.monthly_seconds,
                                              p.monthly_seconds) end      as talk_cap,
                           coalesce((select c.balance from public.user_credits c
                                      where c.user_id = s.user_id), 0)    as bonus,
                           case when s.status = 'trialing'
                                then coalesce(s.monthly_scenes,
                                              (select min(monthly_scenes)
                                                 from public.subscription_plans
                                                where tier = 'light'),
                                              p.monthly_scenes) * 7 / 30
                                else coalesce(s.monthly_scenes,
                                              p.monthly_scenes) end       as scenes_cap,
                           public.plan_period_seconds(s.user_id)
                                                                          as talk_used,
                           coalesce((select count(*)::int
                                       from public.scene_plays sp
                                      where sp.user_id = s.user_id
                                        and sp.created_at >= public.billing_period_started_at(s.user_id)), 0)
                                                                          as scenes_used
                      from public.user_subscriptions s
                      join public.subscription_plans p on p.id = s.plan_id
                     where s.status in ('trialing', 'active', 'grace')
                  ) x),

  'rt_reasons', (select coalesce(jsonb_agg(jsonb_build_object(
                          'reason', reason, 'n', n, 'users', users,
                          'turns', turns) order by n desc), '[]'::jsonb)
                   from (select coalesce(properties->>'reason','(없음)') reason,
                                count(*)::int n,
                                count(distinct user_id)::int users,
                                coalesce(sum((properties->>'turns')::int),0)::int turns
                           from public.client_events
                          where event = 'talk_rt_session'
                            and created_at >= now() - interval '7 days'
                          group by 1) r)
);
$function$;

-- 5 ---------------------------------------------------------------------------
drop function if exists public.default_accent_backfill_candidates(timestamptz, integer);
drop table if exists public.default_accent_backfill_log;
drop function if exists public.set_elevenlabs_usd_per_credit(numeric, timestamptz, text);
