-- Free translations: "tap to see the meaning" moves off the credit-gated
-- `gemini` function onto a dedicated free `translate` Edge Function (fixed
-- server-side prompt, flash-lite). Ledger data showed a single review session
-- spending more credits on meaning-taps than on the conversation itself —
-- for an upstream cost of fractions of a cent.
--
-- This table is the per-user hourly rate-limit counter for that free path
-- (same role word_entry's created_by/created_at play for free dictionary
-- generation). Service-role only; no client reads.

create table if not exists public.translation_log (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  kind        text not null,               -- 'translate' | 'explain'
  chars       integer not null default 0,  -- input size, for cost observability
  created_at  timestamptz not null default now()
);

create index if not exists translation_log_user_created_idx
  on public.translation_log(user_id, created_at desc);

-- No policies on purpose: only the service-role client (Edge Function)
-- touches this table.
alter table public.translation_log enable row level security;
