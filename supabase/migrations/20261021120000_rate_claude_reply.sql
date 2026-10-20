-- The gateway's reply can run on Claude Haiku 5.5 (gateway/src/claude-reply.ts,
-- switched per account by CLAUDE_REPLY). Its rows land in usage_ledger exactly
-- like the Gemini reply's (action 'gemini', purpose 'call-reply', model in
-- metadata), so the cost views price them by model with no view change — they
-- only need the rates. Listed under provider 'gemini' because that is the
-- label the views group every LLM row by; the model column says which it was.
--
-- Anthropic list price, prompts up to 100K tokens (verified 2026-10-21 on
-- platform.claude.com/docs/en/about-claude/pricing). Cache WRITES cost 1.25x
-- input ($0.125); the ledger row folds them into prompt_tokens, so they are
-- priced at $0.10 here — the row's `cache_write_tokens` says how many.

insert into public.provider_rates (provider, model, unit, usd_per_unit, effective_from, note) values
  ('gemini', 'claude-haiku-5-5', 'input_token',        0.10/1000000, timestamptz '2026-10-01', 'Anthropic Haiku 5.5, verified 2026-10-21'),
  ('gemini', 'claude-haiku-5-5', 'cached_input_token', 0.01/1000000, timestamptz '2026-10-01', 'Anthropic Haiku 5.5 cache read, verified 2026-10-21'),
  ('gemini', 'claude-haiku-5-5', 'output_token',       0.50/1000000, timestamptz '2026-10-01', 'Anthropic Haiku 5.5, verified 2026-10-21')
on conflict (provider, model, unit, effective_from) do nothing;
