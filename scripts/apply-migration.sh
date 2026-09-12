#!/usr/bin/env bash
# Apply ONE migration file to production and record it as applied.
#
#   bash scripts/apply-migration.sh supabase/migrations/20260910120000_standing_comps_roll.sql
#
# Why not `supabase db push`: it applies every unrecorded local migration in
# order, and this tree usually carries WIP ones that must not ship with a hot
# fix. This runs exactly the file named, through the Management API with the
# CLI's own keychain token (the same path scripts/beta.sh uses for
# app_release), then marks that single version applied so `db push` doesn't
# try it again later.
#
# The whole file runs as one statement string — a failure anywhere leaves
# nothing applied and the version unrecorded, so re-running is safe.
set -euo pipefail

PROJECT_REF=chhzjtigzdotacutwcyo
FILE="${1:?usage: apply-migration.sh <supabase/migrations/VERSION_name.sql>}"
[[ -f "$FILE" ]] || { echo "no such file: $FILE" >&2; exit 1; }
VERSION="$(basename "$FILE" | cut -d_ -f1)"
[[ "$VERSION" =~ ^[0-9]{14}$ ]] || { echo "not a migration filename: $FILE" >&2; exit 1; }

raw="$(security find-generic-password -s "Supabase CLI" -w)"
token="$(echo "${raw#go-keyring-base64:}" | base64 -d)"

payload="$(python3 - "$FILE" <<'PY'
import json, sys
print(json.dumps({"query": open(sys.argv[1]).read()}))
PY
)"

echo "▸ applying $VERSION to $PROJECT_REF"
resp="$(curl -s -w '\n%{http_code}' -X POST \
  "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
  -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
  --data-binary "$payload")"
code="${resp##*$'\n'}"
body="${resp%$'\n'*}"
if [[ "$code" != "200" && "$code" != "201" ]]; then
  echo "  ! HTTP $code — nothing applied, version not recorded" >&2
  echo "$body" >&2
  exit 1
fi
echo "  ok"

echo "▸ recording $VERSION as applied"
supabase migration repair --status applied "$VERSION" >/dev/null
echo "  ok — run 'supabase migration list' to confirm"
