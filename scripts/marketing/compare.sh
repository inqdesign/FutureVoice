#!/bin/bash
# compare.sh <tag> <pose> <capture.png> <out.png> [lang=ko]
# Renders a web/kit screen posed (no animation) at the capture's resolution (402×874 @3x)
# and writes   capture | kit   side by side, a third of full size. Read the image, fix, repeat.
set -euo pipefail
TAG=$1; POSE=$2; CAP=$3; OUT=$4; LANG_=${5:-ko}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
/opt/homebrew/opt/node@22/bin/node "$ROOT/scripts/marketing/record.mjs" \
  "web/kit/_harness.html?tag=$TAG&pose=$POSE&lang=$LANG_" --size 402x874 --scale 3 \
  --seconds 0.3 --warmup 1.5 --out "$TMP/kit.png" >/dev/null
python3 - "$CAP" "$TMP/kit.png" "$OUT" <<'PY'
import sys
from PIL import Image
a=Image.open(sys.argv[1]).convert('RGB').resize((1206,2622)); b=Image.open(sys.argv[2]).convert('RGB').resize((1206,2622))
W=Image.new('RGB',(1206*2+30,2622),'red'); W.paste(a,(0,0)); W.paste(b,(1236,0))
W.resize((W.width//3,W.height//3)).save(sys.argv[3])
PY
rm -rf "$TMP"; echo "$OUT"
