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
# Ids: ko ja de es (earliest four), then the per-language blocks from
# 2026-11-15 (founder: every language gets every challenge):
# fr 0f, ja 0a, ko 0c, de 0d, es 0e, zh 0b (zh's first one is the app's
# bundled sample, ...0000000b0001).
pairs=(
  "0001:000000000002 000000000003 000000000004 000000000009 0000000f0001 0000000b0001"   # why practise out loud
  "0005:000000000006 000000000007 000000000008 00000000000a 0000000f0002 0000000b0005"   # can languages keep you young
  "000B:00000000000c 00000000000d 00000000000e 00000000000f 0000000f000b 0000000b000b"   # nervous? say you're excited
  "0010:000000000011 000000000012 000000000013 000000000014 0000000f0010 0000000b0010"   # welcome aboard
  "0020:0000000a0020 0000000b0020 0000000c0020 0000000d0020 0000000e0020 0000000f0020"   # morning show
  "0024:0000000a0024 0000000b0024 0000000c0024 0000000d0024 0000000e0024 0000000f0024"   # acceptance
  "0025:0000000a0025 0000000b0025 0000000c0025 0000000d0025 0000000e0025 0000000f0025"   # podcast
  "002B:0000000a002b 0000000b002b 0000000c002b 0000000d002b 0000000e002b 0000000f002b"   # docent
  "002C:0000000a002c 0000000b002c 0000000c002c 0000000d002c 0000000e002c 0000000f002c"   # weather
  "002D:0000000a002d 0000000b002d 0000000c002d 0000000d002d 0000000e002d 0000000f002d"   # film critic
  "002E:0000000a002e 0000000b002e 0000000c002e 0000000d002e 0000000e002e 0000000f002e"   # wedding, best friend
)

for pair in "${pairs[@]}"; do
  pic="${pair%%:*}"
  for s in ${pair#*:}; do echo "  $P$s  ←  challenge-$pic.png"; done
done
[[ "${1:-}" == "--dry-run" ]] && exit 0

n=0; for pair in "${pairs[@]}"; do for s in ${pair#*:}; do n=$((n+1)); done; done
read -r -p "Upload these $n pictures to R2? [y/N] " ok
# Keep only letters (a pasted or IME-typed answer can carry invisible
# characters); ㅛ is y on a Korean keyboard.
ok="$(printf '%s' "$ok" | tr -cd 'A-Za-zㅛ' | tr 'A-Z' 'a-z')"
[[ "$ok" == "y" || "$ok" == "yes" || "$ok" == "ㅛ" ]] || { echo "nothing uploaded"; exit 0; }

for pair in "${pairs[@]}"; do
  pic="${pair%%:*}"
  for s in ${pair#*:}; do "$ROOT/scripts/speech-picture-upload.sh" "$P$s" "$I/challenge-$pic.png"; done
done
echo "done: reopen the Speech tab (pictures refresh on the next launch)"
