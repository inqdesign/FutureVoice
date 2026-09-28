#!/usr/bin/env bash
# Voice parking (2026-09-28) — the deploy steps, one per subcommand, IN ORDER.
# See CLAUDE.md "A voice nobody pays for is PARKED".
#
#   bash scripts/park-voices.sh migrate    # 1. column + SQL functions + cron (disabled)
#   bash scripts/park-voices.sh verify     #    read-only: did it land, who would be parked
#   bash scripts/park-voices.sh functions  # 2. deploy the four edge functions
#   bash scripts/park-voices.sh gateway    # 3. deploy the gateway (drops live calls!)
#   ---- wait for the app build with VoiceParking to be LIVE in the App Store ----
#   bash scripts/park-voices.sh dry        # 4. ask the function who it WOULD park
#   bash scripts/park-voices.sh enable     # 5. switch the hourly cron on
#   bash scripts/park-voices.sh disable    #    switch it off again
#
# Order matters: functions/gateway select `parked_at`, so they must never be
# deployed before `migrate` (every TTS call would 500, every call would be
# voice_forbidden).
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_REF=chhzjtigzdotacutwcyo
raw="$(security find-generic-password -s "Supabase CLI" -w)"
TOKEN="$(echo "${raw#go-keyring-base64:}" | base64 -d)"

sql() {
  curl -sS -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -n --arg q "$1" '{query:$q}')"
  echo
}

case "${1:-}" in
  migrate)
    bash scripts/apply-migration.sh supabase/migrations/20260928140000_park_idle_voices.sql
    ;;
  verify)
    echo "== column"
    sql "select column_name from information_schema.columns where table_name='voice_clones' and column_name='parked_at'"
    echo "== functions"
    sql "select proname from pg_proc where proname in ('parkable_voice_owners','voice_clone_allowed','voice_owner_is_entitled') order by 1"
    echo "== cron (active should be false until step 5)"
    sql "select jobname, schedule, active from cron.job where jobname='park_idle_voices'"
    echo "== who would be parked now"
    sql "select rule, count(*) from public.parkable_voice_owners(7, 500) group by 1"
    echo "== already parked"
    sql "select count(*) from voice_clones where parked_at is not null"
    ;;
  functions)
    for fn in elevenlabs-tts elevenlabs-voice-clone elevenlabs-voice-delete park-idle-voices; do
      echo "== deploying $fn"
      supabase functions deploy "$fn" --project-ref "$PROJECT_REF"
    done
    ;;
  gateway)
    echo "This drops every live call. Ctrl-C within 5 s to abort."
    sleep 5
    (cd gateway && PATH=/opt/homebrew/opt/node@22/bin:$PATH npx wrangler deploy)
    ;;
  dry)
    secret="$(sql "select decrypted_secret from vault.decrypted_secrets where name='cleanup_secret'" | jq -r '.[0].decrypted_secret')"
    curl -sS -X POST "https://$PROJECT_REF.supabase.co/functions/v1/park-idle-voices?dry=1" \
      -H "X-Cleanup-Secret: $secret" -H "Content-Type: application/json" -d '{}' | jq .
    ;;
  enable|disable)
    active=$([[ "$1" == enable ]] && echo true || echo false)
    sql "select cron.alter_job(jobid, active := $active) from cron.job where jobname='park_idle_voices'"
    sql "select jobname, schedule, active from cron.job where jobname='park_idle_voices'"
    ;;
  *)
    sed -n 2,13p "$0"; exit 1
    ;;
esac
