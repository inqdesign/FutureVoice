-- nawana.app/community: the team's own posts are readable without signing in.
--
-- The chat is otherwise members-only (20260929180000). A top-level message
-- from a staff account is an announcement, so everyone may read it. A staff
-- REPLY is not included: without the member's message it answers, it reads
-- out of context, and it may quote what that member said.

drop policy if exists "anyone reads team posts" on public.community_messages;
create policy "anyone reads team posts" on public.community_messages
  for select to anon, authenticated
  using (is_staff and parent_id is null and not hidden);
