#!/usr/bin/env bash
# Put the friend-invite event on the server, in the one order that is safe.
#
#   bash scripts/invite-event-rollout.sh --dry-run    # what would happen
#   bash scripts/invite-event-rollout.sh              # do it, asking before each step
#
# RUN IT ONLY AFTER the app build with the event is live in the stores. The
# first migration (20261118170000) stops an invite paying at sign-up, and the
# builds before it still print "30 minutes when you sign up".
#
# What it does, from the commit at HEAD (never the working tree):
#   1. applies 20261118170000 (inviting is a subscriber's, pays on the
#      friend's first payment) and 20261119120000 (the half-price month);
#   2. deploys `invite-reward`;
#   3. pushes the event's words (scripts/invite-event-texts.json);
#   4. makes the store offers for the current percentage;
#   5. makes the App Store one-time codes and puts them on file.
#
# It does NOT switch the event on. Look at `scripts/invite-event.py`, then:
#   scripts/invite-event.py on --send
set -euo pipefail
PROJECT_REF=chhzjtigzdotacutwcyo
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
MIGRATIONS=(supabase/migrations/20261118170000_invite_pays_when_the_friend_subscribes.sql
            supabase/migrations/20261119120000_invite_half_price_month.sql)

say() { printf '\n== %s\n' "$*"; }
ask() { [[ $DRY == 1 ]] && { echo "   (dry run) would: $1"; return 1; }
        read -r -p "   $1? [y/N] " a; [[ "$a" == y || "$a" == Y ]]; }

cd "$ROOT"
for f in "${MIGRATIONS[@]}" supabase/functions/invite-reward/index.ts \
         scripts/invite-event.py scripts/invite-event-texts.json; do
  git cat-file -e "HEAD:$f" 2>/dev/null || { echo "$f is not committed at HEAD. Commit first."; exit 1; }
done
say "Shipping commit $(git rev-parse --short HEAD)"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git archive HEAD supabase scripts | tar -x -C "$TMP"

say "1. Migrations"
for m in "${MIGRATIONS[@]}"; do
  if ask "apply $(basename "$m")"; then bash "$TMP/scripts/apply-migration.sh" "$TMP/$m"; fi
done

say "2. The function"
if ask "deploy invite-reward"; then
  supabase functions deploy invite-reward --project-ref "$PROJECT_REF" --workdir "$TMP" --use-api
fi

say "3. The words"
python3 "$TMP/scripts/invite-event.py" texts
if ask "push these texts"; then python3 "$TMP/scripts/invite-event.py" texts --send; fi

say "4. The store offers"
python3 "$TMP/scripts/invite-event.py" offers 2>/dev/null \
  || echo "   (the preview needs the migrations of step 1 applied first)"
if ask "create these offers and point the event at them"; then
  python3 "$TMP/scripts/invite-event.py" offers --send
fi

say "5. The App Store one-time codes"
python3 "$TMP/scripts/invite-event.py" codes 2>/dev/null \
  || echo "   (the preview needs steps 1 and 4 done first)"
if ask "make the codes and put them on file"; then
  python3 "$TMP/scripts/invite-event.py" codes --send
fi

say "Done. The event is still OFF."
echo "   Check:      scripts/invite-event.py"
echo "   Switch on:  scripts/invite-event.py on --send"
