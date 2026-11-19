#!/usr/bin/env bash
# Fix a misspelling in the shared dictionary cache (`word_entry`), in
# production. The entries are written once by the model and read by every
# learner, so a typo stays until the row is changed (2026-11-19: "해깔리게"
# on the card for "string us along").
#
#   scripts/fix-word-entry-typo.sh                  # dry run: lists the rows
#   scripts/fix-word-entry-typo.sh --apply          # asks y/N, then fixes them
#   scripts/fix-word-entry-typo.sh 됬 됐 [--apply]  # another pair
#
# Replaces the text everywhere inside the entry (meanings, notes, example
# translations). Read the dry run first: every match is printed with the
# words around it.
set -euo pipefail

PROJECT_REF=chhzjtigzdotacutwcyo
FROM="해깔"; TO="헷갈"; APPLY=0
args=()
# zsh passes a pasted "# comment" as arguments: stop reading at a "#".
for a in "$@"; do
  [[ "$a" == \#* ]] && break
  [[ "$a" == "--apply" ]] && APPLY=1 || args+=("$a")
done
if [[ ${#args[@]} -eq 0 ]]; then :
elif [[ ${#args[@]} -eq 2 ]]; then FROM="${args[0]}"; TO="${args[1]}"
else echo "usage: $0 [<wrong> <right>] [--apply]" >&2; exit 1; fi
[[ "$FROM" != *"'"* && "$TO" != *"'"* && "$FROM" != *'"'* && "$TO" != *'"'* && "$FROM" != *'\'* && "$TO" != *'\'* ]] \
  || { echo "no quotes or backslashes in the words" >&2; exit 1; }
[[ ${#FROM} -ge 2 ]] || { echo "the wrong spelling must be at least 2 characters" >&2; exit 1; }

raw="$(security find-generic-password -s "Supabase CLI" -w)"
token="$(echo "${raw#go-keyring-base64:}" | base64 -d)"
q() {
  curl -sS -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
    -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$1")"
}

echo "Rows in word_entry containing \"$FROM\":"
rows="$(q "select word, native_lang, target_lang, kind,
                  substring(data::text from '.{0,30}$FROM.{0,20}') as around
           from public.word_entry where data::text like '%$FROM%'
           order by created_at")"
python3 - "$rows" <<'PY'
import json, sys
rows = json.loads(sys.argv[1])
if not isinstance(rows, list):
    print(rows); sys.exit(1)
for r in rows:
    print(f"  {r['word']}  [{r['target_lang']}→{r['native_lang']}, {r['kind']}]  …{r['around']}…")
print(f"{len(rows)} row(s)")
PY
count="$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$rows")"
[[ "$count" -gt 0 ]] || exit 0

if [[ $APPLY -eq 0 ]]; then
  echo "Dry run. To change \"$FROM\" to \"$TO\" in these rows: $0 ${args[*]:-} --apply"
  exit 0
fi
read -r -p "Change \"$FROM\" to \"$TO\" in $count row(s) in PRODUCTION? [y/N] " ok
[[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "nothing changed"; exit 0; }
q "update public.word_entry
     set data = replace(data::text, '$FROM', '$TO')::jsonb
   where data::text like '%$FROM%'" >/dev/null
left="$(q "select count(*)::int as n from public.word_entry where data::text like '%$FROM%'")"
echo "done. rows still containing \"$FROM\": $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[0]["n"])' "$left")"
