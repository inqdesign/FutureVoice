-- Pre-launch security hardening (2026-08-22). Five independent fixes, all
-- server-side so no client change is required to close them:
--
--   1) An abuse rate limiter that a REPLAYED idempotency key cannot skip.
--   2) Referral inviter-bonus can no longer be farmed from anonymous sessions.
--   3) Find-people pool rows must carry real density and a bounded intro.
--   4) The global word-cache tables stop accepting direct client writes.
--
-- None of these touch the money math in charge_credits / consume_metered_seconds
-- (already server-role-only, verified sound); they close the free-tier and
-- shared-pool faucets that sit AROUND that math.

-- ---------------------------------------------------------------------------
-- 1) Idempotency-proof abuse limiter.
--
-- THE BUG: every free/pooled metering RPC (record_free_usage,
-- charge_tts_free_pooled, …) short-circuits on a duplicate X-Idempotency-Key
-- and returns `charged: 0` WITHOUT raising — so the edge function proceeds to
-- call Gemini / ElevenLabs for real. A client that PINS one constant key
-- therefore never advances any daily cap and never pays, turning both provider
-- keys into an unlimited free faucet (reachable from an anonymous session).
--
-- The daily caps can't catch it because a pinned key writes no new ledger row,
-- so nothing counts. This limiter increments UNCONDITIONALLY per request,
-- independent of any idempotency key, in an hourly bucket. A pinned key now
-- hits the hourly ceiling like any other traffic; honest use never approaches
-- it (a heavy hour of talking is a few hundred calls). It is a backstop that
-- sits in FRONT of the existing per-purpose daily caps, not a replacement.
create table if not exists public.edge_request_rate (
  user_id    uuid not null references auth.users(id) on delete cascade,
  hour       timestamptz not null,          -- date_trunc('hour', now())
  source_fn  text not null,                 -- "gemini" | "elevenlabs-tts"
  count      integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, hour, source_fn)
);
alter table public.edge_request_rate enable row level security;
-- No client policies: only the SECURITY DEFINER function below touches it.

