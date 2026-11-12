-- A challenger's day checks in by itself (2026-11-12).
--
-- A day of the 100-day challenge counts when it had 4+ minutes of talk AND one
-- speech take, by the date where the participant lives. The server could judge
-- neither half properly: its talk ledger is kept by UTC day, and a speech take
-- never left the phone. So the phone says, per LOCAL date, how much of each
-- there was, and the admin's creators page judges the three months from that.
--
-- Why its own table and not the Learner Record (`learner_events`): that record
-- is switched off, and the apps in the stores mark every event as sent whatever
-- the server accepted. Opening it for participants only would lose everyone
-- else's events. This is purpose-limited instead: two counts a day, kept only
-- for someone who paid for the challenge, and nothing about what was said.
--
-- The contract with the apps is `challenge_days_put` and nothing else:
--   * not a paid challenger  → nothing is stored, {"participant": false}
--   * a paid challenger      → each day keeps the GREATER of what is on file and
--     what was sent, so a second device, a retry or a reinstalled phone with a
--     shorter memory can never take a kept day away
--   * an empty array is a legal call: it is how the app asks "am I in?"

create table if not exists public.challenge_days (
  user_id      uuid not null references auth.users(id) on delete cascade,
  -- The participant's LOCAL date, as their phone named it. Never converted:
  -- the cohort's days are Seoul's, a participant's day is where they live.
  day          date not null,
  talk_seconds integer not null default 0 check (talk_seconds between 0 and 86400),
  speech_takes integer not null default 0 check (speech_takes between 0 and 200),
  -- Kept so a disputed day can be read ("which date was it for them?"), never judged on.
  time_zone    text check (char_length(time_zone) <= 64),
  platform     text check (char_length(platform) <= 16),
  app_version  text check (char_length(app_version) <= 24),
  updated_at   timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.challenge_days enable row level security;

-- A participant may read their own days (the check-in page will show them).
-- There is no write policy on purpose: the only writer is the function below,
-- which is what holds the "never lower a day" rule.
drop policy if exists challenge_days_owner_read on public.challenge_days;
create policy challenge_days_owner_read on public.challenge_days
  for select to authenticated
  using (user_id = auth.uid());

revoke all on table public.challenge_days from anon, authenticated;
grant select on table public.challenge_days to authenticated;

create or replace function public.challenge_days_put(p_days jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_item     jsonb;
  v_day      date;
  v_talk     integer;
  v_speech   integer;
  v_accepted integer := 0;
  v_seen     integer := 0;
  v_starts   date;
begin
  -- Paid, and a challenger. A creator posts instead and is not judged by days;
  -- an application that stopped at the pay step is not in yet.
  if v_uid is null or not exists (
    select 1 from public.creator_applications
     where user_id = v_uid and kind = 'challenger' and paid_at is not null
  ) then
    return jsonb_build_object('participant', false, 'accepted', 0);
  end if;

  if jsonb_typeof(p_days) = 'array' then
    for v_item in select value from jsonb_array_elements(p_days) loop
      -- The app sends at most 60 days; anything past that is not from the app.
      v_seen := v_seen + 1;
      exit when v_seen > 60;
      -- One bad row (a date that doesn't exist, a number that isn't one) must
      -- not cost the other days of the same call, so each stands alone.
      begin
        if (v_item->>'day') !~ '^\d{4}-\d{2}-\d{2}$' then continue; end if;
        v_day    := (v_item->>'day')::date;
        v_talk   := (v_item->>'talk_seconds')::integer;
        v_speech := (v_item->>'speech_takes')::integer;
        -- 45 days back covers a month's judging with room for a phone that was
        -- offline; a day ahead is someone east of UTC whose date already turned.
        if v_day is null or v_talk is null or v_speech is null
           or v_day < current_date - 45 or v_day > current_date + 1
           or v_talk < 0 or v_talk > 86400
           or v_speech < 0 or v_speech > 200 then
          continue;
        end if;

        insert into public.challenge_days as d
          (user_id, day, talk_seconds, speech_takes, time_zone, platform, app_version, updated_at)
        values (
          v_uid, v_day, v_talk, v_speech,
          -- A label too long is cut, never a reason to lose the day it rides on.
          left(nullif(v_item->>'time_zone', ''), 64),
          left(nullif(v_item->>'platform', ''), 16),
          left(nullif(v_item->>'app_version', ''), 24),
          now()
        )
        on conflict (user_id, day) do update set
          talk_seconds = greatest(d.talk_seconds, excluded.talk_seconds),
          speech_takes = greatest(d.speech_takes, excluded.speech_takes),
          time_zone    = coalesce(excluded.time_zone, d.time_zone),
          platform     = coalesce(excluded.platform, d.platform),
          app_version  = coalesce(excluded.app_version, d.app_version),
          updated_at   = now();
        v_accepted := v_accepted + 1;
      exception when others then
        null;
      end;
    end loop;
  end if;

  -- The cohort's first day as Seoul's calendar date, so the app can say
  -- "starts on" without knowing the cohort's time zone. Null until it is set.
  select (challenge_starts_at at time zone 'Asia/Seoul')::date
    into v_starts
    from public.billing_config
   limit 1;

  return jsonb_build_object('participant', true, 'accepted', v_accepted, 'starts_on', v_starts);
end;
$$;

-- Signed-in accounts only. The function answers for auth.uid(), so there is
-- nobody for the service role or an anonymous key to call it as.
revoke all on function public.challenge_days_put(jsonb) from public, anon;
grant execute on function public.challenge_days_put(jsonb) to authenticated;
