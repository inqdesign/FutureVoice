-- One more month-free Light code (2026-10-31): the ten from
-- 20261030160000_month_free_light_codes were all handed out. Same plan, same
-- rule (it replaces the 20 free minutes) and the same last day as the batch,
-- so the mail's "register by 11/29" holds.
insert into public.comp_codes (code, plan_id, months, max_redemptions, replaces_free_minutes, note, expires_at)
select 'FGUVC87T', 'light_monthly', 1, 1, true, 'month free: 5234065@naver.com',
       (select max(expires_at) from public.comp_codes where note like 'month free%')
on conflict (code) do nothing;
