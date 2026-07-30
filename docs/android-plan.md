# Android Version Plan

> Native Kotlin + Jetpack Compose client sharing the Supabase backend with iOS.
> Status: PLAN. Written 2026-07-29. iOS is the reference implementation.

## Strategy in one line

**iOS is the reference implementation; Supabase is the shared brain; Android is a thin native client built vertical-slice-first.**

## Decisions
- **Native Kotlin + Jetpack Compose.** The product is "a phone call, not a chat app" — realtime audio capture, VAD turn-taking, low-latency TTS playback. That demands the platform audio stack directly; cross-platform frameworks (Flutter/RN) fight it. KMP has nothing to share today (the logic is in Swift); sharing happens in Supabase instead.
- **Monorepo**: `android/` directory in this repo. The shared truths — contract docs (`docs/`) and Edge Functions (`supabase/`) — must live next to both clients or the contract goes stale. Splitting later is cheap.
- **Vertical slice first**: one complete Talk call loop before any breadth. 80% of product value and 90% of technical risk live there.
- **Gradual brain-lift**: whenever Android needs a piece of iOS-resident logic (prompt templates, SRS scheduling, curriculum generation), promote it to an Edge Function at that moment instead of re-implementing in Kotlin. Never maintain the same logic in Swift and Kotlin.

## What is shared for free (zero reimplementation)
- **Gemini / ElevenLabs proxying** — same Edge Functions (`supabase/functions/`); the app never holds provider keys, same as iOS.
- **Auth** — `supabase-kt` (official Kotlin SDK) against the same project; same user accounts.
- **Voice clone** — `voice_clones` table, one active clone per user. Android restores the same `elevenlabs_voice_id` on sign-in. *The magic moment: a user who cloned on iPhone hears their own voice on Android immediately — never rebuild cloning UX as a first step, restore is enough for v1.*
- **Subscription/credits** — `user_subscriptions` + `user_credits` + `charge_credits`. Android adds Google Play Billing → credit grant (mirror of `StoreKitService`); consumption paths are untouched.
- **Multi-language contract** — see `multi-language-plan.md`: records belong to `(user, lang)`; Android materializes this as Room tables keyed by `lang` from day one (it never has a single-language legacy to migrate).

## What must be built natively
| Concern | iOS | Android |
|---|---|---|
| UI | SwiftUI | Jetpack Compose |
| Live STT | SFSpeechRecognizer (per-language locale) | `SpeechRecognizer` w/ locale, or same Whisper endpoint |
| Audio capture | AVFoundation, 16kHz mono PCM WAV | `AudioRecord`, same format (contract: don't change without checking Whisper + ElevenLabs) |
| Playback | AVAudioPlayer | `AudioTrack`/ExoPlayer |
| VAD turn-taking | in-app | reimplement (same thresholds — extract constants into the contract doc) |
| Local persistence | JSON-on-disk stores | Room (or DataStore), `lang`-keyed |
| Widgets | WidgetKit (2 widgets) | Glance App Widgets |
| Deep links | `futurevoice://` | same scheme via App Links |
| Billing | StoreKit 2 | Play Billing Library |

## Phase plan

### Phase A — Contract extraction (docs, no Android code)
Extract from iOS into `docs/contracts/`:
1. **Edge Function API contract** — request/response of each function (`gemini`, elevenlabs, …), including the structured turn `{reply, suggestion}` schema.
2. **Data contract** — Models.swift types that cross the wire or will sync in Phase 2 (Session, Turn, LearnerProfile, Drill, …) as language-neutral JSON schemas, `(user, lang)` scoping per the multi-language plan.
3. **Behavior contract** — deterministic rules that must match across platforms: shadow scoring tokenization (word vs syllable), Leitner box scheduling, scorecard metric formulas, VAD thresholds, audio format (16kHz mono PCM WAV).

### Phase B — Skeleton + auth + voice restore
`android/` Gradle project, Compose, `supabase-kt`. Sign-in → restore `voiceCloneId` → play one TTS line in the user's own voice. (Proves the magic moment end-to-end.)

### Phase C — Talk vertical slice
The full call loop: live STT → `gemini` Edge Function structured turn → cloned-voice TTS → auto VAD turn-taking → session end → summary. One screen, phone-call UI. This is the make-or-break milestone.

### Phase D — Learning loop
Summary → drill ingestion (SRS) → profile absorb → next-conversation prompt. **Brain-lift trigger point**: promote prompt construction + summary analysis into Edge Functions here rather than porting ConversationEngine to Kotlin.

### Phase E — Breadth
Watch, Practice, Progress tabs; widgets; Play Billing → credits; language switcher (contract already multi-language).

## Sequencing vs multi-language work
Multi-language Phases 0–2 (iOS) and Android Phase A (contracts) are complementary — the contract doc IS the multi-language `(user, lang)` spec. Do them together; start Android Phase B after the contract exists, so Android never builds against the single-language assumption.

## Risks
1. **Logic drift** (worst long-term risk) — mitigated only by the brain-lift discipline: never port engine logic to Kotlin, promote to Edge Functions.
2. **Android audio fragmentation** — device-dependent capture latency/AEC; validate the Talk slice on low-end hardware early.
3. **STT parity** — Android `SpeechRecognizer` quality varies by vendor; keep the Whisper-endpoint fallback in the design.
4. **Two-store billing reconciliation** — one user could subscribe on both stores; the credits model absorbs this (grants stack), but define the policy before Play launch.
