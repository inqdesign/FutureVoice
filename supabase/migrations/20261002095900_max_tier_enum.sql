-- `subscription_plans.tier` is the `subscription_tier` ENUM (light, plus).
-- Max (`20261002100000_max_tier`) needs its own value, and a value added by
-- `alter type … add value` cannot be USED in the transaction that adds it —
-- `apply-migration.sh` sends a file as one transaction, so this is its own
-- file and runs first.

alter type public.subscription_tier add value if not exists 'max';