-- Bump the caller's hourly request counter for one edge function and return
-- the new count; raise RATE_LIMITED once it passes the ceiling. Because the
-- increment happens before (and regardless of) any idempotency check, a
-- replayed key cannot slip past it.
create or replace function public.bump_request_rate(
  p_user_id uuid,
  p_source_fn text,
  p_limit integer
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_hour timestamptz := date_trunc('hour', now());
begin
  insert into edge_request_rate (user_id, hour, source_fn, count)
  values (p_user_id, v_hour, p_source_fn, 1)
  on conflict (user_id, hour, source_fn) do update
    set count = edge_request_rate.count + 1,
        updated_at = now()
  returning count into v_count;

  if v_count > p_limit then
    raise exception 'RATE_LIMITED' using errcode = 'P0004';
  end if;
  return v_count;
end;
$$;

revoke all on function public.bump_request_rate(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.bump_request_rate(uuid, text, integer) to service_role;

-- Old buckets are worthless the moment their hour passes; a daily cron trims
-- them so the table can't grow without bound.
create index if not exists edge_request_rate_hour_idx on public.edge_request_rate(hour);

create or replace function public.trim_edge_request_rate()
returns void
language sql
security definer
set search_path = public
as $$
  delete from edge_request_rate where hour < now() - interval '2 days';
$$;
revoke all on function public.trim_edge_request_rate() from public, anon, authenticated;
grant execute on function public.trim_edge_request_rate() to service_role;

-- Best-effort schedule (same pattern as settle_core_club) — the limiter works
-- with or without it; this only keeps the table small.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule('trim_edge_request_rate')
      where exists (select 1 from cron.job where jobname = 'trim_edge_request_rate');
    perform cron.schedule('trim_edge_request_rate', '20 0 * * *',
                          $cron$select public.trim_edge_request_rate();$cron$);
  end if;
exception when others then
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Referral: the inviter bonus can be farmed from anonymous sessions.
--
-- Anonymous sign-ins are enabled (the pre-signup clone flow needs them) and an
-- anonymous user carries the `authenticated` Postgres role, so it can call
-- redeem_referral. The self-referral guard only blocks matching uuids, so an
-- attacker spins up N anonymous sessions, redeems their OWN code from each, and
-- harvests up to 10 x 1800 s = 300 min of free talk into their real account.
-- Require the INVITEE to be a non-anonymous (linked) account before either
-- bonus is granted — the reward should follow a real sign-up, not a throwaway.
create or replace function public.redeem_referral(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitee uuid := auth.uid();
  v_inviter uuid;
  v_code text := upper(trim(p_code));
  v_invite_count int;
  v_balance int;
  v_inviter_rewarded boolean := false;
  v_bonus int := 1800;          -- seconds, both sides
begin
  if v_invitee is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- An anonymous session is not a real account; a referral must not pay out to
  -- (or on behalf of) one, or the bonus becomes farmable N sessions at a time.
  if exists (
    select 1 from auth.users
     where id = v_invitee and coalesce(is_anonymous, false)
  ) then
    raise exception 'ANON_NOT_ALLOWED';
  end if;
  if v_code is null or length(v_code) = 0 then raise exception 'INVALID_CODE'; end if;

  select user_id into v_inviter from referral_codes where code = v_code;
  if v_inviter is null then raise exception 'INVALID_CODE'; end if;
  if v_inviter = v_invitee then raise exception 'SELF_REFERRAL'; end if;
  if exists (select 1 from referral_redemptions where invitee_id = v_invitee) then
    raise exception 'ALREADY_REDEEMED';
  end if;

  insert into referral_redemptions(invitee_id, inviter_id, code)
  values (v_invitee, v_inviter, v_code);

  -- Invitee bonus (one-time).
  v_balance := public.grant_credits(
    p_user_id => v_invitee, p_credits => v_bonus, p_kind => 'grant',
    p_action => 'referral_invitee', p_source_fn => 'redeem_referral',
    p_idempotency_key => 'ref_invitee:' || v_invitee::text,
    p_metadata => jsonb_build_object('code', v_code, 'inviter', v_inviter)
  );

  -- Inviter bonus, capped at the first 10 successful invites.
  select count(*) into v_invite_count
    from referral_redemptions where inviter_id = v_inviter;
  if v_invite_count <= 10 then
    perform public.grant_credits(
      p_user_id => v_inviter, p_credits => v_bonus, p_kind => 'grant',
      p_action => 'referral_inviter', p_source_fn => 'redeem_referral',
      p_idempotency_key => 'ref_inviter:' || v_invitee::text,
      p_metadata => jsonb_build_object('code', v_code, 'invitee', v_invitee)
    );
    v_inviter_rewarded := true;
  end if;

  return jsonb_build_object(
    'balance', v_balance,
    'invitee_bonus', v_bonus,
    'inviter_rewarded', v_inviter_rewarded
  );
end;
$$;

revoke all on function public.redeem_referral(text) from public;
grant execute on function public.redeem_referral(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Find-people pool: server-side density + size bound on published rows.
--
-- The 80-char density gate lived only in the client, so any authenticated
-- (including anonymous) session could publish an ACTIVE persona with a one-line
-- or oversized `intro` — which is also quoted verbatim into the conversation
-- prompt (YOUR CHARACTER block), making it a prompt-injection surface reachable
-- without a real account. Enforce the bar in the database: an ACTIVE row must
-- carry a real intro, and no row may carry an unbounded one. NOT VALID so any
-- pre-existing curated row is grandfathered; the constraint is enforced on
-- every future insert/update.
alter table public.public_personas
  add constraint public_personas_intro_bounds
  check (
    (is_active = false or char_length(intro) between 80 and 2000)
    and char_length(display_name) between 1 and 80
  ) not valid;

-- ---------------------------------------------------------------------------
-- 4) Global word-cache: stop accepting direct client writes (cache poisoning).
--
-- word_lore / word_meaning / word_entry are read by every learner and their
-- rows are first-writer-wins for any not-yet-cached key. The
-- "insertable by authed with check (true)" policies let any authenticated
-- (incl. anonymous) session pre-seed garbage or offensive definitions that are
-- then served to everyone forever. Generation already runs exclusively through
-- the `word-entry` edge function on the service role (which bypasses RLS), and
-- the client only SELECTs — so dropping the client INSERT policies changes no
-- legitimate behaviour and closes the poisoning vector. Read policies are left
-- intact.
drop policy if exists "word_entry insertable by authed" on public.word_entry;
drop policy if exists "word_lore insertable by authed" on public.word_lore;
drop policy if exists "word_meaning insertable by authed" on public.word_meaning;
