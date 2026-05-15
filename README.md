# Future Voice

> Learn a language by speaking with a fluent version of yourself.
> 자신의 유창한 미래 버전과 대화하며 언어를 배우는 앱.

iOS-first SwiftUI app. ElevenLabs for voice clone + TTS, Anthropic Claude for the conversation brain, on-device STT for transcription.

Full design: [`docs/SPEC.md`](docs/SPEC.md). We are currently in **Phase 1 — Voice + Conversation Spike**.

---

## Repo layout

```
FutureVoice/
├── FutureVoiceApp.swift              # @main entry
├── Models/
│   └── Models.swift                  # User, LearnerProfile, Session, Turn, ...
├── Services/
│   ├── ElevenLabsClient.swift        # /v1/voices/add, /v1/text-to-speech
│   ├── ClaudeClient.swift            # Anthropic Messages API
│   ├── ConversationEngine.swift      # Prompt templates + summary decoding
│   ├── AudioRecorder.swift           # 16kHz mono WAV via AVAudioRecorder
│   ├── AudioPlayer.swift             # MP3 playback via AVAudioPlayer
│   └── SpeechTranscriber.swift       # On-device SFSpeechRecognizer
├── Views/
│   ├── RootView.swift                # Onboarding gate
│   ├── VoiceCloneOnboardingView.swift
│   └── ConversationView.swift        # The whole Phase 1 loop
├── Config/
│   └── Secrets.swift                 # Reads from Info.plist (xcconfig-injected)
└── Resources/
    └── Info.plist                    # Permissions + $(KEY) injections

Config/
└── FutureVoice.xcconfig.example      # Copy → FutureVoice.xcconfig and fill keys

docs/
└── SPEC.md
```

---

## First-time setup

### 1. Secrets

```bash
cp .env.example .env                                  # fill in keys
cp Config/FutureVoice.xcconfig.example Config/FutureVoice.xcconfig
# edit Config/FutureVoice.xcconfig — paste real keys
```

Both `.env` and `FutureVoice.xcconfig` are gitignored.

### 2. Create the Xcode project (one-time)

These Swift files are already written, but the `.xcodeproj` is intentionally not committed — Xcode generates a cleaner project than hand-rolling one. Steps:

1. Open Xcode → **File → New → Project…**
2. Choose **iOS → App**.
3. Settings:
   - Product Name: **FutureVoice**
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None** (Phase 1 — no persistence yet)
   - Bundle Identifier: `com.roro.futurevoice` (or your own)
   - Minimum Deployment: **iOS 17.0** (bump to 26.0 when ready to use `SpeechAnalyzer`)
4. Save the project **inside this repo's `FutureVoice/` folder, replacing the default scaffold** (don't create a nested second `FutureVoice` folder). When Xcode offers to create files, let it; then remove its generated `ContentView.swift` and the default app file — keep the ones already in this repo.
5. In the Project navigator, right-click the `FutureVoice` group → **Add Files to "FutureVoice"…** → select the `Models/`, `Services/`, `Views/`, `Config/`, and `Resources/` folders → **Create groups** (not folder refs) → **Add**.
6. Project settings → **Build Settings** → **Configurations** → set both Debug and Release to use `Config/FutureVoice.xcconfig`.
7. Project settings → **Info** → confirm the keys from `Info.plist` are picked up (or set the **Info.plist File** path to `FutureVoice/Resources/Info.plist`).
8. **Signing & Capabilities** → pick your team.
9. Build and run on a real device (the simulator can't access the microphone the same way).

### 3. Voice cloning hint

The first record-clone round-trip is the single most important thing to validate in Phase 1. If the cloned voice sounds like *you* speaking the target language, the rest of the product is downstream.

---

## Running

```bash
open FutureVoice.xcworkspace   # if you create one
# or
open FutureVoice.xcodeproj
```

Cmd-R. Hit "Start recording" → read the prompt → wait for the clone → start a conversation.

---

## Conventions

- **No secrets in code.** `Secrets.devOverride` is a temporary local hatch only.
- **Domain types are the source of truth.** Spec doc points at `Models.swift`; don't duplicate.
- **Prompts live in code.** `ConversationEngine.swift`, not in Markdown.
- **One transport per provider.** Keep `ElevenLabsClient` and `ClaudeClient` as the only HTTP entry points.

---

## What's next (Phase 2 sketch)

- Supabase auth + tables for `users`, `learner_profiles`, `sessions`.
- Move API keys behind a Supabase Edge Function so the iOS app never holds raw provider keys (matches the DearMyChild pattern).
- SwiftData cache for offline session replay.
- Switch ElevenLabs to the streaming TTS endpoint for sub-1.5s latency.
- Wire `SpeechAnalyzer` (iOS 26) when min-deployment is bumped.

---

*Built on the same philosophy as Dear RoRo — person before product.*
