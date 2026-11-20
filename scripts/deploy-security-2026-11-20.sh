#!/usr/bin/env bash
# Deploys the 2026-11-20 security fixes that need the founder's hands
# (commits d29da66f, 82627bb5, b01a3f17). Order matters: the functions go
# first, then the migrations; the voice_clones one last, because it takes
# away a write the OLD functions still used.
#   ./scripts/deploy-security-2026-11-20.sh --dry-run
#   ./scripts/deploy-security-2026-11-20.sh
set -euo pipefail
cd "$(dirname "$0")/.."
REF=chhzjtigzdotacutwcyo
FUNCS=(talk-tick tts voice-clone voice-remix voice-rename voice-delete stripe-checkout stripe-portal)
MIGS=(
  supabase/migrations/20261120110000_charge_talk_seconds_is_the_servers.sql
  supabase/migrations/20261120120000_a_replayed_key_counts.sql
  supabase/migrations/20261120130000_voice_clones_written_by_the_server.sql
)

if ! git diff --quiet HEAD -- supabase/functions/_shared "${FUNCS[@]/#/supabase/functions/}" "${MIGS[@]}"; then
  echo "Uncommitted changes in these files; deploy only HEAD. Stopping." >&2; exit 1
fi

echo "Functions:  ${FUNCS[*]}"
printf 'Migration:  %s\n' "${MIGS[@]}"
[[ "${1:-}" == "--dry-run" ]] && exit 0
read -r -p "Deploy to production? [y/N] " a; [[ "$a" == y ]] || exit 0

for f in "${FUNCS[@]}"; do
  echo "== $f"; supabase functions deploy "$f" --project-ref "$REF"
done
for m in "${MIGS[@]}"; do
  echo "== $m"; bash scripts/apply-migration.sh "$m"
done
echo "Done."
