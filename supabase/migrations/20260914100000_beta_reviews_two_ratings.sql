-- ---------------------------------------------------------------------------
-- Two scores beside the sentence, and the build they were given on.
--
-- `rating` (already here, nullable, unused since 2026-08-17) becomes the score
-- for the APP; `call_rating` is the score for the CALLS. They are asked
-- together in one sheet — "how is the app" and "how is the thing the app is
-- for" are different answers, and a single number blurs them: someone can
-- love the calls and find everything around them confusing, which is exactly
-- the feedback worth having.
--
-- Both stay OPTIONAL and independent. A row with no score and a written note
-- is the most valuable row there is; a row with two scores and no note is
-- still worth having. The sheet enables Send when EITHER exists.
--
-- `app_version` / `app_build` because a score is unreadable six weeks later
-- without them: "the calls got worse" is only actionable against the build it
-- got worse on.
--
-- The old `first_talk` / `first_watch` rows keep working untouched — they
-- simply carry nulls in the new columns.
--
-- ORDER MATTERS: this must be applied BEFORE the app build that writes
-- `call_rating` ships, or every insert from that build fails and the feedback
-- is silently dropped (the same trap `FeedbackSheet`'s doc comment describes
-- for renaming the table).
-- ---------------------------------------------------------------------------
alter table public.beta_reviews
  add column if not exists call_rating smallint,
  add column if not exists app_version text,
  add column if not exists app_build   text;

do $$
begin
  alter table public.beta_reviews
    add constraint beta_reviews_call_rating_range
    check (call_rating is null or call_rating between 1 and 5);
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.beta_reviews
    add constraint beta_reviews_rating_range
    check (rating is null or rating between 1 and 5);
exception when duplicate_object then null;
end $$;
