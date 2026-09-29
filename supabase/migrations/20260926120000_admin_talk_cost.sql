-- ---------------------------------------------------------------------------
-- The per-user cost table sees half the money (2026-09-26).
--
-- `admin_raw().cost_user` / `cost_month` price the TTS characters in the
-- ledger — and the realtime gateway, which carries every call since
-- 2026-09-13, sends its characters to ElevenLabs without writing them
-- anywhere. Over 9/12–9/26 the table's ElevenLabs column summed to $19.67 at
-- the Pro rate against $42 on ElevenLabs' own meter; a Plus subscriber with
-- 108 minutes of calls showed $0.095, because the only characters on file
-- for them were a voicemail. The founder read the table as "talking costs
-- less than I was told" — it was the table that couldn't see the talking.
--
-- The fix is on the console side (`admin/src/assemble.ts`): a user's TALK
-- cost is their metered seconds × the credits-per-minute measured from
-- ElevenLabs' usage API (the one figure the ledger can't supply), and the
-- ledger's own priced characters cover everything else. Two things that
-- needs from the database, per user and per month, that `admin_raw` does
-- not hand over:
--
--   · the ledger's TURN rows (`purpose = 'turn'`, the app-side TTS path that
--     older builds and a few surfaces still use) — those characters ARE
--     talk, and are subtracted so a call is not counted twice;
--   · talk seconds per user for the whole cost window (`cost_month` carries
--     them per month; `cost_user` never did).
--
-- A function of its own rather than another 500-line copy of `admin_raw`:
-- the console makes one more RPC and merges. Service role only, like
-- `admin_raw`.
-- ---------------------------------------------------------------------------

create or replace function public.admin_talk_cost()
returns jsonb
language sql
security definer
set search_path to 'public'
as $$
  with w as (select date '2026-08-10' as cost_history),   -- same as admin_raw
  turn as (
    select user_id, to_char(created_at, 'YYYY-MM') as month,
           sum(usd) as usd
      from usage_cost, w
     where action = 'tts' and purpose = 'turn'
       and created_at >= w.cost_history
     group by user_id, to_char(created_at, 'YYYY-MM')
  ),
  talk as (
    select user_id, to_char(created_at, 'YYYY-MM') as month,
           sum(talk_row_seconds(metadata, delta)) as secs
      from usage_ledger, w
     where action = 'talk_time'
       and created_at >= w.cost_history
     group by user_id, to_char(created_at, 'YYYY-MM')
  ),
  both_ as (
    select coalesce(t.user_id, k.user_id) as user_id,
           coalesce(t.month, k.month) as month,
           coalesce(t.usd, 0) as turn_usd,
           coalesce(k.secs, 0) as talk_secs
      from turn t
      full join talk k on k.user_id = t.user_id and k.month = t.month
  )
  select jsonb_build_object(
    'user', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
               select jsonb_build_object(
                 'id', user_id::text,
                 'turn_usd', round(sum(turn_usd)::numeric, 4)::float8,
                 'talk_secs', sum(talk_secs)::int) as x
                 from both_ group by user_id) u),
    'month', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                select jsonb_build_object(
                  'month', month, 'id', user_id::text,
                  'turn_usd', round(turn_usd::numeric, 4)::float8,
                  'talk_secs', talk_secs::int) as x
                  from both_) m)
  );
$$;

revoke all on function public.admin_talk_cost() from public, anon, authenticated;
