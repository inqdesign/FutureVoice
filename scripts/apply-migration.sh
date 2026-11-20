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

# One version, one file (2026-11-04). Two files sharing a version is how
# 20261012140000_plan_change_is_a_new_purchase and
# 20261022120000_trial_talk_seconds_setting never ran in production: the
# other file of the pair was recorded first, and every later look — `db push`,
# this script's own record step — took the version as done.
NAME="$(basename "$FILE" .sql | cut -d_ -f2-)"
twins="$(ls "$(dirname "$FILE")" | grep "^${VERSION}_" | grep -vx "$(basename "$FILE")" || true)"
if [[ -n "$twins" ]]; then
  echo "✗ another migration has version $VERSION: $twins" >&2
  echo "  give this file its own version (git mv) and run it again" >&2
  exit 1
fi

raw="$(security find-generic-password -s "Supabase CLI" -w)"
token="$(echo "${raw#go-keyring-base64:}" | base64 -d)"

recorded="$(curl -s -X POST \
  "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
  -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
  -d "{\"query\":\"select name from supabase_migrations.schema_migrations where version = '$VERSION'\"}")"
if [[ "$recorded" != "[]" ]]; then
  echo "✗ version $VERSION is already recorded in production: $recorded" >&2
  echo "  if that is another file, give this one its own version; nothing applied" >&2
  exit 1
fi

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
# Through the same Management API as the apply, not `supabase migration
# repair`: that one dials the session pooler on :5432, which refused every
# connection on 2026-09-28 while the API worked — the migration landed and
# the record didn't.
rec="$(curl -s -w '\n%{http_code}' -X POST \
  "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
  -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
  -d "{\"query\":\"insert into supabase_migrations.schema_migrations (version, name) values ('$VERSION', '$NAME')\"}")"
if [[ "${rec##*$'\n'}" != "200" && "${rec##*$'\n'}" != "201" ]]; then
  echo "  ! applied, but NOT recorded: ${rec%$'\n'*}" >&2
  exit 1
fi
echo "  ok"
