-- admin_raw(): what the console needs to WATCH a launch, not only to analyse
-- a beta.
--
-- The page was built for ten beta users and a month of history: cohorts,
-- streaks, unit economics. On launch day (2026-09-12, nine signups) the
-- questions changed — who signed up in the last hour, did they get through
-- the clone, did they talk, did they start a trial, did they cancel it — and
-- none of that was on the page. Two trial cancellations that day were found
-- by joining user_subscriptions by hand.
--
-- Same function, same callers, same keys as before (every existing chart
-- keeps reading exactly what it read); this APPENDS:
--   users[]         signed_up_at (timestamp, not just the date), provider,
--                   last_sign_in_at, cancel_at_period_end, sub_source,
--                   sub_started, period_end, trial_ends_at, clone_at,
--                   first_talk_at, last_talk_at
--   sub_events      subscription_transactions, Production only — the row is
--                   upserted per transaction so this is each transaction's
--                   LATEST state, not a history
--   recent_sessions talk sessions of the last 14 days, with an approximate
--                   turn count and whether a summary landed
--   recent_events   client_events of the last 7 days, minus the two
--                   per-turn telemetry rows, grouped by user × event
--   free_recent     free_usage_daily of the last 14 days (what else they did)

create or replace function public.admin_raw()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
with
-- Everything on this page starts the day Talk became the unit of account.
-- 2026-08-10 is where the first `talk_time`, the first `tts_scene` and the
-- first `free_usage_daily` rows all appear. The cost window starts later,
-- when scene_plays began being written — before it, per-scene cost is
-- inflated by scene audio whose plays were never recorded.
w as (select date '2026-08-10' as start, date '2026-08-14' as cost_start),

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
         u.created_at::date::text                    as signed_up,
         s.plan_id, s.status as sub_status,
         s.trial_ends_at::date::text                 as trial_ends,
         c.balance,
         (vc.id is not null)                         as clone,
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
                  filter (where action = 'talk_time'), 0)::int  as secs
  from public.usage_ledger, w
  where created_at >= w.start
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

  -- languages actually practised, from the Core's per-language ledger
  'langs', (select coalesce(jsonb_agg(jsonb_build_object(
                     'id', user_id::text,
                     'langs', langs)), '[]'::jsonb)
              from (select user_id, array_agg(distinct language order by language) as langs
                      from public.talk_seconds_by_language group by 1) l),

  'reviews', (select coalesce(jsonb_agg(jsonb_build_object(
                       'id', user_id::text, 'context', context, 'rating', rating,
                       'body', body, 'd', created_at::date::text)
                     order by created_at), '[]'::jsonb)
                from public.beta_reviews),

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
                          'd', d::text, 'el', el, 'gm', gm) order by d), '[]'::jsonb)
                   from (select day as d,
                                round(sum(elevenlabs_usd)::numeric,4)::float8 as el,
                                round(sum(gemini_usd)::numeric,4)::float8     as gm
                           from public.user_daily_usage, w
                          where day >= w.start group by day) cd),

  'cost_user', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                  select jsonb_build_object(
                    'id', user_id::text,
                    'usd', round(sum(total_usd)::numeric,4)::float8,
                    'el',  round(sum(elevenlabs_usd)::numeric,4)::float8,
                    'gm',  round(sum(gemini_usd)::numeric,4)::float8,
                    'chars', round(sum(tts_chars)::numeric)::float8,
                    'unpriced', bool_or(has_unpriced)) as x
                  from public.user_daily_usage, w where day >= w.start group by user_id) y),

  -- Same figures cut by calendar month, so the table can be read a month at a
  -- time. Talk and scenes ride along: a cost column filtered to August beside
  -- a talk column counting everything invites the wrong comparison.
  'cost_month', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                   select jsonb_build_object(
                     'month', to_char(day,'YYYY-MM'),
                     'id', user_id::text,
                     'usd', round(sum(total_usd)::numeric,4)::float8,
                     'el',  round(sum(elevenlabs_usd)::numeric,4)::float8,
                     'gm',  round(sum(gemini_usd)::numeric,4)::float8,
                     'chars', round(sum(tts_chars)::numeric)::float8,
                     'talk_secs', sum(talk_seconds)::int,
                     'scenes', sum(scenes)::int) as x
                   from public.user_daily_usage, w where day >= w.start
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

  -- $/credit, back out of the per-char rate (turbo bills 0.5 credit/char)
  'rate', (select usd_per_unit::float8 / 0.5 from public.provider_rates
            where provider = 'elevenlabs' and model = 'eleven_turbo_v2_5'
              and unit = 'char' order by effective_from desc limit 1),
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
                      select user_id::text as id, event, count(*)::int as n,
                             max(created_at) as last,
                             max(properties->>'build') as build,
                             max(coalesce(nullif(properties->>'error',''),
                                          nullif(properties->>'detail',''))) as detail
                        from public.client_events
                       where created_at >= now() - interval '7 days'
                         and event not in ('talk_turn_timing', 'talk_asr_upgrade')
                       group by 1, 2) x),

  'free_recent', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', user_id::text, 'd', day::text,
                           'purpose', purpose, 'n', "count")), '[]'::jsonb)
                    from public.free_usage_daily
                   where day >= current_date - 14)
);
$$;

revoke all on function public.admin_raw() from public, anon, authenticated;
grant execute on function public.admin_raw() to service_role;
