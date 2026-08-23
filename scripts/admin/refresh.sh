#!/usr/bin/env bash
# Rebuild the admin console from production and print the file to publish.
#
#   ./scripts/admin/refresh.sh
#
# Then publish build/admin.html to the SAME artifact URL (see
# memory: cost-dashboard / user-activity-dashboard) — a new URL splits the
# one place this is supposed to be.
set -euo pipefail
cd "$(dirname "$0")"
python3 derive_cost.py
python3 gather_admin.py
python3 merge_admin.py
echo
echo "→ publish: $(cd build && pwd)/admin.html"
