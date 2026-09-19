-- ---------------------------------------------------------------------------
-- The first call is free again — 1.0.6 (53) is on the App Store.
--
-- 20260919120000 held the grant at 0 because 1.0.5 (51) had no post-call
-- pitch and showed a spent free call as an error alert. 1.0.6 was released
-- in every storefront on 2026-09-19 21:44 UTC (itunes lookup kr/us/de) and
-- `beta.sh released 53` moved `app_release.latest_build`, so a new signup
-- installs a build that wraps the call up and offers the plans after its
-- summary. Same body as 20260918100000; no backfill (that one already ran).
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
declare
  -- One call. Keep it a named constant: this is the number the whole
  -- "try it before you buy it" decision rests on.
  first_call_seconds constant integer := 300;
begin
  insert into public.user_credits (user_id, balance, updated_at)
  values (new.id, first_call_seconds, now())
  on conflict (user_id) do nothing;
  return new;
end;
$$;
