-- The renewal offers already running, read off Apple on 2026-09-18.
--
-- 20260918100000 added the columns, but they only fill as notifications
-- arrive — and Apple sends nothing between a purchase and its first renewal.
-- The three people whose launch code is pricing their NEXT charge would have
-- kept seeing the regular price for the rest of their trial, which is the
-- complaint the columns exist to answer. So the values are backfilled from
-- `GET /inApps/v1/subscriptions/<originalTransactionId>` (see
-- scripts/apple-subscription.sh), one call per entitled Apple subscription.
--
-- 24 entitled rows: 11 renew (3 of them on a `Beta50 … v2` offer code), 12
-- have auto-renew OFF — nothing renews, so their columns stay null, which is
-- the honest reading — and 1 is the founder's Sandbox row, which the
-- production API does not know.
--
-- Guarded on `apple_original_tx_id` so a row the webhook has since moved to a
-- different subscription is left alone. From here the webhook keeps these
-- current on every notification.

update public.user_subscriptions set
    renewal_offer_type = null, renewal_offer_id = null,
    renewal_price_milliunits = 29000000, renewal_currency = 'KRW',
    renewal_product_id = 'com.roro.futurevoice.unlimited_monthly'
  where user_id = '09101cc8-94f7-4bc1-b11e-52ba668eb18b' and apple_original_tx_id = '500003042786071';
update public.user_subscriptions set
    renewal_offer_type = 3, renewal_offer_id = 'Beta50 Plus Monthly v2',
    renewal_price_milliunits = 14500000, renewal_currency = 'KRW',
    renewal_product_id = 'com.roro.futurevoice.unlimited_monthly'
  where user_id = '1f5c04ca-e7e9-4b82-a962-99988b341ed1' and apple_original_tx_id = '270003123752849';
update public.user_subscriptions set
    renewal_offer_type = null, renewal_offer_id = null,
    renewal_price_milliunits = 0, renewal_currency = 'KRW',
    renewal_product_id = 'com.roro.futurevoice.unlimited_monthly'
  where user_id = 'a680574d-b3c8-4fd7-9633-6a5e4dcf2723' and apple_original_tx_id = '530003098792306';
update public.user_subscriptions set
    renewal_offer_type = null, renewal_offer_id = null,
    renewal_price_milliunits = 0, renewal_currency = 'KRW',
    renewal_product_id = 'com.roro.futurevoice.daily_monthly'
  where user_id = '07ad19f0-6383-4242-b03a-4bfe993409c3' and apple_original_tx_id = '310003179058251';
update public.user_subscriptions set
    renewal_offer_type = null, renewal_offer_id = null,
    renewal_price_milliunits = 0, renewal_currency = 'KRW',
    renewal_product_id = 'com.roro.futurevoice.unlimited_monthly'
  where user_id = '703341ce-49b0-4e06-9ab8-b228605330c2' and apple_original_tx_id = '380002564362134';
update public.user_subscriptions set
    renewal_offer_type = 3, renewal_offer_id = 'Beta50 Plus Monthly v2',
    renewal_price_milliunits = 9990, renewal_currency = 'USD',
    renewal_product_id = 'com.roro.futurevoice.unlimited_monthly'
  where user_id = '019b115f-9c87-4cc0-9db2-e87029a298e5' and apple_original_tx_id = '530003097841262';
update public.user_subscriptions set
    renewal_offer_type = null, renewal_offer_id = null,
    renewal_price_milliunits = 148000, renewal_currency = 'CNY',
    renewal_product_id = 'com.roro.futurevoice.unlimited_monthly'
  where user_id = '82237c9a-8214-48a1-9930-e2c76071b9e1' and apple_original_tx_id = '160003648195835';
update public.user_subscriptions set
    renewal_offer_type = null, renewal_offer_id = null,
    renewal_price_milliunits = 0, renewal_currency = 'KRW',
    renewal_product_id = 'com.roro.futurevoice.unlimited_annual'
  where user_id = '2ba4ed7d-9f92-4289-8970-0684aa362b71' and apple_original_tx_id = '340002864257948';
update public.user_subscriptions set
    renewal_offer_type = null, renewal_offer_id = null,
    renewal_price_milliunits = 0, renewal_currency = 'KRW',
    renewal_product_id = 'com.roro.futurevoice.unlimited_monthly'
  where user_id = '3a626756-a581-4672-9b2e-c889845db18b' and apple_original_tx_id = '270003114617995';
update public.user_subscriptions set
    renewal_offer_type = null, renewal_offer_id = null,
    renewal_price_milliunits = 88000, renewal_currency = 'HKD',
    renewal_product_id = 'com.roro.futurevoice.daily_monthly'
  where user_id = '4e4d6bf5-be9a-45cf-ac08-feb8b3ca5ade' and apple_original_tx_id = '710002996211156';
update public.user_subscriptions set
    renewal_offer_type = 3, renewal_offer_id = 'Beta50 Light Monthly v2',
    renewal_price_milliunits = 4990, renewal_currency = 'USD',
    renewal_product_id = 'com.roro.futurevoice.daily_monthly'
  where user_id = '00c6a881-e825-425c-8805-cbd86ec6147b' and apple_original_tx_id = '530003087964475';
