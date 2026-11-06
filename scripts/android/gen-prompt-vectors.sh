#!/bin/bash
# Golden CONVERSATION PROMPTS: compile the real iOS ConversationEngine (at an
# iOS ref, not this worktree's copy) against stubs, build the system prompt
# for every fixture in scripts/android/promptgen/main.swift, and write them
# where Android's ConversationPromptVectorTest reads them. A Kotlin prompt
# that differs from these by one byte fails that test.
#
#   scripts/android/gen-prompt-vectors.sh            # the pinned ref below
#   scripts/android/gen-prompt-vectors.sh <ios-ref>  # re-pin after an iOS change
set -euo pipefail
cd "$(dirname "$0")/../.."
REF=${1:-$(cat scripts/android/promptgen/IOS_REF)}
OUT=docs/contracts/vectors/conversation-prompts.json
SRC=$(mktemp -d)
for f in Models/Models.swift Models/SpeechRegister.swift Services/ConversationEngine.swift \
         "Services/ConversationEngine+Character.swift" Services/PromptClock.swift \
         Services/CoachingLanguage.swift Services/LanguageCatalog.swift Services/CommonGround.swift \
         Services/PersonHistory.swift; do
  git show "$REF:FutureVoice/$f" > "$SRC/$(basename "$f")"
done
# Lines for one target language each (iOS 5a462332).
if git cat-file -e "$REF:FutureVoice/Services/ConversationEngine+LanguageLines.swift" 2>/dev/null; then
  git show "$REF:FutureVoice/Services/ConversationEngine+LanguageLines.swift" > "$SRC/ConversationEngine+LanguageLines.swift"
fi
# Tutor mode's lesson types (iOS af3c7ffe) — the model only; the store and
# the model calls below it need the app.
if git cat-file -e "$REF:FutureVoice/Services/TutorLesson.swift" 2>/dev/null; then
  git show "$REF:FutureVoice/Services/TutorLesson.swift" | sed '/^\/\/ MARK: - Store/,$d' > "$SRC/TutorLesson.swift"
fi
# The learner's own goals (iOS 3d655c8b): the WHO YOU BECAME block's lines.
if git cat-file -e "$REF:FutureVoice/Services/FutureGoal.swift" 2>/dev/null; then
  git show "$REF:FutureVoice/Services/FutureGoal.swift" > "$SRC/FutureGoal.swift"
fi
BIN=$SRC/promptgen
swiftc -O -o "$BIN" scripts/android/promptgen/stubs.swift scripts/android/promptgen/main.swift "$SRC"/*.swift
TZ=UTC "$BIN" "$OUT" "$(git rev-parse --short "$REF")"
mkdir -p android/app/src/test/resources/vectors
cp "$OUT" android/app/src/test/resources/vectors/conversation-prompts.json
echo "$REF" > scripts/android/promptgen/IOS_REF
