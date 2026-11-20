-- ---------------------------------------------------------------------------
-- No free voice for an account whose free minutes were withheld
-- (2026-11-18, founder: "the first clone is free once per device too").
--
-- Seen that day: one Android phone made three accounts in 36 minutes
-- (deleted the first, signed up again with the same Gmail, then with a new
-- one). `free_grant_withheld` caught both (email, then device), so neither
-- got talk minutes, but each still made a voice, three accents and a
-- greeting for free, because the first clone is free per ACCOUNT.
--
-- `voice_clone_allowed` already refuses a parked voice's owner who has
-- nothing to spend; a withheld account now gets the same answer. The edge
-- function sends the spent-pool 402 for it, so every build shows what it
-- shows for a spent pool. With a plan, or any balance (a code, an invite, a
-- purchase), the voice is made as usual.
--
-- Not covered: an onboarding that clones on an ANONYMOUS session and links
-- the account afterwards. The withholding is written at the link, after the
-- voice exists.
-- ---------------------------------------------------------------------------

create or replace function public.voice_clone_allowed(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (
           not exists (select 1 from voice_clones
                        where user_id = p_user_id and parked_at is not null)
           and not exists (select 1 from free_grant_withheld
                            where user_id = p_user_id)
         )
      or public.voice_owner_is_entitled(p_user_id)
      or coalesce((select balance from user_credits where user_id = p_user_id), 0) > 0;
$$;
