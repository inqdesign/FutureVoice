-- ---------------------------------------------------------------------------
-- The console's Gemini section (2026-10-08).
--
-- Until today the money tab carried Gemini as one daily total off the ledger,
-- and the ledger saw about a quarter of the Gemini bill: the live call (the
-- reply and the transcriber) goes from the gateway straight to Google. The
-- gateway now writes a row per call (purpose call-reply / call-transcribe),
-- and word-entry one per new dictionary entry (purpose dictionary), so the
-- money tab can say where the Gemini money goes — by day, by feature, by
-- model, with the reply's cache share — and what a call minute costs in it.
--
-- One function of its own, like admin_talk_cost; the console treats it as
-- optional. Grain: UTC day × purpose × model × unit, priced by
-- usage_cost_component (unpriced units come back with usd null). Plus the
-- day's metered talk minutes, the denominator of "per call minute".
-- Service role only.
-- ---------------------------------------------------------------------------

create or replace function public.admin_gemini()
returns jsonb
language sql
security definer
set search_path to 'public'
stable
as $$
  select jsonb_build_object(
    'rows', (select coalesce(jsonb_agg(jsonb_build_object(
               'd', d::text, 'p', p, 'm', m, 'u', unit, 'q', q, 'usd', usd, 'n', n)), '[]'::jsonb)
               from (select (created_at at time zone 'UTC')::date as d,
                            coalesce(purpose, action)               as p,
                            model                                   as m,
                            unit,
                            sum(qty)::bigint                        as q,
                            round(sum(usd)::numeric, 6)             as usd,
                            count(distinct ledger_id)::int          as n
                       from public.usage_cost_component
                      where provider = 'gemini'
                        and created_at >= date '2026-08-10'
                      group by 1, 2, 3, 4) t),
    'talk', (select coalesce(jsonb_agg(jsonb_build_object('d', d::text, 'min', min) order by d), '[]'::jsonb)
               from (select (created_at at time zone 'UTC')::date as d,
                            round(sum(abs(delta))::numeric / 60, 1) as min
                       from public.usage_ledger
                      where action = 'talk_time'
                        and created_at >= date '2026-08-10'
                      group by 1) t)
  );
$$;

revoke all on function public.admin_gemini() from public, anon, authenticated;
grant execute on function public.admin_gemini() to service_role;
