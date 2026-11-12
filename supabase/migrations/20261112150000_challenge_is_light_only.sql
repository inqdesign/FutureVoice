-- Every challenger takes Light (2026-11-12, founder: one size; more is his to
-- give by hand). The Plus and Max packages come off the web's shelf: their
-- rows stay, so one UPDATE brings them back, and stripe-checkout refuses a
-- plan that is neither active nor sold on the web.
update subscription_plans
   set sold_on_web = false
 where id in ('plus_challenge', 'max_challenge');
