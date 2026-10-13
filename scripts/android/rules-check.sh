#!/usr/bin/env bash
# The rule tests in one command (master plan 1.4 / 5단계):
#   1. compile the REAL Swift implementations and write the golden vectors
#   2. say whether any vector changed — a change means an iOS rule moved,
#      and the Android port now owes the same change
#   3. run the Android tests that read those vectors
#
# Every prompt Android sends is held to iOS at ONE pinned ref
# (scripts/android/promptgen/IOS_REF): each gen-*.py lifts its text from the
# Swift source at that ref and, in --check mode, fails when the Kotlin on disk
# is not what it would write — a hand edit or a stale generator breaks this
# script. The conversation and correction prompts are held twice:
# ConversationPromptVectorTest compares the whole assembled prompt against the
# real iOS output (gen-prompt-vectors.sh). Re-pinning = one edit to IOS_REF,
# then run the generators without --check.
set -euo pipefail
cd "$(dirname "$0")/../.."
scripts/android/gen-vectors.sh

# A generator that reads the worktree's FutureVoice/ (whatever iOS was when
# this branch last merged it) or a ref of its own is the drift this exists
# to stop: every one goes through promptgen/iosref.py.
for g in scripts/android/gen-*.py; do
  [ "$(basename "$g")" = gen-strings.py ] && continue   # the catalog, not iOS source
  grep -q "from iosref import" "$g" || { echo "✗ $g does not read iOS through promptgen/iosref.py"; exit 1; }
done
# Client prompts: Android ships these, so a mismatch fails the check.
CLIENT="conversation-prompt coach-prompts correction-prompt lifted-prompts breath-punctuation
  free-talk-openers counterpart-ideas counterpart-parser path-ideas persona-polish
  shadow-coach-prompt shadow-transcribe-prompt clone-script contractions situation-tree
  voice-accents futureself-ramp"
SERVER="summary-prompt weekly-prompt enrichment-prompt"
for g in scripts/android/gen-*.py; do   # a new generator must be listed in one of the two
  n=$(basename "$g" .py); n=${n#gen-}
  [ "$n" = strings ] && continue
  case " $(echo $CLIENT $SERVER) " in *" $n "*) ;; *) echo "✗ gen-$n.py is in neither CLIENT nor SERVER"; exit 1;; esac
done
for g in $CLIENT; do python3 "scripts/android/gen-$g.py" --check; done
# Server prompts (supabase/functions/*/prompt.ts): Android-only edge functions
# whose prompt iOS builds client-side. A stale one is LOUD but not fatal —
# changing it is a server deploy, which is the founder's call.
for g in $SERVER; do
  python3 "scripts/android/gen-$g.py" --check || echo "▲ server prompt behind iOS: gen-$g.py — needs a regenerate + edge deploy"
done
python3 scripts/android/gen-strings.py --check >/dev/null 2>&1 || { echo "✗ strings stale — run gen-strings.py"; exit 1; }
scripts/android/gen-prompt-vectors.sh
if ! git diff --quiet -- docs/contracts/vectors; then
  echo "▲ golden vectors changed — an iOS rule moved:"; git --no-pager diff --stat -- docs/contracts/vectors
fi
( cd android && ./gradlew :app:testDebugUnitTest --console=plain -q )
python3 - <<'PY'
import glob, re
t = f = 0
for x in glob.glob("android/app/build/test-results/testDebugUnitTest/*.xml"):
    s = open(x).read()
    m = re.search(r'tests="(\d+)".*?failures="(\d+)" errors="(\d+)"', s)
    if m: t += int(m.group(1)); f += int(m.group(2)) + int(m.group(3))
print(f"rule tests: {t} run, {f} failing")
PY
