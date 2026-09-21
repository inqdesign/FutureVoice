-- ---------------------------------------------------------------------------
-- Put back the trials an informational Apple notification promoted.
--
-- `apple-webhook`'s statusFor mapped every unlisted notificationType to a flat
-- "active" (default branch), ignoring the transaction's own FREE_TRIAL offer.
-- On 2026-09-13 a PRICE_INCREASE/PENDING notification — Apple asking a
-- subscriber to consent to a new price, which says nothing about entitlement —
-- landed on a running 7-day plus_monthly trial and wrote `status = 'active'`.
--
-- Two things break when that happens:
--   * metering. `consume_metered_seconds` / `talk_allowance` read
--     `status <> 'trialing' and talk_unlimited`, so the trial stopped being
--     capped at the light pool's 7/30 (35 min) and became UNCAPPED — a week's
--     sample worth more than the month it converts to (20260821120000).
--   * counting. `user_directory.subscription_state` reads 'active' as "paid,
--     renews", so a free trial was in the paid column.
--
-- The function is fixed (informational types now leave the status alone); this
-- repairs the rows already written. A trial is identified by `trial_ends_at`
-- still being in the future, which only the webhook's own FREE_TRIAL branch
-- ever writes — so nothing that was genuinely paid can be caught by it.
-- ---------------------------------------------------------------------------
update public.user_subscriptions
   set status = 'trialing',
       updated_at = now()
 where status = 'active'
   and trial_ends_at is not null
   and trial_ends_at > now()
   and current_period_end is not null
   and trial_ends_at >= current_period_end;
