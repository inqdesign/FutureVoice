# Future Voice — Claude Code Context

> Read this before making changes. Spec lives in `docs/SPEC.md`.

## What this app is

iOS SwiftUI app. A user clones their own voice once (ElevenLabs), then practices a target language by talking with a "fluent self" — same voice, fluent output. Claude is the conversation brain and the post-session summarizer.

Currently in **Phase 1 — Voice + Conversation Spike**. No persistence, no auth, single-screen flow.

## Source of truth

- **Domain types** → `FutureVoice/Models/Models.swift`. Update there first; spec doc references it.
- **Prompt templates** → `FutureVoice/Services/ConversationEngine.swift`.
- **HTTP** → only `ElevenLabsClient.swift` and `ClaudeClient.swift`. Don't add ad-hoc URLSession calls elsewhere.
- **Secrets** → `Secrets.swift` only. Reads from Info.plist (xcconfig-injected). Never paste keys into other files.

## Hard rules

- **No secrets in committed code.** Use `Config/FutureVoice.xcconfig` (gitignored). `Secrets.devOverride` is a temporary local hatch.
- **Don't change `FutureVoice.xcconfig.example`** to include real values — it's the public template.
- **iOS-first.** macOS support is out of scope; AVAudioSession etc. only need to work on iOS.
- **Don't write to disk outside `FileManager.default.urls(for: .documentDirectory)`** unless using `cacheDirectory` with a clear cleanup policy.
- **One screen at a time in Phase 1.** Adding a NavigationStack or tab bar is Phase 2 work.

## UI rules (strict)

**Voice is the primary modality. Design like a phone call, not a chat app.**

- **iOS-native SwiftUI elements only.** No custom card materials, no custom bubble shapes, no rolled-our-own components.
  - Use: `NavigationStack`, `.toolbar`, `Form`, `List`, `Button`, `Label`, `Image(systemName:)`, `ProgressView`, `Text` with system fonts (`.largeTitle`, `.headline`, `.body`, `.footnote`).
  - System colors only: `.primary`, `.secondary`, `.accentColor`, `Color(.systemBackground)`, `Color(.secondarySystemBackground)`. Avoid `.blue`/`.red`/`.green` literals except when they convey semantic state (recording = red, success = green) — even then prefer `.tint`/`.foregroundStyle(.red)` over background fills.
  - SF Symbols for every icon.
- **Voice-first layout.** The dominant element on the conversation screen is a single big mic button. Status (speaking / listening / thinking) is shown in plain text above it. The most-recent line of dialogue is shown as a caption, not as a chat bubble.
- **No chat-bubble metaphor.** No left/right aligned bubbles, no "blue user / gray fluent self" message list. This isn't a messenger.
- **Sheets for non-primary content.** Topic picker, session summary, settings — present as `.sheet` so the call screen stays clean.
- **Animation = subtle.** A breathing pulse on the mic button while recording is fine. No bouncy springs, no confetti.

## Conventions

- SwiftUI views, no UIKit unless absolutely required.
- `@MainActor` on anything touching `URLSession` callbacks → published state, audio recorder/player.
- `async/await` over completion handlers everywhere.
- No third-party Swift packages in Phase 1. Add SPM deps only when there's a concrete need (RevenueCat, Supabase-swift, etc. — all Phase 2+).

## Phase 1 success criterion

Hear yourself say a fluent sentence in your target language, end-to-end, on a real device. Everything else is scaffolding.

## Model defaults

- Conversation turns: `claude-sonnet-4-6` (fast, cheap, good enough).
- Session summary: `claude-opus-4-7` (higher-stakes single call, JSON output).
- Both via `ClaudeClient.Model` enum.

## Audio format

16kHz mono PCM WAV for recordings. Whisper and ElevenLabs both accept this. Don't change it without checking both providers' docs.
