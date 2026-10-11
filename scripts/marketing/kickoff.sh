#!/usr/bin/env bash
# Start the marketing team for a build, headless, in the background (marketing/AUTOMATION.md §1).
#
#   scripts/marketing/kickoff.sh upload  <version> <build>   # scripts/beta.sh, after a TestFlight upload
#   scripts/marketing/kickoff.sh release <version> <build>   # scripts/release-watch.sh, after `beta.sh released`
#
# Returns at once. The run is `claude -p "/marketing auto <phase> <version> <build>"`
# from the repo root, logged to marketing/logs/<date>-<phase>-<version>.log, with a
# `run_start` and a `run_end` event (piece_id NULL) in marketing_events.
#
# One run per phase+version at a time: a second kickoff while the first is alive
# exits without starting anything. MARKETING_AUTOPILOT=0 disables it entirely.
#
# Permissions: the headless lead may run the mkt-* agents and edit files, and in the
# shell only the tools below — no git writes, no deploys, no posting, no publishing
# community news, no deletes beyond prune-renders.sh.
set -euo pipefail

[[ "${MARKETING_AUTOPILOT:-1}" == "0" ]] && { echo "marketing autopilot off (MARKETING_AUTOPILOT=0)"; exit 0; }

phase=${1:-}; version=${2:-}; build=${3:-}
[[ "$phase" == upload || "$phase" == release ]] || { echo "usage: kickoff.sh upload|release <version> <build>" >&2; exit 2; }
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "✗ odd version '$version'" >&2; exit 2; }
[[ "$build" =~ ^[0-9]+$ ]] || { echo "✗ odd build '$build'" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLAUDE=${CLAUDE_BIN:-/Users/eunggyuelee/.local/bin/claude}
LOGDIR="$ROOT/marketing/logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/$(date +%F)-$phase-$version.log"
LOCK="$LOGDIR/.run-$phase-$version.lock"   # a directory: mkdir is atomic
[[ -x "$CLAUDE" ]] || { echo "✗ claude not found at $CLAUDE" >&2; exit 1; }

# launchd hands release-watch a bare PATH; the team needs node 22, ffmpeg, python3.
export PATH="/opt/homebrew/opt/node@22/bin:/Users/eunggyuelee/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if ! mkdir "$LOCK" 2>/dev/null; then
  pid=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "marketing $phase $version already running (pid $pid) — not starting another"
    exit 0
  fi
  rm -rf "$LOCK"                      # stale: the run that held it is gone
  mkdir "$LOCK" || { echo "✗ could not take $LOCK" >&2; exit 1; }
fi

ALLOWED=(
  "Agent" "Read" "Write" "Edit" "Glob" "Grep" "Skill"
  "Bash(python3 scripts/marketing/db.py:*)"
  "Bash(scripts/marketing/media.sh:*)"
  "Bash(bash scripts/marketing/media.sh:*)"
  "Bash(scripts/marketing/prune-renders.sh:*)"
  "Bash(bash scripts/marketing/prune-renders.sh:*)"
  "Bash(scripts/marketing/capture.sh:*)"
  "Bash(scripts/marketing/compare.sh:*)"
  "Bash(/opt/homebrew/opt/node@22/bin/node scripts/marketing/record.mjs:*)"
  "Bash(node scripts/marketing/record.mjs:*)"
  "Bash(python3 scripts/marketing/metrics.py --dry-run)"
  "Bash(python3 scripts/marketing/scheduler.py --dry-run)"
  "Bash(ffmpeg:*)"
  "Bash(ffprobe:*)"
  "Bash(git log:*)"
  "Bash(git diff:*)"
  "Bash(git show:*)"
  "Bash(ls:*)"
  "Bash(cat:*)"
  "Bash(sips:*)"
  "Bash(python3 scripts/community.py news-add:*)"
)
# Deny wins over allow: a news draft is fine, publishing it is the founder's.
DENIED=(
  "Bash(python3 scripts/community.py news-add * --publish*)"
  "Bash(python3 scripts/community.py news-publish:*)"
)
DB="$ROOT/scripts/marketing/db.py"
label="$phase $version ($build)"

cd "$ROOT"
# The run's own command line is handed in as "$@", so every rule stays one argument.
LOCK="$LOCK" LOG="$LOG" DB="$DB" LABEL="$label" nohup bash -c '
  set -u
  echo $$ > "$LOCK/pid"
  trap "rm -rf \"$LOCK\"" EXIT
  echo "=== $(date "+%F %T") marketing $LABEL"
  python3 "$DB" event - run_start "$LABEL · log $(basename "$LOG")" || true
  "$@"
  rc=$?
  echo "=== $(date "+%F %T") exit $rc"
  python3 "$DB" event - run_end "$LABEL · exit $rc" || true
' kickoff "$CLAUDE" -p "/marketing auto $phase $version $build" \
    --permission-mode acceptEdits \
    --allowedTools "${ALLOWED[@]}" \
    --disallowedTools "${DENIED[@]}" \
  >>"$LOG" 2>&1 </dev/null &
pid=$!
echo "$pid" > "$LOCK/pid" 2>/dev/null || true
disown "$pid" 2>/dev/null || true
echo "▸ marketing $label started in the background (pid $pid) — $LOG"
