#!/usr/bin/env bash
# Deploys the edge functions that must refuse anonymous sessions
# (2026-11-20, commit be87b153), then the migration that gives anonymous
# users no free seconds (20261120100000). Run from the repo, on HEAD.
#   ./scripts/deploy-anon-lockdown.sh --dry-run   # print what would run
#   ./scripts/deploy-anon-lockdown.sh
set -euo pipefail
cd "$(dirname "$0")/.."
REF=chhzjtigzdotacutwcyo
FUNCS=(talk-tick gemini tts translate word-entry pronunciation drill-enrichment
  scenario-curriculum topic-engine session-summary voicemail-script weekly-report
  script-study speech-cover speech-reference news-article news-topics field-topics library-add)
MIG=supabase/migrations/20261120100000_anonymous_sessions_get_no_free_minutes.sql

if ! git diff --quiet HEAD -- supabase/functions/_shared "${FUNCS[@]/#/supabase/functions/}"; then
  echo "Uncommitted changes in these functions; deploy only HEAD. Stopping." >&2; exit 1
fi

echo "Functions: ${FUNCS[*]}"
echo "Migration: $MIG"
[[ "${1:-}" == "--dry-run" ]] && exit 0
read -r -p "Deploy to production? [y/N] " a; [[ "$a" == y ]] || exit 0

for f in "${FUNCS[@]}"; do
  echo "== $f"; supabase functions deploy "$f" --project-ref "$REF"
done
bash scripts/apply-migration.sh "$MIG"
echo "Done."
