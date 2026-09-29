-- nawana.app/community, round three: deleting a message, and knowing you're staff.
--
-- Delete is a SOFT delete — `hidden = true`, the same flag moderation uses —
-- so a message that was reported and then deleted by its author can still be
-- read by the team. The author may delete their own; staff may delete any.
-- It runs through a function because the browser has no UPDATE on the table
-- (every other column is the trigger's to set).
--
-- `community_am_i_staff()` lets the page show staff-only chrome (the online
-- count, delete on everyone's messages). It is a display switch only: the
-- delete function checks staff again on the server.

alter table public.community_messages
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

create or replace function public.community_am_i_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from community_staff where user_id = auth.uid());
$$;

create or replace function public.community_delete_message(p_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'not_signed_in' using errcode = 'P0001';
  end if;
  update community_messages
     set hidden = true, deleted_at = now(), deleted_by = v_uid
   where id = p_id
     and not hidden
     and (user_id = v_uid or exists (select 1 from community_staff where user_id = v_uid));
  return found;
end;
$$;

revoke all on function public.community_am_i_staff() from public, anon;
revoke all on function public.community_delete_message(bigint) from public, anon;
grant execute on function public.community_am_i_staff() to authenticated;
grant execute on function public.community_delete_message(bigint) to authenticated;
