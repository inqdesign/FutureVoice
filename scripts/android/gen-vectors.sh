#!/bin/bash
# Golden vectors for the deterministic ports (android-launch-roadmap §0.3):
# compile the REAL Swift implementations against test stubs, run them over
# fixed fixtures, and write the results where both platforms' tests read them.
# Re-run whenever CarryoverDetector / DrillStore / ScorecardMetrics /
# LearnerProfile.absorb changes; a number that then differs across platforms
# is a bug on whichever side is newer.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=docs/contracts/vectors/summary-ingestion.json
BIN=$(mktemp -d)/vecgen
swiftc -O -o "$BIN" \
  scripts/android/vecgen/stubs.swift scripts/android/vecgen/main.swift \
  FutureVoice/Models/Models.swift \
  FutureVoice/Services/CarryoverDetector.swift \
  FutureVoice/Services/DrillStore.swift \
  FutureVoice/Services/ScorecardMetrics.swift \
  FutureVoice/Services/ShadowEngine.swift \
  FutureVoice/Services/LanguageCatalog.swift \
  FutureVoice/Services/WordSplitter.swift \
  FutureVoice/Services/JapaneseMorph.swift \
  FutureVoice/Services/TextScript.swift
# JapaneseMorph checks a stem rule's guess against the word classes, read
# through Bundle.main — a command-line tool's is the directory it sits in.
cp FutureVoice/Resources/word_classes_ja.tsv "$(dirname "$BIN")/"
"$BIN" "$OUT"
cp "$OUT" android/app/src/test/resources/vectors/summary-ingestion.json
echo "vectors regenerated → $OUT (+ android test resources)"
