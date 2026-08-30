# Cross-platform contracts

> The shared truth between the iOS client (`FutureVoice/`), the Android client
> (`android/`) and the server (`supabase/`).
> Written 2026-08-02 as Phase A of `docs/android-plan.md`, by extraction from
> the iOS implementation. iOS is the reference; where iOS and this doc disagree,
> **iOS code wins and this doc is the bug**.

Three documents, one per kind of contract:

| Doc | Answers | Extracted from |
|---|---|---|
| [`edge-api.md`](edge-api.md) | What goes over the wire to Supabase Edge Functions | `GeminiClient.swift`, `ElevenLabsClient.swift`, `supabase/functions/` |
| [`data-model.md`](data-model.md) | What a record IS, and whether it is scoped to `user` or `(user, lang)` | `Models.swift`, `supabase/migrations/`, `docs/multi-language-plan.md` |
| [`behavior.md`](behavior.md) | Deterministic rules that must produce the SAME result on every platform | `ConversationView.swift`, `LiveTranscriber.swift`, `ShadowEngine.swift`, `DrillStore.swift` |

## Rules for changing a contract

1. **Change the doc in the same commit as the code.** A contract doc that lags
   the code is worse than no doc — the second client builds against a lie.
2. **Never fork logic.** If Android needs a piece of iOS-resident brain
   (prompt construction, summary analysis, SRS scheduling), promote it into an
   Edge Function at that moment. Never maintain the same rule in Swift and
   Kotlin. This is the single mitigation for the plan's #1 risk (logic drift).
3. **Numbers in `behavior.md` are load-bearing.** VAD tiers, the audio format,
   Leitner intervals — a client that picks its own values is a different
   product, not a port.

## Known parity gaps (Android, as of 2026-08-26)

| Gap | Why | Exit |
|---|---|---|
| No inline user audio on the turn call | Android's `SpeechRecognizer` holds the mic exclusively, so raw PCM can't be tapped in parallel. iOS attaches the user's WAV so Gemini can hear past ASR errors. | Either a Whisper-style server STT leg (then Android captures with `AudioRecord` and never uses `SpeechRecognizer`), or on-device recognition with an audio-passthrough API. Until then the turn's `transcript` field comes back `null`, exactly as the prompt specifies for the no-audio case. |
| Sign-in is Apple-only (debug builds: email) | The first spike reused a clone already on the server, so it only needed the iPhone identity. | Android users are Android users: anonymous session → **Google** link as the primary provider, Apple **web** OAuth for iPhone switchers (`android-launch-roadmap.md` §1.2). |
| Purchase | iOS sells subscriptions via StoreKit 2 (`apple-webhook`). Android meters talk time (`talk-tick`, 2026-08-26) but cannot yet BUY: an Android-only account meets the hard paywall on its first talk. | Play Billing → a `google-webhook` sibling of `apple-webhook` writing the same `user_subscriptions` row. Decide the two-store policy (one user subscribed on both) before Play launch. |
