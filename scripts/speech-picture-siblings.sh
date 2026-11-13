#!/bin/bash
# The same challenge in another language wears the English one's picture
# (2026-11-14, founder: every non-English card was blank). Pictures are keyed
# by challenge id in R2, and only the English ids had one; this copies the
# English picture to each sibling id. Both apps read R2, so no build needed.
#
#   scripts/speech-picture-siblings.sh            asks once, then uploads
#   scripts/speech-picture-siblings.sh --dry-run  prints what it would put
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
I="$ROOT/SpeechApp/Illustrations"
P=5beec000-0000-4000-8000-

# english picture : sibling ids (ko ja de es fr, as they exist)
pairs=(
  "0001:000000000002 000000000003 000000000004 000000000009 0000000f0001"   # why practise out loud
  "0005:000000000006 000000000007 000000000008 00000000000a 0000000f0002"   # can languages keep you young
  "000B:00000000000c 00000000000d 00000000000e 00000000000f"                # nervous? say you're excited
  "0010:000000000011 000000000012 000000000013 000000000014"                # welcome aboard
)

for pair in "${pairs[@]}"; do
  pic="${pair%%:*}"
  for s in ${pair#*:}; do echo "  $P$s  ←  challenge-$pic.png"; done
done
[[ "${1:-}" == "--dry-run" ]] && exit 0

read -r -p "Upload these 18 pictures to R2? [y/N] " ok
[[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "nothing uploaded"; exit 0; }

for pair in "${pairs[@]}"; do
  pic="${pair%%:*}"
  for s in ${pair#*:}; do "$ROOT/scripts/speech-picture-upload.sh" "$P$s" "$I/challenge-$pic.png"; done
done
echo "done: reopen the Speech tab (pictures refresh on the next launch)"
