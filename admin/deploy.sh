#!/usr/bin/env bash
# Deploy the live admin console, or set one of its secrets.
#
#   bash admin/deploy.sh                            # push the current code
#   bash admin/deploy.sh secret SUPABASE_SERVICE_ROLE_KEY   # paste, then ⌃D
#   bash admin/deploy.sh tail                       # live logs
#
# Wrangler needs Node 22 and the repo's default `node` is 20, so the PATH is
# fixed here rather than left to whoever is at the keyboard. There is no
# node_modules of our own — the gateway Worker already has wrangler.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
W=../gateway/node_modules/.bin/wrangler

case "${1:-deploy}" in
  deploy) "$W" deploy ;;
  secret) shift; "$W" secret put "$1" ;;
  tail)   "$W" tail ;;
  *) echo "usage: deploy.sh [deploy|secret NAME|tail]" >&2; exit 2 ;;
esac
