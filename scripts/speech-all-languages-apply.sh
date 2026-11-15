#!/bin/bash
# Every target language gets the speech challenges English has (founder,
# 2026-11-15). Applies the seven migrations of that day to production, then
# gives every challenge its English sibling's picture in R2.
#
#   scripts/speech-all-languages-apply.sh --dry-run   prints what it would do
#   scripts/speech-all-languages-apply.sh             asks once, then runs
#
# Safe to run twice: every insert is `on conflict do nothing`, a migration already
# recorded under its own name is skipped (another name is refused), and a picture upload overwrites the same
# file. Runs the files as committed (HEAD), never a working-tree edit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MIGRATIONS=(
  20261115100000_speech_interstellar_film_critic.sql
  20261115110000_speech_challenges_de_catch_up.sql
  20261115120000_speech_challenges_es_catch_up.sql
  20261115130000_speech_challenges_fr_catch_up.sql
  20261115140000_speech_challenges_ja_catch_up.sql
  20261115150000_speech_challenges_ko_catch_up.sql
  20261115160000_speech_challenges_zh.sql
)

for m in "${MIGRATIONS[@]}"; do
  f="supabase/migrations/$m"
  git cat-file -e "HEAD:$f" 2>/dev/null || { echo "not committed: $f" >&2; exit 1; }
  git diff --quiet HEAD -- "$f" || { echo "has uncommitted edits: $f" >&2; exit 1; }
done

echo "Migrations (production):"
for m in "${MIGRATIONS[@]}"; do echo "  $m"; done
echo "Pictures (R2):"
bash scripts/speech-picture-siblings.sh --dry-run | sed 's/^/ /'
[[ "${1:-}" == "--dry-run" ]] && exit 0

read -r -p "Apply ${#MIGRATIONS[@]} migrations and upload the pictures? [y/N] " ok
ok="$(printf '%s' "$ok" | tr -cd 'A-Za-zㅛ' | tr 'A-Z' 'a-z')"
[[ "$ok" == "y" || "$ok" == "yes" || "$ok" == "ㅛ" ]] || { echo "nothing done"; exit 0; }

raw="$(security find-generic-password -s "Supabase CLI" -w)"
token="$(echo "${raw#go-keyring-base64:}" | base64 -d)"
recorded_name() {
  curl -s -X POST \
    "https://api.supabase.com/v1/projects/chhzjtigzdotacutwcyo/database/query" \
    -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    -d "{\"query\":\"select name from supabase_migrations.schema_migrations where version = '$1'\"}"
}

for m in "${MIGRATIONS[@]}"; do
  echo "== $m"
  version="${m%%_*}"; name="${m#*_}"; name="${name%.sql}"
  # A version already recorded under THIS file's name was applied by an
  # earlier run: skip it. Under another name, apply-migration.sh refuses.
  if [[ "$(recorded_name "$version")" == "[{\"name\":\"$name\"}]" ]]; then
    echo "  already applied, skipped"
    continue
  fi
  bash scripts/apply-migration.sh "supabase/migrations/$m"
done

# The picture script asks again on its own; answer it for the learner who
# already said yes above.
echo y | bash scripts/speech-picture-siblings.sh
echo "done: reopen the Speech tab in each language"
