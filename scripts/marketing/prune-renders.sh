#!/usr/bin/env bash
# Delete a piece's local renders/ once its media is in R2 (marketing/AUTOMATION.md §1, "Disk").
#
#   scripts/marketing/prune-renders.sh <slug>
#
# The one delete the headless marketing run is allowed: it refuses unless the
# piece's slides are registered in the database with media keys, and it only
# ever removes marketing/content/<slug>/renders.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
slug=${1:?usage: prune-renders.sh <slug>}
[[ "$slug" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "✗ odd slug '$slug'" >&2; exit 2; }
dir="$ROOT/marketing/content/$slug/renders"
[[ -d "$dir" ]] || { echo "nothing to prune ($dir)"; exit 0; }

n=$(python3 "$ROOT/scripts/marketing/db.py" get "$slug" | python3 -c '
import json, sys
s = json.load(sys.stdin).get("slides") or []
print(sum(1 for x in s if x.get("mp4") or x.get("jpg") or x.get("png")))')
[[ "$n" -gt 0 ]] || { echo "✗ $slug has no slides with media in the database — upload first (media.sh --set-slides)" >&2; exit 1; }

size=$(du -sh "$dir" | cut -f1)
rm -rf "$dir"
echo "✓ removed $dir ($size); $n slides live in R2"
