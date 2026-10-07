#!/usr/bin/env bash
# Copies the repo's hooks into the SHARED hooks dir, so every worktree
# (planner, speech, release, android) runs them. A copy, not a symlink: a
# worktree on a branch without scripts/hooks must not find a dangling hook.
# Re-run after editing a hook.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dest="$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)/hooks"
mkdir -p "$dest"
for h in commit-msg; do
  install -m 0755 "$here/$h" "$dest/$h"
  echo "✓ $h → $dest/$h"
done
