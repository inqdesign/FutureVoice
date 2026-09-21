#!/usr/bin/env bash
# Build the admin console's page.
#
#   ./scripts/admin/refresh.sh
#
# The page is ONE file — `scripts/admin/page.html` — and the Worker serves it
# with the data blob substituted for `__ADMIN_DATA__` at request time. So this
# script is a copy plus two guards.
#
# It used to be four Python steps over `base.html` plus 1,165 lines of string
# surgery in `merge_admin.py`; that pipeline is what let the page grow to five
# tabs and twenty-five sections nobody could see at once. Both files were
# retired on 2026-09-14 and live in git history.
#
# There is no offline snapshot any more either. It existed because the console
# used to be a static artifact someone had to remember to republish, which is
# the exact failure the live Worker was built to end.
set -euo pipefail
cd "$(dirname "$0")"
SRC=page.html
DEST=../../admin/src/shell.html

grep -q '__ADMIN_DATA__' "$SRC" || { echo "!! $SRC has no __ADMIN_DATA__ placeholder" >&2; exit 1; }
# The shell is committed, so a real address in it would be a leak in git.
if grep -oE '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}' "$SRC" | grep -v '@example\.com' | head -1 | grep -q .; then
  echo "!! $SRC contains an email address — the page must hold no data" >&2; exit 1
fi

cp "$SRC" "$DEST"
echo "wrote $DEST ($(wc -c < "$DEST" | tr -d ' ') bytes, no data)"

echo
echo "→ live: bash admin/deploy.sh"
