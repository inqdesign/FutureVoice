#!/usr/bin/env bash
# Applies the two billing migrations that never ran in production
# (2026-11-14). Neither is needed by any build; both are server rules.
#
#   scripts/apply-billing-migrations.sh            # checks, shows, asks, applies
#   scripts/apply-billing-migrations.sh --dry-run  # checks and shows, applies nothing
#
#   1. 20261104110000_trial_talk_seconds_setting
#      A trial's talk time becomes a setting (billing_config.trial_talk_seconds,
#      NULL = today's 7/30 rule, so nothing changes until it is set). Rewrites
#      four live functions (consume_metered_seconds, talk_allowance,
#      script_voiceover_wall, admin_raw) and fails as a whole if the trial
#      rule isn't found in any one of them. Makes `billing-switch.py
#      trial-minutes` work.
#   2. 20261107100000_plan_change_leaves_scene_count
#      A plan change also removes the account from scene_count_billing, so
#      after an upgrade or downgrade Watch scenes cost talk minutes like any
#      new subscriber's (founder, 11-07).
#
# Both run from the COMMITTED tree (HEAD), one file at a time through
# scripts/apply-migration.sh; one already recorded is skipped.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_REF="chhzjtigzdotacutwcyo"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
MIGRATIONS=(
  supabase/migrations/20261104110000_trial_talk_seconds_setting.sql
  supabase/migrations/20261107100000_plan_change_leaves_scene_count.sql
)

RAW=$(security find-generic-password -s "Supabase CLI" -w)
TOKEN=$(echo "${RAW#go-keyring-base64:}" | base64 -d)
sql() {
  curl -s -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$1")"
}
one() { python3 -c 'import json,sys; r=json.load(sys.stdin); print(list(r[0].values())[0] if isinstance(r,list) and r else ("-" if r==[] else "ERR "+str(r)))'; }
recorded() { sql "select name from supabase_migrations.schema_migrations where version='$1'" | one; }

cd "$ROOT"
HEAD_SHA=$(git rev-parse --short HEAD)
for m in "${MIGRATIONS[@]}"; do
  git cat-file -e "HEAD:$m" || { echo "$m is not committed at HEAD ($HEAD_SHA)"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git archive HEAD "${MIGRATIONS[@]}" scripts/apply-migration.sh | tar -x -C "$TMP"

# The trial rewrite needs its pattern in all four functions; say so before asking.
PATTERN="coalesce\\(s\\.monthly_seconds,\\s*\\(select\\s+min\\(monthly_seconds\\)\\s+from\\s+(public\\.)?subscription_plans\\s+where\\s+tier\\s*=\\s*''light''\\),\\s*p\\.monthly_seconds\\)\\s*\\*\\s*7\\s*/\\s*30"
printf '\n== Production now (commit %s)\n' "$HEAD_SHA"
todo=()
for m in "${MIGRATIONS[@]}"; do
  v=$(basename "$m" | cut -d_ -f1)
  r=$(recorded "$v")
  if [ "$r" = "-" ]; then echo "  $(basename "$m" .sql): not applied"; todo+=("$m")
  else echo "  $(basename "$m" .sql): already applied ($r), skipped"; fi
done
for fn in 'public.consume_metered_seconds(uuid,integer,text,text,text,text,jsonb)' 'public.talk_allowance()' \
          'public.script_voiceover_wall(uuid,integer)' 'public.admin_raw()'; do
  f=$(sql "select pg_get_functiondef('$fn'::regprocedure) ~ '$PATTERN' as found" | one)
  echo "  trial rule in $fn: $f"
done
echo "  accounts on scene count billing: $(sql 'select count(*) from scene_count_billing' | one)"

[ ${#todo[@]} -eq 0 ] && { echo; echo "Nothing to apply."; exit 0; }
[ $DRY -eq 1 ] && { echo; echo "Dry run: nothing applied."; exit 0; }

echo
read -r -p "Apply ${#todo[@]} migration(s) to production? [y/N] " ok
ok="$(printf '%s' "$ok" | tr -cd 'A-Za-zㅛ' | tr 'A-Z' 'a-z')"
[[ "$ok" == "y" || "$ok" == "yes" || "$ok" == "ㅛ" ]] || { echo "nothing applied"; exit 0; }

for m in "${todo[@]}"; do
  (cd "$TMP" && bash scripts/apply-migration.sh "$m")
done

printf '\n== After\n'
echo "  trial_talk_seconds(): $(sql "select count(*) from pg_proc where proname='trial_talk_seconds'" | one) function"
echo "  billing_config.trial_talk_seconds: $(sql 'select coalesce(trial_talk_seconds::text, '"'"'NULL (7/30 rule, as before)'"'"') from billing_config limit 1' | one)"
echo "  plan change clears scene count: $(sql "select position('scene_count_billing' in pg_get_functiondef('public.clear_stamp_on_plan_change()'::regprocedure))>0" | one)"
echo "done"
