-- Flag the developer account as unlimited (see 20260706090000).
--
-- Resolution order:
--   1. auth.users row with the known dev email (exact when Apple sign-in
--      didn't use the private relay);
--   2. otherwise the FIRST account ever created — the developer signed up
--      before any invite existed, so the earliest row is the dev account.
--
-- RAISE NOTICE prints which account got flagged in the `db push` output, so
-- the operator can verify the match immediately.

do $$
declare
  v_uid uuid;
  v_email text;
begin
  select id, email into v_uid, v_email
    from auth.users
   where email = 'eunggyu.lee@gmail.com'
   limit 1;

  if v_uid is null then
    select id, email into v_uid, v_email
      from auth.users
     order by created_at asc
     limit 1;
  end if;

  if v_uid is null then
    raise notice 'admin flag: no auth users found — nothing flagged';
    return;
  end if;

  insert into public.user_credits (user_id, balance, unlimited, updated_at)
  values (v_uid, 999999, true, now())
  on conflict (user_id) do update
    set unlimited = true,
        balance = 999999,
        updated_at = now();

  raise notice 'admin flag: unlimited credits enabled for % (email: %)', v_uid, coalesce(v_email, '<none>');
end $$;
