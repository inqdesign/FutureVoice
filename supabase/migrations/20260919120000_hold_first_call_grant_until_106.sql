-- ---------------------------------------------------------------------------
-- Hold the first-call grant until 1.0.6 (53) is on the App Store.
--
-- 20260918100000 went to prod on 2026-09-17 22:55 UTC while the store still
-- served 1.0.5 (51), which has neither the post-summary pitch nor the mid-call
-- wrap-up. On 51 a 300 s balance makes OnboardingPaywallView skip itself
-- (needsSubscription is false above zero), so the only mention of a plan is a
-- "Something went wrong — your talk time is used up" alert mid-call. From that
-- moment to 2026-09-19: 11 signups, 0 trials (the five days before: 22 of 31).
--
-- New accounts start at 0 again, which puts the onboarding paywall back on 51.
-- Balances already granted are left alone (taking back seconds someone was
-- given is worse than the leak). Restore by re-applying 20260918100000's
-- function body AFTER `beta.sh released 53` — not before.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user_credits()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.user_credits (user_id, balance, updated_at)
  values (new.id, 0, now())
  on conflict (user_id) do nothing;
  return new;
end;
$$;
