-- ---------------------------------------------------------------------------
-- The waiting queue becomes first-qualified, first-seated.
--
-- Promotion used to sort by: recent departure first, then met_keep desc, then
-- met_entry desc, then seniority. Once every waiting member has to clear the
-- SAME bar to be eligible at all (20260815140000 — 28 of the last 30 days),
-- the two middle terms stop meaning anything defensible. They rank 30/30
-- above 28/30, which is a second competition invented on top of a pass/fail
-- test, and its effect is that someone who has waited two months can be
-- overtaken indefinitely by whoever happened to talk on all thirty days last
-- month. A bar is a bar; above it, everyone is equal, which is the same
-- principle that keeps the inside of the club rankless.
--
-- So the queue is now exactly one rule: whoever qualified first goes first.
-- `join_number` is the qualification order — it comes off a sequence at the
-- moment the month is completed — so it IS the queue, and this is the reason
-- the column survives even though no person is ever shown it
-- (20260815130000).
--
-- The recently-departed priority goes away as an explicit term and comes back
-- for free: someone returning qualified long ago, so their number is low and
-- they are already ahead of the people who qualified after them. The door
-- back stays easier than the door in, without a special case.
--
-- Same-day qualifiers also stop being ranked by how many days they cleared:
-- everyone crossing 28 on the same settlement is equal, so the tie is broken
-- arbitrarily and honestly by user_id rather than by a metric that pretends
-- to be a merit.
--
-- Everything else in this function is reproduced verbatim from
-- 20260813120000. The order of operations — qualify, release, promote — is
-- what guarantees a newcomer never displaces a sitting member, and must not
-- be touched.
-- ---------------------------------------------------------------------------

create or replace function public.settle_core_club(
  p_as_of date default (now() at time zone 'utc')::date
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c           core_club_config%rowtype;
  v_qualified integer := 0;
  v_promoted  integer := 0;
  v_released  integer := 0;
  v_seated    integer := 0;
  v_free      integer := 0;
begin
  -- Idempotent per day: a re-run must not double-count days_total.
  if exists (select 1 from core_settlement_log where day = p_as_of) then
    return jsonb_build_object('day', p_as_of, 'skipped', true);
  end if;

  select * into c from core_club_config where id;

  drop table if exists _core_stats;
  create temporary table _core_stats on commit drop as
  with act as (
    select user_id, day, talk_seconds
      from core_daily_activity
     where day > p_as_of - c.entry_window_days
       and day <= p_as_of
  )
  select u.user_id,
         count(*) filter (
           where a.talk_seconds >= c.daily_bar_seconds
         )::int as met_entry,
         count(*) filter (
           where a.talk_seconds >= c.daily_bar_seconds
             and a.day > p_as_of - c.keep_window_days
         )::int as met_keep
    from (select user_id from act
          union
          select user_id from core_membership) u
    left join act a on a.user_id = u.user_id
   group by u.user_id;

  -- (a) Qualify. The badge is granted the moment the month is done — it is
  --     never held back waiting for a seat or for the club to fill. Numbers
  --     come off a sequence and are never reused; they are the queue's order
  --     and nothing else.
  drop table if exists _core_new;
  create temporary table _core_new on commit drop as
  with fresh as (
    select s.user_id
      from _core_stats s
     where s.met_entry >= c.entry_required_days
       and not exists (select 1 from core_membership m where m.user_id = s.user_id)
     -- Everyone here cleared the same bar on the same day. There is no honest
     -- way to rank them, so the tie-break is arbitrary rather than dressed up
     -- as merit.
     order by s.user_id
  ), issued as (
    insert into core_membership (user_id, join_number)
    select user_id, nextval('core_join_number_seq') from fresh
    returning user_id, join_number
  )
  select * from issued;

  select count(*) into v_qualified from _core_new;

  -- (b) Release. Below the keep bar → the seat is vacated. This is the ONLY
  --     way a seat opens.
  drop table if exists _core_out;
  create temporary table _core_out on commit drop as
  with released as (
    update core_membership m
       set seated = false,
           seated_since = null,
           last_left_on = p_as_of,
           updated_at = now()
      from _core_stats s
     where s.user_id = m.user_id
       and m.seated
       and s.met_keep < c.keep_required_days
    returning m.user_id, m.join_number
  )
  select * from released;

  select count(*) into v_released from _core_out;

  -- (c) Promote into whatever is now free, oldest qualification first.
  select count(*) into v_seated from core_membership where seated;
  v_free := greatest(c.seats - v_seated, 0);

  drop table if exists _core_in;
  create temporary table _core_in on commit drop as
  with eligible as (
    -- Never seated before → this will be their first seat.
    select m.user_id, (m.last_left_on is null) as first_time
      from core_membership m
      join _core_stats s on s.user_id = m.user_id
     where not m.seated
       and case
             when m.last_left_on is null
               or p_as_of - m.last_left_on <= c.requalify_after_days
             then s.met_keep >= c.keep_required_days
             -- Gone long enough that the month has to be earned again. With
             -- one bar these branches are the same test; the case stays so
             -- that splitting the bars again keeps working.
             else s.met_entry >= c.entry_required_days
           end
     order by m.join_number asc
     limit v_free
  ), promoted as (
    update core_membership m
       set seated = true,
           seated_since = p_as_of,
           updated_at = now()
      from eligible e
     where e.user_id = m.user_id
    returning m.user_id, m.join_number, e.first_time
  )
  select * from promoted;

  select count(*) into v_promoted from _core_in;

  -- (d) Tenure. Counted after promotion, so a seat taken today counts today.
  --     days_total is stock: it survives every later departure.
  update core_membership set days_total = days_total + 1 where seated;

  select count(*) into v_seated from core_membership where seated;

  -- (e) Events, all stamped with the FINAL club size — the counter is the
  --     emotional payload of the announcement, so it must be the number a
  --     member would see if they opened the app right then.
  insert into core_events (kind, user_id, join_number, club_size)
  select 'left', user_id, join_number, v_seated from _core_out;

  insert into core_events (kind, user_id, join_number, club_size)
  select 'qualified', user_id, join_number, v_seated from _core_new;

  insert into core_events (kind, user_id, join_number, club_size, first_time)
  select 'seated', user_id, join_number, v_seated, first_time from _core_in;

  -- Fires once, ever.
  if v_seated >= c.seats
     and not exists (select 1 from core_events where kind = 'club_full') then
    insert into core_events (kind, club_size) values ('club_full', v_seated);
  end if;

  insert into core_settlement_log (day, qualified, promoted, released, seated_after)
  values (p_as_of, v_qualified, v_promoted, v_released, v_seated);

  return jsonb_build_object(
    'day', p_as_of, 'skipped', false,
    'qualified', v_qualified, 'promoted', v_promoted,
    'released', v_released, 'seated', v_seated, 'seats', c.seats);
end;
$$;

revoke all on function public.settle_core_club(date) from public, anon, authenticated;

comment on column public.core_club_config.return_priority_days is
  'Unused since 20260815150000. The queue is ordered by join_number, so a '
  'returning member is already ahead of everyone who qualified after them.';
