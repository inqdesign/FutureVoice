# Future Voice — Claude Code Context

> Read this before making changes. `docs/SPEC.md` has the original concept but is STALE (still says Phase 1) — this file and the code are the truth.

## What this app is

iOS SwiftUI app. A user clones their own voice once (ElevenLabs), then practices a target language by talking with a "fluent self" — same voice, fluent output. Gemini is the conversation brain and analyzer; ElevenLabs synthesizes every fluent-self line in the user's cloned voice.

**Current state (2026-06): four-tab app in TestFlight prep, NOT a Phase-1 spike.**

Tab order: **Talk · Watch · Practice · Progress** (`RootTabView`) — do → create → review → measure.

- **Talk** (`ConversationHome`) — the speaking launcher, one tap to start the call. A List: Today status (minutes/goal, streak, talks → ActivityView), Free talk, **Scenarios** (header "+" → builder), **In the news** (`NewsTopicSection`, refresh + interests in its header). Every row tap launches `ConversationView` phone-call-mode conversation (live STT → Gemini structured turn `{reply, suggestion}` → cloned-voice TTS, auto VAD turn-taking; per-turn suggestions as inline chips). `MeTab` opens from this tab's header.
- **Watch** (`WatchTab`) — simulate a specific situation BEFORE it happens and mine ideas (how the fluent self handles it, which expressions it uses). Three entries, all landing in the `SituationComposerSheet` bottom sheet: ① a stories-style People row (tap a persona → composer scoped to them, with relationship-grounded ideas from `TopicEngine.suggestForCounterpart`, cached on the counterpart), ② "Make your own situation" — the DEFAULT: describe the real upcoming thing in a blank composer (no person needed; empty `Scenario.role` makes the scene infer its own counterpart), ③ "Likely situations" — a drill-down chain (cafe → ordering → order came out wrong) whose leaves prefill the composer, always editable. **Watch** mints the `Scenario` and plays its scene in `SceneWatchView` (`ScenarioCurriculumEngine` — the same generation stocks the book Practice reviews). A saved `Scenario` is a reusable TEMPLATE: tapping it under "Your scenarios" writes a FRESH take every time (`SceneWatchView(freshTake:)` — per-run idempotency key, previous titles passed as `avoidTitles`), and the new take is `absorb`ed into the scenario's book — latest scene replaces the old, study items accumulate, mastery survives. Replaying past material is Practice's job, never Watch's. No browsing here; books live in Practice.
- **Practice** (`PracticeTab`) — the REVIEW home; everything here came out of an activity. Three layers: today's cross-cutting SRS queue (`DrillStore` Leitner boxes 0–5 + shadow picks), the **Books** shelves behind chips (**Talks · Topics · Scenarios**), and the Library dictionaries (vocabulary / expressions / shadowing). Every book has the same anatomy — one scene + words/lines to master, then archive. Watch books = `Scenario` + `ScenarioCurriculum` (`ScenarioDetailView`; scene behind its Watch button). Talk books = a finished `Session` whose material is DERIVED by `TalkCurriculum` (fluent-self pickup words + corrected lines as shadow material, mastery via `VocabStore`/shadow attempts — never persisted); their page is `ConversationDetailView` (Continue / Replay; raw transcript + sequential audio replay behind Replay in `TalkTranscriptView`).
- **Progress** (`ProgressTab`) — measured CEFR estimate + per-skill pages behind swipeable chip tabs, plus the activity/effort panel (14-day rep bars).
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
- **Prompt templates** → `ConversationEngine.swift` (conversation + summary), `ShadowEngine.swift`, `WeeklyReportEngine.swift`, `TopicEngine.swift`, `DrillEnrichmentEngine.swift`. The shared two-language preamble every coaching prompt splices in lives in `CoachingLanguage.swift` — see "Two languages" below.
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

## Two languages (target vs. native)

Every learner has a **target** language (what they practice, `AppState.targetLanguage`) and a **native** language (what they think in, `AppState.nativeLanguage`, picked in setup, editable in Me). Anything an LLM writes falls on one side of a single line:

- **Material → target language.** Anything the learner says out loud, drills, or memorizes: drill cards, `fluent_alternative`, `suggested_drills`, expressions, scene lines, shadow targets.
- **Coaching → native language.** Anything that explains, judges or frames that material: `reason`, `note`, `overall_note`, scorecard commentary, weekly-report prose, drill memory hooks, shadow feedback. A B1 learner skips feedback they have to decode.
- **Machine-consumed fields stay English** regardless: `weak_vocab_areas` and `new_patterns_detected.context` are re-injected into the next conversation's system prompt via `LearnerProfile` and are never rendered.

