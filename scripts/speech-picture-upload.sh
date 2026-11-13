#!/bin/bash
# Puts speech challenge pictures in R2, where the speech app fetches them
# (`ChallengeArt`, 2026-11-13): nawana-shows/speech/pictures/<challenge id>.png.
# A picture put again under the same id replaces the old one on every phone
# within a launch (the app revalidates by ETag), so a redraw needs no build.
#
#   scripts/speech-picture-upload.sh <challenge id> <png>    one picture
#   scripts/speech-picture-upload.sh --bundled               every picture in
#       SpeechApp/Illustrations (challenge-<LAST4>.png), as the English ids
#       5beec000-0000-4000-8000-00000000<LAST4>
#
# The png is 1024x1024 with the cream keyed to alpha (see the memory note on
# daily speech challenges for how it is drawn and keyed).
set -euo pipefail
BUCKET="${BUCKET:-nawana-shows}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
cd "$ROOT/gateway"

put() {  # <challenge id> <png>
  local id; id="$(echo "$1" | tr 'A-Z' 'a-z')"
  [[ "$id" =~ ^[0-9a-f-]{36}$ ]] || { echo "not a challenge id: $1" >&2; exit 1; }
  npx wrangler r2 object put "$BUCKET/speech/pictures/$id.png" --file "$2" \
    --content-type image/png --cache-control "public, max-age=3600" --remote >/dev/null
  echo "put $id"
}

if [[ "${1:-}" == "--bundled" ]]; then
  for f in "$ROOT"/SpeechApp/Illustrations/challenge-*.png; do
    last4="$(basename "$f" .png)"; last4="${last4#challenge-}"
    put "5beec000-0000-4000-8000-0000000$(printf '%05s' "$last4" | tr ' ' 0)" "$f"
  done
else
  put "${1:?usage: speech-picture-upload.sh <challenge id> <png> | --bundled}" "${2:?png}"
fi
