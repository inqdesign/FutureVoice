# Future Voice — Claude Code Context

> Read this before making changes. `docs/SPEC.md` has the original concept but is STALE (still says Phase 1) — this file and the code are the truth.

## What this app is

iOS SwiftUI app. A user clones their own voice once (ElevenLabs), then practices a target language by talking with a "fluent self" — same voice, fluent output. Gemini is the conversation brain and analyzer; ElevenLabs synthesizes every fluent-self line in the user's cloned voice.

**Current state (2026-06): four-tab app in TestFlight prep, NOT a Phase-1 spike.**

Tab order: **Talk · Watch · Practice · Progress** (`RootTabView`).

- **Talk** (`ConversationHome` → `ConversationView`) — phone-call-mode conversation: live STT → Gemini structured turn `{reply, suggestion}` → cloned-voice TTS, auto VAD turn-taking. Per-turn "say it more naturally" suggestions render as inline chips. `MeTab` (persona, CEFR picker, voice re-record, history) opens from this tab's toolbar.
- **Watch** (`WatchTab`) — two swipeable shelf pages of curriculum "books" (`Scenario` + `ScenarioCurriculum`) behind chip tabs, same mechanics, different seed: "By topic" (born from an interest/news topic via `WatchTopicSheet`, `Scenario.isTopic`) and "By scenario" (built situation + counterpart). Each book = one generated scene to watch + its words/expressions/shadow lines to master (`ScenarioDetailView`). Counterparts are voiced by ElevenLabs presets; the user's side is their clone.
- **Practice** (`PracticeTab`) — Leitner SRS drill deck (`DrillStore`, boxes 0–5, active-recall reveal), per-session drill review, shadow practice (`ShadowDrillView`, karaoke timing + deterministic token-Levenshtein score from `ShadowEngine`).
- **Progress** (`ProgressTab`) — measured CEFR estimate + per-skill pages (vocabulary, fluency, shadowing, …) behind swipeable chip tabs.
- **Home-screen widgets** (`FutureVoiceWidget` target) — TWO widgets in one bundle, one per `StudyWidgetSection`: a **Vocabulary** widget (notebook `studying` words + recent used, CEFR tag, taps `futurevoice://vocab`) and an **Expressions** widget (`VocabStore.expressionEntries()`, taps `futurevoice://expressions`). Both are list widgets whose window slides every 30 min. App-side `StudyWidgetRefresher` writes a per-section snapshot into the App Group on every `DrillStore`/`VocabStore` write and at scene-phase edges; the extension only reads. App-side `StudyWidgetRefresher` writes a snapshot into the App Group (`group.com.roro.futurevoice`) on every `DrillStore`/`VocabStore.studying` write and at scene-phase edges; the extension only reads. The shared contract `FutureVoice/Shared/StudyWidgetShared.swift` compiles into BOTH targets — keep it free of Models.swift/store imports. Widget tap deep-links `futurevoice://practice` (handled in `RootTabView`).

## The learning loop (keep it closed)

```
conversation → summary (+ scorecard metrics) → DrillStore.ingest (SRS cards)
            ↘ LearnerProfile.absorb via ProfileStore  → next conversation's system prompt
            ↘ WeeklyReportEngine (unlocks on accumulated speaking time)
```

Every feature should feed this loop. Per-turn suggestions come back in the SAME Gemini call as the reply (structured JSON) — do not add a second per-turn LLM call, and do not remove the suggestion field: `ScorecardMetrics.suggestionRate`, drill ingestion, and the weekly report's repeated-mistake detection all depend on `Turn.suggestion`.

## Source of truth

- **Domain types** → `FutureVoice/Models/Models.swift`. Update there first.
- **Prompt templates** → `ConversationEngine.swift` (conversation + summary), `ShadowEngine.swift`, `WeeklyReportEngine.swift`, `TopicEngine.swift`, `DrillEnrichmentEngine.swift`.
- **HTTP** → `GeminiClient.swift` and `ElevenLabsClient.swift` only. Both route through Supabase Edge Functions (`supabase/functions/`) so the app never holds raw provider keys. `ClaudeClient.swift` is a dead transport (no call sites) — don't wire new features to it.
- **Persistence** → JSON-on-disk stores in `Services/` (`SessionStore`, `DrillStore`, `ProfileStore`, `PersonaStore`, …), all following the same pattern. Supabase tables exist for auth/voice-clone/subscriptions (`supabase/migrations/`).
- **Secrets** → `Secrets.swift` only, injected via `Config/FutureVoice.xcconfig` (gitignored).

## Build / run

Project is **xcodegen-driven** — `.xcodeproj` is generated, don't hand-edit it.

```bash
cd /Users/eunggyuelee/FutureVoice
xcodegen generate          # REQUIRED after adding/removing Swift files
xcodebuild -project FutureVoice.xcodeproj -scheme FutureVoice \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build build
# install+launch: xcrun simctl install <UDID> <path>.app && xcrun simctl launch <UDID> com.roro.futurevoice
```

SourceKit diagnostics commonly show ghost errors ("Cannot find type …") for new files until xcodegen + a build run. **xcodebuild is the truth — don't chase SourceKit ghosts.**

## Hard rules

- **No secrets in committed code.** `Config/FutureVoice.xcconfig` is gitignored; never put real values in `FutureVoice.xcconfig.example`.
- **iOS-first.** macOS support is out of scope.
- **Don't write to disk outside `documentDirectory`** unless using `cacheDirectory` with a clear cleanup policy.
- **Deterministic scores stay deterministic.** Shadow match scores and scorecard metrics are computed in code; the LLM only writes qualitative notes anchored to those numbers. Don't let an LLM invent a number the code can compute.
- **Drill cards must be speakable utterances**, never meta-rules ("use articles correctly"). `DrillStore.looksLikeMetaRule` is the safety net; keep prompts emitting concrete sentences.

## UI rules (strict)

**Voice is the primary modality. Design like a phone call, not a chat app.**

- **iOS-native SwiftUI elements only.** No custom card materials, no chat bubbles, no rolled-our-own components. `NavigationStack`, `.toolbar`, `Form`, `List`, `Button`, `Label`, SF Symbols, system fonts.
- System colors only: `.primary`, `.secondary`, `.accentColor`, `Color(.systemBackground)`, `Color(.secondarySystemBackground)`. Semantic literals (recording = red, success = green) via `.tint`/`.foregroundStyle` only.
- **No chat-bubble metaphor.** The transcript is a plain left-aligned feed, not messenger bubbles.
- **Sheets for non-primary content.** Topic picker, summaries, settings.
- **Animation = subtle.** Breathing pulse on the mic is fine; no bouncy springs, no confetti.

## Conventions

- SwiftUI views, no UIKit unless absolutely required.
- `@MainActor` on anything touching URLSession callbacks → published state, audio recorder/player.
- `async/await` over completion handlers everywhere.
- SPM deps: `supabase-swift` only. Add more only with a concrete need.

## Model defaults

- All LLM calls: Gemini `gemini-2.5-flash` with `thinkingBudget: 0`, via the `gemini` Edge Function (`GeminiClient.Model`).
- Conversation turns: structured JSON `{reply, suggestion}` at temperature 0.7; analysis calls (summary, shadow bullets, weekly report) at 0.4 via `sendJSON`.

## Audio format

16kHz mono PCM WAV for recordings. Whisper and ElevenLabs both accept this. Don't change it without checking both providers' docs.
