-- nawana.app/community: the chat is for people with an account.
--
-- Until now anyone could read it (and only signed-in people write). From here
-- reading needs a signed-in, non-anonymous account too: the page asks a
-- visitor to sign in with the account they use in the app. News and the
-- feature guides stay public. Realtime follows these policies, so a signed-out
-- browser receives no messages live either.

drop policy if exists "chat is public" on public.community_messages;
drop policy if exists "signed-in people read the chat" on public.community_messages;
create policy "signed-in people read the chat" on public.community_messages
  for select to authenticated
  using (not hidden and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false);

drop policy if exists "likes are public" on public.community_reactions;
drop policy if exists "signed-in people see likes" on public.community_reactions;
create policy "signed-in people see likes" on public.community_reactions
  for select to authenticated
  using (coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false);
