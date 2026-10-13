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
         Services/CoachingLanguage.swift Services/LanguageCatalog.swift Services/CommonGround.swift; do
  git show "$REF:FutureVoice/$f" > "$SRC/$(basename "$f")"
done
BIN=$SRC/promptgen
swiftc -O -o "$BIN" scripts/android/promptgen/stubs.swift scripts/android/promptgen/main.swift "$SRC"/*.swift
TZ=UTC "$BIN" "$OUT" "$(git rev-parse --short "$REF")"
mkdir -p android/app/src/test/resources/vectors
cp "$OUT" android/app/src/test/resources/vectors/conversation-prompts.json
echo "$REF" > scripts/android/promptgen/IOS_REF
