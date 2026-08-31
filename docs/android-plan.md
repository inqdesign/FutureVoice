# Android Version Plan

> Native Kotlin + Jetpack Compose client sharing the Supabase backend with iOS.
> Written 2026-07-29. iOS is the reference implementation.
>
> **Status (2026-08-30): Phase A + B done, Phase C in progress.** `android/`
> builds and runs on the emulator: sign-in → `voice_clones` restore → Gemini
> SSE turn → cloned-voice streaming TTS → VAD turn-taking, and since 2026-08-26
> the call is METERED (`TalkMeter.kt` ↔ `talk-tick`, idle seconds free, both
> 402 walls told apart). Since 2026-08-30 a call also **puts itself down**
> after 30 s of nothing (`TalkPhase.PAUSED`, `behavior.md` §9 — same predicate
> the meter bills on) and can be paused/resumed by hand, and the Talk screen
> reads every string from the generated catalog (see "Strings" below). Since
> 2026-08-31 a talk is PERSISTED (`SessionStore.kt`, iOS's on-disk contract)
> and SUMMARIZED through the new `session-summary` Edge Function (prompt
> server-side; see `edge-api.md`) — verbatim guards and title→topic ported.
> Since 2026-08-31 the LOOP CLOSES: vocab/drill/carry-over/profile ingestion
> are ported and verified against golden vectors PRODUCED BY THE SWIFT
> IMPLEMENTATION (`scripts/android/gen-vectors.sh` →
> `docs/contracts/vectors/summary-ingestion.json`, 9 JVM tests). Known gap:
> Android has no lemmatizer yet — `VocabLemmas` returns surface tokens, so
> vocab counts lag iOS and `distinct_words_by_cefr_level` stays empty. Since 2026-08-31 (evening) onboarding has begun:
> the 4-question SETUP flow and the VOICE-CLONE act (consent → 60–90 s
> scripted read with a fixed record bar → measured quality review →
> SNR-driven denoise decision → multipart clone → greeting) are built and
> verified on the emulator up to REVIEW — the upload itself is untested on
> purpose (a real clone spends an ElevenLabs slot and would replace the dev
> account's voice; first real-device run covers it). The clone script is
> EXTRACTED from `VoiceCloneScript.swift` by `scripts/android/
> gen-clone-script.py`, never retyped. The Talk home now carries the day
> (metered `TalkTimeLog` vs the setup goal) and **In the news** (platform
> pool, cache-first + pending-poll, story tap → topic + grounded facts into
> the prompt). Since 2026-09-01 onboarding is
> ACCOUNT-FREE in the iOS order: "Get started" opens an anonymous session
> (verified `is_anonymous: true` on a fresh AVD), the clone happens on it,
> and the sign-up asks to KEEP the voice (`AccountScreen`; Google/Apple
> buttons gated on the owner's provider setup). Me screen, Google sign-in
> code-ahead (`GOOGLE_WEB_CLIENT_ID` gate) are in. Scenarios v1 are in via
> the NEW `topic-engine` Edge Function (brain-lift #3's first slice —
> categorize, prompt extracted from Swift; iOS untouched): compose free-text
> → category/summary (never blocks) → saved template → in-scene talk with
> `origin=scenario`. The review loop is
> visible end to end: a drill DECK (Got it graduates — iOS rule), and a
> talk DETAIL page (score · corrections · offered expressions · grammar ·
> transcript). WATCH's core is live
> (2026-09-01): the NEW `scenario-curriculum` Edge Function (prompt +
> sceneScale extracted from Swift) writes the scene, lines play one by one —
> the learner's side in their OWN clone on the fidelity model, the
> counterpart on a preset — under ONE `scene_key` (one count per scene), and
> the take absorbs into the book (scene replaces, study items accumulate).
> A dormant Play Billing client wakes when `google_product_id`s exist.
> SHADOWING's deterministic
> half is ported (`ShadowScore` — expandForDiff/tokenize/align/curve,
> 7 golden-vector cases incl. contractions, digit spell-out, Korean
> syllables) with a line screen off the talk page: listen (cached TTS) →
> say it → score + diff-colored words. Karaoke timing + coach bullets later.
> The DAILY CALL v1 rings
> (exact alarm → CATEGORY_CALL full-screen notification with the SAME
> bundled two-tone warble, Answer opens the talk directly — Android draws
> the real incoming-call surface iOS cannot). Voicemail scripts, callbacks
> and outcome history ride in with the VoicemailEngine brain-lift.
> Still missing from the
> slice: real-mic
> STT validation, and Apple web OAuth (a Services ID + secret the app can't
> set up for itself — until then debug builds sign in with a test email).
> `ConversationEngine.kt` is a 2026-08-04 port and has drifted from Swift
> since; the fix is the Phase D brain-lift, not a re-port.
>
> **Scope (2026-08-26): Android is a standalone launch for Android users with
> full iOS parity — see `android-launch-roadmap.md`.** The "restore, never
> re-clone" and "Apple-only sign-in" lines below describe the order of the
> first spike (a voice already on the server was the cheapest way to prove
> the loop), NOT the product. An Android user clones on Android, signs in
> with Google, and pays on Play.
>
> **Emulator caveat (2026-08-26):** the Pixel_9 AVD's virtual mic delivers
> loud, transcribable noise regardless of the host input volume (level pins at
> 1.0, `SpeechRecognizer` keeps producing partials, no turn ever endpoints —
> the café case, permanently). So on the emulator every listening second is
> "someone talking" and BILLS; that is the meter being right about a wrong
> room, not a bug. Silence/idle behaviour and real-mic STT can only be
> verified on a device.

## Strings: one catalog, generated resources

`FutureVoice/Resources/Localizable.xcstrings` is the ONLY place a UI string is
authored (roadmap §0.4). `scripts/android/gen-strings.py` turns it into
`android/app/src/main/res/values/strings_catalog.xml` (en, the source
language) and `values-ko/strings_catalog.xml`; both are committed and
`--check` fails when they lag the catalog. A key becomes
`R.string.<slug of the English text>` — `"Free talk"` → `R.string.free_talk`
— so a Kotlin call site can be read off the iOS one. Two keys that slug alike
(`Accent` / `Accent: %@`, `Future self` / `Future Self`) BOTH get a hash
suffix and a comment carrying the key, so a name never silently changes
meaning when a sibling appears. Format specifiers are rewritten (`%@` → `%s`,
`%lld` → `%d`) and made positional when there are several. Skipped on
purpose: `shouldTranslate: false`, `extractionState: "stale"`, blank keys.

A string Android needs that iOS doesn't (`Connecting…`, `Ended`, `Resume`)
is added to the CATALOG as `extractionState: "manual"` with its Korean written
— never to a `strings.xml`. `res/xml/locales_config.xml` declares en + ko so
the per-app language setting resolves through the same fallback; the app's
own language switch (`UILanguage` = the learner's pick, not the phone's) is
M0 work and will drive `AppCompatDelegate.setApplicationLocales`.

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
