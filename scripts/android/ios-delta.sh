#!/usr/bin/env bash
# Superseded 2026-10-07 by the Android ledger in the iOS worktree, which reads
# the `Android:` line wherever it sits in the message (this script used git's
# trailer parser, which misses it whenever it is its own paragraph — most of
# them) and knows which todos an Android commit already closed.
#
#   scripts/android/ios-delta.sh [<from-ios-commit>]
set -euo pipefail
ios=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
ANDROID_LEDGER_START=${1:-} exec python3 "$ios/scripts/android-sync/ledger.py"
