#!/usr/bin/env bash
# The rule tests in one command (master plan 1.4 / 5단계):
#   1. compile the REAL Swift implementations and write the golden vectors
#   2. say whether any vector changed — a change means an iOS rule moved,
#      and the Android port now owes the same change
#   3. run the Android tests that read those vectors
set -euo pipefail
cd "$(dirname "$0")/../.."
scripts/android/gen-vectors.sh
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
