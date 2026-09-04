#!/usr/bin/env bash
# Rebuild the admin console's page from production.
#
#   ./scripts/admin/refresh.sh
#
# The console itself is LIVE now (admin/ — a Worker that reads production on
# every load), so this is no longer how the numbers get updated. What it still
# does is rebuild the PAGE: base.html + merge_admin.py produce the page, and
# make_shell.py strips the data out of it to give the Worker its shell. Run
# this after editing base.html or merge_admin.py, then `bash admin/deploy.sh`.
#
# It also leaves build/admin.html, a self-contained snapshot with the numbers
# baked in — the offline fallback, and what the old artifact was.
set -euo pipefail
cd "$(dirname "$0")"
python3 derive_cost.py
python3 gather_admin.py
python3 merge_admin.py
python3 make_shell.py
echo
echo "→ live:     bash admin/deploy.sh   (serves admin/src/shell.html)"
echo "→ snapshot: $(cd build && pwd)/admin.html"
