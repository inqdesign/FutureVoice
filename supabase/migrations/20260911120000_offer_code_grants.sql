-- ---------------------------------------------------------------------------
-- Offer code grants: which App Store one-time code went to whom.
--
-- The beta ends 2026-09-21 and testers + the waitlist get a year at half
-- price (docs/launch-billing.md §7). The price lives in App Store Connect as
-- an Offer Code; the codes are ONE-TIME (a custom code shared in a chat is a
-- coupon for strangers), so each person gets their own — and the only record
-- of who got which would otherwise be a spreadsheet. The emails are already
-- here (`waitlist`, `user_waitlist_mapping`), so the assignment is written
-- here too, by the `offer-code-mail` function that also sends the mail.
--
-- One row per code. `(offer, email)` is unique so the same person can never
-- be dealt two codes for the same offer by a re-run. `sent_at` is null for a
-- code reserved for someone who can't be mailed (an Apple private-relay
-- address with no waitlist match — the relay only forwards from a domain
-- registered in ASC, and Gmail isn't one) and is handed over by hand.
-- Never read by a client.
-- ---------------------------------------------------------------------------

create table if not exists public.offer_code_grants (
  code        text primary key,
  offer       text not null,                       -- ASC offer reference name
  kind        text not null check (kind in ('beta', 'waitlist')),
  email       text not null,
  user_id     uuid references auth.users(id) on delete set null,
  sent_at     timestamptz,
  note        text,
  created_at  timestamptz not null default now()
);

create unique index if not exists offer_code_grants_offer_email
  on public.offer_code_grants (offer, lower(email));

comment on table public.offer_code_grants is
  'App Store one-time offer codes dealt to beta testers and the waitlist; '
  'written by the offer-code-mail function. sent_at null = handed over by hand.';

alter table public.offer_code_grants enable row level security;
revoke all on public.offer_code_grants from anon, authenticated;
