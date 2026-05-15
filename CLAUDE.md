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
