-- The admin's plan-usage table reads each subscription's STAMP first, the
-- way every meter has since 2026-09-26 (`consume_metered_seconds`,
-- `talk_allowance`). Scenes already did; talk did not, so a subscriber sold a
-- bigger pool than today's catalog — the three legacy Plus rows at 900 min,
-- a trial stamped with the plan it trials — showed the CATALOG's cap, and an
-- uncapped legacy row showed as capped. `bonus` is the extra minutes
-- (`user_credits.balance`: packs, invites) spent before the plan's pool.
--
-- Body is prod's `pg_get_functiondef` of 2026-09-28 with only the
-- plan_usage section changed.

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
         va.elevenlabs_voice_id                      as voice_id,
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
  left join lateral (select v.name, v.elevenlabs_voice_id, v.created_at
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
                          'd', d::text, 'el', el, 'gm', gm) order by d), '[]'::jsonb)
                   from (select day as d,
                                round(sum(elevenlabs_usd)::numeric,4)::float8 as el,
                                round(sum(gemini_usd)::numeric,4)::float8     as gm
                           from public.user_daily_usage, w
                          where day >= w.cost_history group by day) cd),

  'cost_user', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                  select jsonb_build_object(
                    'id', user_id::text,
                    'usd', round(sum(total_usd)::numeric,4)::float8,
                    'el',  round(sum(elevenlabs_usd)::numeric,4)::float8,
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
                     'el',  round(sum(elevenlabs_usd)::numeric,4)::float8,
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
                           coalesce((select sum(t.chars)::int
                                       from public.tts_char_pool t
                                      where t.user_id = s.user_id
                                        and t.action in ('talk_seconds','scene_seconds')
                                        and t.day >= public.billing_period_start(s.user_id)), 0)
                                                                          as talk_used,
                           coalesce((select count(*)::int
                                       from public.scene_plays sp
                                      where sp.user_id = s.user_id
                                        and sp.day >= public.billing_period_start(s.user_id)), 0)
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
