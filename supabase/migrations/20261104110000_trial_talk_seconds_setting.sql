-- ---------------------------------------------------------------------------
-- 2026-11-04: written as 20261022120000, the same version as
-- 20261022120000_speech_challenge_cabin_announcement, which was the one
-- recorded — so this file NEVER RAN in production (no
-- billing_config.trial_talk_seconds, no trial_talk_seconds()). Harmless so
-- far: no row is trialing and the store trial is off (2026-11-03), but
-- `billing-switch.py trial-minutes` fails until it is applied. Renamed to its
-- own version; NOT applied yet — it rewrites four live billing functions from
-- their definitions, so apply it deliberately, not as part of this fix.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- The trial's talk time as a SETTING (2026-10-22).
--
-- Founder: "5 free minutes, then a trial with 60 minutes — and the trial's
-- size changeable any time without a build." Until now a trialing row was
-- metered at Light's month × 7/30 (35 min) whatever the trial's length, and
-- that expression was written out in four functions: the meter
-- (consume_metered_seconds), what the app shows (talk_allowance), the
-- voiceover's wall (script_voiceover_wall) and the admin console (admin_raw).
--
-- `billing_config.trial_talk_seconds` (NULL = the old 7/30 rule) now decides
-- it, through ONE helper the four call, so they can't disagree. The four are
-- rewritten in place from their live definitions — only the trial
-- expression changes, and the block fails loudly if it is not found, rather
-- than leaving one of them on the old rule.
--
-- Scenes during a trial keep their own count (begin_scene_play /
-- scene_allowance): a learner billed in minutes for scenes spends this same
-- pool, so a bigger trial is bigger for scenes too.
--
-- Requires 20261021120000_billing_config.
-- ---------------------------------------------------------------------------

alter table public.billing_config
  add column if not exists trial_talk_seconds integer
    check (trial_talk_seconds is null or trial_talk_seconds between 0 and 36000);

-- What a trialing subscription may talk in its whole trial.
--   p_stamp: user_subscriptions.monthly_seconds (a size stamped on the row)
--   p_plan:  the plan's own monthly_seconds
create or replace function public.trial_talk_seconds(p_stamp integer, p_plan integer)
returns integer
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select c.trial_talk_seconds from public.billing_config c where c.id),
    coalesce(p_stamp,
             (select min(monthly_seconds) from public.subscription_plans where tier = 'light'),
             p_plan) * 7 / 30);
$$;

grant execute on function public.trial_talk_seconds(integer, integer) to anon, authenticated, service_role;

do $$
declare
  fn text;
  def text;
  rewritten text;
  pattern constant text :=
    'coalesce\(s\.monthly_seconds,\s*\(select\s+min\(monthly_seconds\)\s+from\s+(public\.)?subscription_plans\s+where\s+tier\s*=\s*''light''\),\s*p\.monthly_seconds\)\s*\*\s*7\s*/\s*30';
begin
  foreach fn in array array[
    'public.consume_metered_seconds(uuid,integer,text,text,text,text,jsonb)',
    'public.talk_allowance()',
    'public.script_voiceover_wall(uuid,integer)',
    'public.admin_raw()'
  ] loop
    def := pg_get_functiondef(fn::regprocedure);
    rewritten := regexp_replace(def, pattern,
                   'public.trial_talk_seconds(s.monthly_seconds, p.monthly_seconds)', 'g');
    if rewritten = def then
      raise exception 'trial rule not found in %', fn;
    end if;
    execute rewritten;
  end loop;
end $$;
