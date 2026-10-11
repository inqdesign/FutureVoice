#!/usr/bin/env bash
# Upload a piece's rendered slides to R2 (marketing/AUTOMATION.md §4).
#
#   scripts/marketing/media.sh [--set-slides] [--dry-run] <slug> <file>…
#
#   bucket   nawana-marketing  (bound to the admin Worker as MEDIA)
#   key      <slug>/<file name>
#   served   https://nawana.app/admin/media/<slug>/<file name>
#
# For every PNG it also makes and uploads two JPEGs, because Instagram's
# publishing API takes JPEG only and the community page wants half size:
#   NN.png → NN.jpg      1080×1350, quality 90   (what Instagram/Threads post for an image slide)
#          → NN-web.jpg  720×900,   quality 82   (the community page)
#
# Prints the slides as JSON on the last line ([{n, kind, mp4, png, jpg, jpg_web}],
# grouped by file stem, n = the stem's number). With --set-slides it also merges
# them into the piece (db.py slides-merge — alt_ko/alt_en already there survive)
# and logs a `media` event.
#
# Wrangler is the gateway's (no node_modules of our own) and needs Node 22.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
W="$ROOT/gateway/node_modules/.bin/wrangler"
BUCKET=nawana-marketing
DB="$ROOT/scripts/marketing/db.py"

set_slides=0; dry=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --set-slides) set_slides=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n 2,20p "$0"; exit 0 ;;
    *) echo "unknown flag $1" >&2; exit 2 ;;
  esac
  shift
done
[[ $# -ge 2 ]] || { sed -n 2,20p "$0" >&2; exit 2; }
slug=$1; shift
[[ "$slug" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "✗ odd slug '$slug'" >&2; exit 2; }
[[ -x "$W" ]] || { echo "✗ wrangler not found at $W (npm ci in gateway/)" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/nawana-media.XXXXXX"); trap 'rm -rf "$work"' EXIT

ctype() {
  case "${1##*.}" in
    mp4) echo video/mp4 ;; mov) echo video/quicktime ;;
    png) echo image/png ;; jpg|jpeg) echo image/jpeg ;; webp) echo image/webp ;;
    gif) echo image/gif ;; json) echo application/json ;; *) echo application/octet-stream ;;
  esac
}

put() {  # put <local file> <file name in the piece>
  local f=$1 name=$2 key="$slug/$2" t
  t=$(ctype "$name")
  if (( dry )); then echo "would put $key ($t, $(du -h "$f" | cut -f1))" >&2; return; fi
  ( cd "$ROOT/admin" && "$W" r2 object put "$BUCKET/$key" --file "$f" --content-type "$t" --remote >/dev/null ) \
    || { echo "✗ upload failed: $key" >&2; return 1; }
  echo "✓ $key" >&2
}

# jpeg <src png> <dst> <width> <height> <quality>
jpeg() {
  local src=$1 dst=$2 w=$3 h=$4 q=$5
  if command -v sips >/dev/null; then
    sips -s format jpeg -s formatOptions "$q" -z "$h" "$w" "$src" --out "$dst" >/dev/null
  else
    python3 - "$src" "$dst" "$w" "$h" "$q" <<'PY'
import sys
from PIL import Image
s, d, w, h, q = sys.argv[1:]
Image.open(s).convert("RGB").resize((int(w), int(h)), Image.LANCZOS).save(d, "JPEG", quality=int(q))
PY
  fi
}

names=()
for f in "$@"; do
  [[ -f "$f" ]] || { echo "✗ no such file $f" >&2; exit 1; }
  base=$(basename "$f"); stem="${base%.*}"; ext="${base##*.}"
  put "$f" "$base"; names+=("$base")
  if [[ "$ext" == png ]]; then
    jpeg "$f" "$work/$stem.jpg" 1080 1350 90
    put "$work/$stem.jpg" "$stem.jpg"; names+=("$stem.jpg")
    jpeg "$f" "$work/$stem-web.jpg" 720 900 82
    put "$work/$stem-web.jpg" "$stem-web.jpg"; names+=("$stem-web.jpg")
  fi
done

slides=$(SLUG="$slug" python3 - "${names[@]}" <<'PY'
import json, os, re, sys
slug = os.environ["SLUG"]
by = {}
for name in sys.argv[1:]:
    stem, ext = name.rsplit(".", 1)
    web = stem.endswith("-web")
    stem = stem[:-4] if web else stem
    m = re.match(r"(\d+)", stem)
    if not m:
        continue                     # not a numbered slide (e.g. a cover note) — uploaded, not listed
    s = by.setdefault(int(m.group(1)), {"n": int(m.group(1))})
    key = f"{slug}/{name}"
    if ext == "mp4": s["mp4"] = key
    elif ext == "png": s["png"] = key
    elif ext in ("jpg", "jpeg"): s["jpg_web" if web else "jpg"] = key
for s in by.values():
    s["kind"] = "video" if "mp4" in s else "image"
print(json.dumps([by[n] for n in sorted(by)], ensure_ascii=False))
PY
)

if (( set_slides && !dry )); then
  python3 "$DB" slides-merge "$slug" "$slides" >&2
  python3 "$DB" event "$slug" media "uploaded ${#names[@]} files to r2://$BUCKET/$slug/" >&2
fi
echo "$slides"
