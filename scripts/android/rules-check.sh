#!/usr/bin/env bash
# The rule tests in one command (master plan 1.4 / 5단계):
#   1. compile the REAL Swift implementations and write the golden vectors
#   2. say whether any vector changed — a change means an iOS rule moved,
#      and the Android port now owes the same change
#   3. run the Android tests that read those vectors
#
# The conversation prompt is held to iOS twice: its text must be what
# gen-conversation-prompt.py lifts from the pinned iOS ref (scripts/android/
# promptgen/IOS_REF), and ConversationPromptVectorTest compares the whole
# assembled prompt against the real iOS output (gen-prompt-vectors.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."
scripts/android/gen-vectors.sh
python3 scripts/android/gen-conversation-prompt.py --check
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
