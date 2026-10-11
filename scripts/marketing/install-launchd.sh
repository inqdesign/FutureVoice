#!/usr/bin/env bash
# Install (or reinstall) the marketing scheduler and metrics agents.
#
#   scripts/marketing/install-launchd.sh            # copy to ~/Library/LaunchAgents and load
#   scripts/marketing/install-launchd.sh uninstall  # unload and remove
#
# scheduler: every 15 min, posts pieces whose veto window is over
# metrics:   daily 09:00, collects views/engagement
# Logs: marketing/logs/{scheduler,metrics}.log
#
# Before loading: the migration is applied and ~/.config/nawana/marketing.env exists
# (see marketing/AUTOMATION.md §5). Try `python3 scripts/marketing/scheduler.py --dry-run` first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AGENTS="$HOME/Library/LaunchAgents"
mkdir -p "$AGENTS" "$ROOT/marketing/logs"

for name in scheduler metrics; do
  label="com.nawana.marketing-$name"
  dst="$AGENTS/$label.plist"
  launchctl unload "$dst" 2>/dev/null || true
  if [[ "${1:-}" == uninstall ]]; then
    rm -f "$dst"; echo "removed $label"; continue
  fi
  cp "$ROOT/scripts/marketing/launchd/$label.plist" "$dst"
  launchctl load "$dst"
  echo "loaded $label"
done
