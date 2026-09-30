-- The welcome letter, once per account.
--
-- One row per user, written BEFORE the send and stamped after Resend accepts,
-- so a re-run never mails anyone twice and a failed send is retried. Both the
-- one-off broadcast to accounts that signed up before the letter existed
-- (`scripts/welcome-mail.py`, variant 'hello') and the at-signup send (variant
-- 'signup') claim the same row, so nobody gets both.

create table if not exists public.welcome_mails (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  lang       text not null,          -- 'ko' | 'en' | 'both'
  variant    text not null,          -- 'signup' | 'hello'
  claimed_at timestamptz not null default now(),
  sent_at    timestamptz,
  resend_id  text,
  error      text
);

alter table public.welcome_mails enable row level security;
-- No policies: service role only.
