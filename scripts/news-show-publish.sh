#!/usr/bin/env bash
# Puts one day of the news show (made by scripts/news-show-probe.py) in R2,
# where the app reads it: shows/<lang>/latest.json plus every file it names.
#
#   scripts/news-show-publish.sh "~/Desktop/beta audio/news-show-2026-10-19"
#
# The bucket is `nawana-shows`, public through its r2.dev URL (set once by a
# person: `wrangler r2 bucket create nawana-shows` + `r2 bucket dev-url
# enable nawana-shows`). latest.json goes up LAST, so the app never reads a
# manifest whose files are still uploading.
set -euo pipefail

DAY_DIR="${1:?usage: news-show-publish.sh <day folder>}"
BUCKET="${BUCKET:-nawana-shows}"
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
cd "${GATEWAY_DIR:-$(dirname "$0")/../gateway}"

put() {  # <key> <file> <content-type> <cache-control>
  npx wrangler r2 object put "$BUCKET/$1" --file "$2" --content-type "$3" \
    --cache-control "$4" --remote >/dev/null
}

for lang_dir in "$DAY_DIR"/*/; do
  lang="$(basename "$lang_dir")"
  manifest="$lang_dir/show.json"
  [[ -f "$manifest" ]] || continue
  date="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["date"])' "$manifest")"
  count=0
  while IFS= read -r -d '' f; do
    rel="${f#"$lang_dir"}"
    put "shows/$lang/$date/$rel" "$f" audio/mpeg "public, max-age=31536000, immutable"
    count=$((count + 1))
  done < <(find "$lang_dir" -name '*.mp3' -print0)
  put "shows/$lang/latest.json" "$manifest" application/json "public, max-age=300"
  echo "[$lang] $date: $count audio files + latest.json"
done
