-- ---------------------------------------------------------------------------
-- Five more minutes for the six first callers whose free call misbehaved.
--
-- Signed up while the first-call grant ran on 1.0.5 (2026-09-17 → 09-19),
-- spent most of the 300 s, and met the old wall: a call cut before the pool
-- was empty, "Something went wrong", books written twice, and no trial offer.
-- Fixed server-side in 20260920190000; this gives them the call they were
-- promised, and the founder's mail says so. Idempotent per user.
-- ---------------------------------------------------------------------------

do $$
declare
  r record;
begin
  for r in
    select u.id
      from auth.users u
     where u.email in ('sajacall@gmail.com',
                       'sodamkim25@gmail.com',
                       'ninakimsuyeon@gmail.com',
                       'hbkim1042@gmail.com',
                       'hsht6r2z9b@privaterelay.appleid.com',
                       'joohami0806@gmail.com')
       and not exists (select 1 from public.user_subscriptions s
                        where s.user_id = u.id
                          and s.status in ('active', 'trialing', 'grace'))
  loop
    perform public.grant_credits(
      r.id, 300, 'grant'::public.ledger_kind,
      'goodwill_grant', 'migration',
      'goodwill_first_call:' || r.id::text,
      jsonb_build_object('reason', 'first call cut early on 1.0.5',
                         'migration', '20260921090000'));
  end loop;
end $$;
