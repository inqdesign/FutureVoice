-- Ten more month-free Light codes (2026-10-31), dealt one by one as the
-- founder names people, so each new name is a mail and not a migration. The
-- first is already kyky8009@naver.com's. Same plan, same rule (replaces the
-- 20 free minutes) and the same last day as the first batch (11/29), which
-- the mail states. An unassigned note has no colon, so the admin console's
-- "month free:" lookup leaves it alone until a name is written in.
insert into public.comp_codes (code, plan_id, months, max_redemptions, replaces_free_minutes, note, expires_at)
select v.code, 'light_monthly', 1, 1, true, v.note,
       (select max(expires_at) from public.comp_codes where note like 'month free%')
from (values
  ('25FMB36S', 'month free: kyky8009@naver.com'),
  ('36M27EDW', 'month free spare 2 (unassigned)'),
  ('8SW9RQHW', 'month free spare 3 (unassigned)'),
  ('BDSZJG3Y', 'month free spare 4 (unassigned)'),
  ('EP5W8VJY', 'month free spare 5 (unassigned)'),
  ('N4UJ4FWT', 'month free spare 6 (unassigned)'),
  ('QPMGS8QT', 'month free spare 7 (unassigned)'),
  ('QV693BMW', 'month free spare 8 (unassigned)'),
  ('T867F3ZZ', 'month free spare 9 (unassigned)'),
  ('TGA8W8D9', 'month free spare 10 (unassigned)')
) as v(code, note)
on conflict (code) do nothing;