`CoachingLanguage.contract(target:native:)` is the shared preamble; each engine then tags its own fields (an "OUTPUT LANGUAGE, FIELD BY FIELD" block). When adding a field to any prompt schema, decide which side it's on and say so in the prompt — an untagged field silently comes back English.

Two cases that look like exceptions but aren't:

- **Scenario titles/blurbs** (`TopicEngine`) are MATERIAL, so target language — the blurb literally becomes the scene the learner talks through. These used to say "in English" literally; they now follow `targetLanguage`, which only matters once the target isn't English.
- **Counterpart profiles** (`CounterpartParser`) are the user's OWN note about their own friend, dictated in their own language and edited by hand afterwards — so every field comes back in the native language. They're also injected as free-text context into `DialogueEngine` / `TopicEngine` / `ScenarioCurriculumEngine` prompts, each of which carries a "context only, don't let its language change your output language" guard next to the data. Keep that guard next to any new native-language context you inject.

Still English, and the one real gap: **UI chrome**. The app has **no** localization infrastructure — no `.xcstrings`, no `String(localized:)`; ~590 hardcoded English literals in `Views/` alone.

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
- **One dialogue surface.** Every conversation view — Watch's scripted dialogue, the live call transcript, past-conversation detail — renders lines through `DialogueLine` (`Views/DialogueLine.swift`). Speaker separation (name label, side, bubble fill, playback ring) lives ONLY there; callers pass their own content + accessories. Restyling the conversation UI must stay a single-file change — never re-implement a line locally.
- **Sheets for non-primary content.** Topic picker, summaries, settings.
- **Animation = subtle.** Breathing pulse on the mic is fine; no bouncy springs, no confetti.

## Conventions

- SwiftUI views, no UIKit unless absolutely required.
- `@MainActor` on anything touching URLSession callbacks → published state, audio recorder/player.
- `async/await` over completion handlers everywhere.
- SPM deps: `supabase-swift` only. Add more only with a concrete need.

## Model defaults

- Default LLM: Gemini `gemini-3.6-flash` with `thinkingLevel: "low"` and DEFAULT sampling (Google recommends against sub-1.0 temperature on gen-3 — `GeminiClient` drops the caller's temperature for gen-3 models), via the `gemini` Edge Function (`GeminiClient.Model`).
- Utility calls (Translator's pure translation, CounterpartParser, FreeTalkOpeners) run on `gemini-3.1-flash-lite`. Learner-facing coaching text stays on the default model.
- `gemini-2.5-flash` remains in the enum as a rollback hatch only — the 2.5 family retires 2026-10-16.
- Conversation turns: structured JSON, **streamed** via `sendJSONStream` (`stream: true` → the `gemini` Edge Function proxies `streamGenerateContent?alt=sse`). Field order is load-bearing — `{reply, suggestion, transcript}`, reply FIRST — because TTS fires the instant the reply's closing quote arrives while the tail is still being written. Don't put a field before `reply` and don't reorder the prompt's schema line. Analysis calls (summary, shadow bullets, weekly report) stay on buffered `sendJSON`. Temperature args still exist on the API for 2.5-era callers but are ignored on gen-3.
- TTS: **speaker similarity is the product** — the user must believe the voice is theirs. Model choice ranks `eleven_multilingual_v2` > `eleven_turbo_v2_5` > `eleven_flash_v2_5` on similarity, and exactly the reverse on latency. Defaults:
  - Talk conversation turns → `eleven_turbo_v2_5` (`ElevenLabsClient.conversationModelId`). Flash was tried here and reverted: it costs the same but sounds less like the user, on the app's highest-exposure surface.
  - Watch scenes (the user's OWN voice only) + the onboarding greeting → `eleven_multilingual_v2` (`ElevenLabsClient.fidelityModelId`).
  - Everything else — Shadow, drills, library, counterpart preset voices → `eleven_turbo_v2_5`.
  - `fidelityModelId` bills ~2x per character upstream while `priceFor("tts")` in the edge function is model-BLIND, so that 2x is pure margin we absorb. Only put a path on it when `PhraseAudioStore` caches the result (making the 2x one-time per unique line) or when it fires once per user, ever. NEVER for live conversation turns.
  - Voice settings are fixed server-side in `supabase/functions/elevenlabs-tts/`. `style` MUST stay `0` — any style exaggeration pulls the output away from the reference speaker.

## Audio format

16kHz mono PCM WAV for recordings. Whisper and ElevenLabs both accept this. Don't change it without checking both providers' docs.
