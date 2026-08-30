# Android Launch Roadmap — full parity with iOS

> Written 2026-08-26. Supersedes the SCOPE of `android-plan.md` (whose
> architecture decisions still stand). **Android is a standalone launch for
> Android users: the same product, same features, same spec as iOS.** It is
> not a companion for iPhone owners, not "restore the clone only", not
> Talk-only. Every item below is measured against the iOS app as it stands
> today (~64k lines of Swift; `CLAUDE.md` is the feature map).

## 0. Ground rules

1. **Same product, not same code.** Where the platform differs (alarms,
   widgets, billing, background audio, STT) Android gets the native
   equivalent that produces the same experience. Where iOS made a product
   decision (idle seconds are free, a seat is a bar not a rank, the card is
   the offer) Android inherits the decision, never re-derives it.
2. **One brain.** LLM prompt construction and analysis are promoted into Edge
   Functions and iOS is switched to them (the plan's brain-lift). Nothing
   with a prompt in it is ported to Kotlin. `ConversationEngine.kt` is a
   temporary fork and is deleted in M1.
3. **Deterministic logic is ported WITH golden vectors.** Scoring, SRS
   scheduling, endpointing, alignment, carry-over detection: each gets a
   fixture file (`docs/contracts/vectors/*.json`) produced by the Swift
   implementation and a test on both platforms. A number that differs across
   platforms is a bug, on whichever side is newer.
4. **One string catalog.** `Localizable.xcstrings` (1,637 keys, ko/en) is
   the source; a script generates Android `values*/strings.xml` from it. No
   string is authored twice.
5. **Same UI rules, translated.** iOS: native SwiftUI only, system colours,
   one `DialogueLine`. Android: Material 3 only, dynamic/system colours,
   `Color.coreClub` indigo reserved for the Core, one `DialogueLine`
   composable. Voice first — a phone call, not a chat app.
6. **Every milestone ends in an installable internal-test build.** No
   milestone is "infrastructure only".

## 1. Inventory: what parity means, feature by feature

Sizes are relative to the iOS implementation (lines are the iOS files, as a
proxy for scope): **S** < 300, **M** 300–1,000, **L** 1,000–2,500, **XL** more.
"Android" says what replaces the iOS mechanism, not just "port".

### 1.1 Foundation
| Item | iOS | Android | Size |
|---|---|---|---|
| App shell, 4 tabs, deep links (`futurevoice://`) | `RootTabView`, `RootView` | Compose Navigation, App Links | M |
| Persistence (all stores, `(user, lang)`-scoped) | JSON-on-disk stores in `Services/` (`SessionStore`, `DrillStore`, `VocabStore`, `ProfileStore`, `PersonaStore`, …) | Same JSON shapes via kotlinx.serialization in `filesDir` — identical on-disk contract, so backup/restore is shared (`BackupService`) | L |
| Models | `Models.swift` (1,272) | `Models.kt` generated/mirrored; field-for-field | M |
| Localization pipeline | `.xcstrings` + `explain()`/`chrome()` | generator script → `strings.xml`; `UILanguage` = app language, not device | M |
| Networking / update / analytics | `NetworkSupport`, `AppUpdateService` (`app_release`), PostHog | OkHttp (exists), `app_release` gets a `platform` column, PostHog Android | S |
| Audio stack | `AudioRecorder` (16 kHz mono WAV), `AudioPlayer` (rate, ducking), `AudioSessionRouting` (worn mic wins), `AudioLoudness`, `AudioSampleQuality` (SNR) | `AudioRecord`, `AudioTrack`/ExoPlayer, `AudioManager` device routing, ports of loudness/SNR with vectors | L |
| Phrase/turn audio caches | `PhraseAudioStore`, `TurnAudioStore` | same keys `(text, voiceId)` | S |

### 1.2 Onboarding & identity (an Android user starts HERE — nothing exists before this)
| Item | iOS | Android | Size |
|---|---|---|---|
| Welcome + Futureself | `WelcomeView`, `WelcomeHeroes` (1,380), `Futureself.metal` shader, `FutureselfPixels` | AGSL `RuntimeShader` (API 33+), Canvas fallback below | M |
| Setup (native/target language, level) | `SetupFlowView`, `LanguageCatalog` | same | S |
| Persona intake (dictated, parsed) | `PersonaIntakeView`, `GuidedIntake`, `PersonaParser`, `PersonaOnboardingView` | same, parser via Edge (brain-lift) | M |
| **Voice clone** | `VoiceCloneOnboardingView` (1,543), `VoiceCloneScript`, `CloneScriptStore`, `AudioSampleQuality`, `VoiceAccentSheet`, `VoiceComparisonSheet`, `elevenlabs-voice-clone/-remix` | full port: script reading, take quality/SNR-based denoise flag, accent picks, comparison; anonymous session first, then account | XL |
| Anonymous session → account | `AuthService` (anonymous → `linkIdentityWithIdToken` Apple) | anonymous → **Google** link (primary on Android) + **Apple web OAuth** (iPhone switchers). Same rule: `isSignedIn`, never `session != nil` | M |
| Consent, daily-call onboarding, onboarding paywall | `ConsentStore`, `DailyCallOnboardingView`, `OnboardingPaywallView` | same order: clone → meet → account → daily call → plans | M |

### 1.3 Talk
| Item | iOS | Android | Size |
|---|---|---|---|
| Home | `ConversationHome` (1,079): today status, free talk, scenarios, In the news (`NewsTopicSection`, `news-topics`), missed-call row, avatar ring (tier-aware) | same | L |
| Live call | `ConversationView` (3,622) + `LiveTranscriber` (996): VAD tiers, café rules, chunk ASR, speculative reply, deferred turn work, correction guards, `TalkGoalChips`, idle pause, interruptions, lock-screen controls, `TalkMeter` | Android has ~35% of this (`TalkViewModel`, `TurnTaking`, `LiveTranscriber`, `TalkMeter`). **Audio-grounded transcription needs raw PCM alongside live partials**: use `RecognizerIntent.EXTRA_AUDIO_SOURCE` (API 33+) so the app captures with `AudioRecord` and feeds the recognizer — one mic, both consumers; below 33 fall back to recognizer-only (`transcript: null`, as the contract already allows). Background call = foreground service (`microphone` + `mediaPlayback`) + `MediaSession` for lock-screen play/pause | XL |
| Openers | `FreeTalkOpeners` (bundled per language), `HeroGreeting`, pre-synthesized greeting | bundle the same files; greeting synthesized in the launcher | S |
| Scenarios launcher / builder | `ScenarioBuilderSheet`, `TopicEngine` (597), `TopicStore`, `ScenarioIdeaCache` | UI port; `TopicEngine` via Edge | M |
| Gate | `BillingGate` (needsSubscription only, "no" never from cache) | same rule, one funnel | S |
| Wrap-up | `SummaryProgressView` (streamed `Progress.absorb`), summary sheet, `ScorecardView` | same board, same key-order semantics | M |

### 1.4 Session-end pipeline (the loop must close identically)
| Item | iOS | Android | Size |
|---|---|---|---|
| Summary | `SessionSummarizer` (372) + summary prompt in `ConversationEngine` | Edge Function `session-summary` (brain-lift), streamed; client absorbs | M (server) + S |
| Deterministic metrics | `ScorecardMetrics`, `CarryoverDetector` (326), `KoreanMorph`, `CoreVocabulary`/`WordCatalog`, `PracticeStats` (streak), `TalkTimeLog` | ports + vectors | L |
| Ingestion | `DrillStore.ingest` (Leitner 0–5, `looksLikeMetaRule`), `VocabStore.ingest`, `ExpressionCatalog` (heard/used merge), `TalkCurriculum`, `LearnerProfile.absorb` via `ProfileStore`, `rememberAboutUser` | ports + vectors | L |
| Widgets/daily-call refresh at session end | `StudyWidgetRefresher`, `AppState.refreshDailyCall(force:)` | same hooks | S |

### 1.5 Watch
| Item | iOS | Android | Size |
|---|---|---|---|
| Tab + composer | `WatchTab` (643), `SituationComposerSheet`/`ScenarioComposerSheet` (1,018), likely-situations chain, `ScenarioStore` | UI port | L |
| People | `CounterpartsListSheet`, `CounterpartVoiceIntakeView` (461), `CounterpartParser`, `CounterpartDetailView`, `AvatarStore`, preset voices | UI port; parser via Edge | M |
| Scene | `WatchView` (958), `SceneWatchView`, `ScenarioCurriculumEngine` (344), `DialogueEngine`, `WatchDialogueStore`, karaoke via `with_timestamps` + `LocalAlignment` (230) | engines via Edge; alignment port + vectors; `begin_scene_play` count metering; fresh takes + `absorb` | L |
| Find people | `FindPeopleSheet` (472), `PublicPersonaService` (315), `PublicIntroView`, `CoreSeal` | same table/RLS, auto-sync rule, `manualIntroKey` | M |

### 1.6 Practice
| Item | iOS | Android | Size |
|---|---|---|---|
| Tab + queue | `PracticeTab` (1,453), `DueReviewView`, `ReviewQueue`, `StudyScheduleStore`, `GoalStore` | UI port + scheduling ports with vectors | L |
| Decks | `StudyDeckView` (994; drag-to-file folders), `DrillSheet` (1,089), `DailyWordsView`/`DailyExpressionsView` (`pick` funnel gate), `PracticeSessionView`, `SentencesView` | UI port; folder = window on return time, one implementation | L |
| Books | `BookCards`, `ScenarioDetailView` (649), `ConversationDetailView` (1,643; Continue/Replay, `TalkTranscriptView` sequential audio), `HistorySheet` | UI port | L |
| Library | `VocabularyView` (1,113), `WordsView`, `ExpressionsView` (591), `word-entry`, `Translator`, `BookGlossary` | UI port | L |
| Shadowing | `ShadowDrillView` (1,592), `ShadowEngine` (470; deterministic score, word/syllable tokens), `ShadowTimelinePlayer`, `ShadowBrowserSheet`, `ShadowAttemptStore`, `SavedLineStore` | UI port; score port + vectors; feedback via Edge | XL |
| Export | `BookExport` (470; one `BookDocument` → PDF + Markdown), `BookExportMenu` | same `BookDocument`; PDF via `WebView` + `PrintDocumentAdapter` (HTML-authored for the same reason) | M |
| Enrichment / reminders | `DrillEnrichmentEngine`/`Store`/`Sheet`, `DrillReminder`, `ItemReminder`, `ReviewNotifications` | engine via Edge; `WorkManager` + notifications | M |

### 1.7 Progress
| Item | iOS | Android | Size |
|---|---|---|---|
| Tab | `ProgressTab` (2,171): CEFR estimate, per-skill chip pages, 14-day rep bars, `LevelHeader`, `ActivityView` (538) | UI port; estimate is deterministic → vectors | L |
| Weekly report | `WeeklyReportEngine` (375), `WeeklyReportStore`, `WeeklyReportView` | engine via Edge; unlock on accumulated talk time | M |

### 1.8 The daily call
| Item | iOS | Android | Size |
|---|---|---|---|
| Ring | `DailyCallAlarm` (AlarmKit), notification fallback, bundled `ringtone.wav` | `AlarmManager.setAlarmClock` + **full-screen intent notification** — Android CAN draw an incoming-call screen (`CATEGORY_CALL` style); ringtone via notification channel sound. Permissions: `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT` (Play policy declaration), `POST_NOTIFICATIONS` | L |
| Plan, outcomes, callbacks, history, missed-call trace | `DailyCallScheduler` (615), `DailyCall` (289), `DailyCallStore`, `DailyCallSheets`, `DailyCallCallbackSheet` | port; multiple times/day all armed at once; `.missed` settled on launch | L |
| Voicemail | `VoicemailEngine` (288), PCM→WAV under 30 s, same `(script, voiceId)` cache = the call's first line | engine via Edge; synthesis at session end | M |

### 1.9 The Core
| Item | iOS | Android | Size |
|---|---|---|---|
| Service + view + seal | `CoreClubService` (437; `core_my_progress`, arrivals polling → quiet local notification), `CoreClubView`, `CoreSeal` | port; `talk-tick` already carries `language` | M |

### 1.10 Me / account
| Item | iOS | Android | Size |
|---|---|---|---|
| Settings | `MeTab` (1,278): Subscribe row, Talk time (`PlanPageView`), Usage (`UsageDetailView`, `UsageBreakdown`), `CreditGuideView`, profile + learned notes (swipe to forget), languages (`AddLanguageSheet`, `LanguageScope` — never gated), app language, mic preference, voices (rename/delete/remix/accent), daily call times, Find-people intro, Invite (`InviteView`, `ReferralService`), Feedback, Backup, Account delete (`account-delete`), Consent | UI port | XL |
| Paywall / allowance | `PaywallView` (841; the card IS the offer, same four rows), `DailyAllowanceSheet`, `AccountStatus` (359; `tierName` keyed, `isLightPlan`, `isUncappedTalk` from tier) | same copy rules, `TalkWall` already split | M |
| Trial/update sheets | `TrialReminder`, `UpdateAvailableSheet` | port | S |

### 1.11 Billing (server + client)
| Item | iOS | Android | Size |
|---|---|---|---|
| Purchase | `StoreKitService` (236) | Play Billing Library (current major): 4 subscriptions (Light/Plus × monthly/yearly), `obfuscatedAccountId` = user id (the `appAccountToken` twin) | M |
| Server | `apple-webhook` (323; hand-verified JWS) | **`google-webhook`**: RTDN (Pub/Sub push) → verify with the Play Developer API → same `user_subscriptions` row; `subscription_plans.google_product_id` column; trial pro-rating unchanged | M |
| Policy | — | **two-store rule** (one user, two stores): entitlement = max of active rows; a second purchase is refused client-side when an entitled row exists | S |

### 1.12 Widgets
| Item | iOS | Android | Size |
|---|---|---|---|
| Vocabulary + Expressions | `FutureVoiceWidget` (497) + `StudyWidgetShared` (1,027): App Group snapshot, 30-min window, app-language chrome | Glance app widgets reading a snapshot file the app writes; `WorkManager` periodic refresh | M |

### 1.13 Brain-lift (server, shared by both apps)
Engines to promote, each as one Edge Function with the prompt moved verbatim and
`CoachingLanguage.contract` as a shared module; iOS is switched over one at a
time behind a flag, then the Swift prompt is deleted:

`ConversationEngine` (conversation prompt, summary), `TopicEngine`,
`ScenarioCurriculumEngine`, `DialogueEngine`, `ShadowEngine` (feedback only —
the score stays client-side and deterministic), `WeeklyReportEngine`,
`DrillEnrichmentEngine`, `VoicemailEngine`, `CounterpartParser`,
`PersonaParser`, `FreeTalkOpeners` (rotating pool), `NewsTopicEngine`,
`Translator`, `UtteranceTranscriber`. ≈ 4,500 lines of Swift prompt and
schema code become ≈ 3,000 lines of TypeScript. **Field order in every
schema is load-bearing** (`{reply, suggestion}`, summary `about_user` last) and
moves unchanged.

This is the single largest de-risking item and it also touches the LIVE iOS
app; it ships engine by engine, never as one cut-over.

## 2. Milestones (each ends in an internal-test build)

| # | Build says | Contains | Depends on |
|---|---|---|---|
| **M0 — "A stranger can install, clone, pay, and talk"** | Onboarding (1.2) end to end, Google + Apple sign-in, Play Billing + `google-webhook` (1.11), foundation (1.1), localization pipeline, the existing Talk slice | Google/Play console setup (§4) |
| **M1 — "The loop closes"** | Talk parity (1.3), session-end pipeline (1.4), brain-lift #1: conversation + summary + openers + transcribe; `ConversationEngine.kt` deleted | M0 |
| **M2 — "Review"** | Practice (1.6) + Progress (1.7), remaining deterministic ports with vectors, brain-lift #2: enrichment, weekly, translator, word-entry | M1 |
| **M3 — "Rehearse"** | Watch (1.5) incl. Find people, scene metering, brain-lift #3: topic/curriculum/dialogue/parsers | M1 (M2 in parallel) |
| **M4 — "It calls you"** | Daily call (1.8), the Core (1.9), widgets (1.12), Me complete (1.10), brain-lift #4: voicemail | M1 |
| **M5 — Launch** | §3 checklist, closed beta on a device matrix, production rollout | M0–M4 |

Rough weight by milestone, from the sizes above (XL = 4, L = 2, M = 1, S = ½):
M0 ≈ 12 · M1 ≈ 14 · M2 ≈ 16 · M3 ≈ 10 · M4 ≈ 9 · M5 ≈ 3 — **≈ 64 units**,
against the ≈ 3 units that exist today. M2 and M3 are independent of each
other and can run interleaved; nothing after M1 can start before M1 because
every review surface is fed by the session-end pipeline.

## 3. Launch checklist (M5) — none of this is in `android-plan.md`

- Play Console: app, package `com.roro.futurevoice`, upload key + Play App
  Signing, internal → closed → production tracks, `fastlane supply`.
- Data safety form + privacy policy covering microphone, voice clone
  (biometric-adjacent voice data — say where it is stored, how it is deleted:
  `account-delete`, nightly `cleanup-anonymous-voices`).
- Policy declarations: foreground service types (`microphone`,
  `mediaPlayback`) with the in-app justification video; `USE_FULL_SCREEN_INTENT`
  (alarm/call use); exact alarms; background microphone is only ever inside a
  live call the user started.
- Permission flows: `RECORD_AUDIO`, `POST_NOTIFICATIONS`, exact alarm,
  full-screen intent — each asked at the moment it is first needed, as on iOS.
- Device matrix before beta: a low-end device (capture latency, AEC), a
  Samsung (vendor `SpeechRecognizer` quality), a Pixel, one on API 26–32 (no
  `EXTRA_AUDIO_SOURCE`), one on API 34+ (foreground-service and
  full-screen-intent policy changes). **The emulator cannot verify idle
  billing or STT** (its virtual mic is noise — see `android-plan.md`).
- Observability: PostHog events with the same names as iOS (`distinct_id` =
  Supabase user id, note the iOS uppercase quirk), `talk_turn_timing` /
  `talk_asr_upgrade` rows from Android tagged by platform, crash reporting.
- `app_release` row per platform (`scripts/beta.sh` twin), web landing gets
  "Get it on Google Play", ASC/Play listing metadata shared from
  `fastlane/metadata`.
- Store listing: screenshots per language (`DebugCaptureHarness` has an
  Android twin so the captures come from the same fixtures).

## 4. What only the owner can do (blocking; start now, in parallel with M0)

1. Google Play Console developer account; create the app.
2. Google Cloud project: OAuth client IDs (Android + web) for Google sign-in;
   enable the Google provider in Supabase Auth with them.
3. Apple: a **Services ID** + key for "Sign in with Apple" on the web (Android
   uses the web flow); configure in Supabase Auth. (Same identity as the
   iPhone app, so an iPhone user who switches keeps their account.)
4. Play Billing: four subscription products mirroring the ASC ones; Real-time
   developer notifications topic (Pub/Sub) pointed at `google-webhook`;
   a service account with the Play Developer API for purchase verification.
5. Upload key custody (or Play App Signing), and the privacy policy URL.
6. Test devices per the matrix in §3.

## 5. Where this leaves `android-plan.md`

Its architecture (native Kotlin, monorepo, Supabase as the shared brain,
brain-lift instead of porting prompts) is unchanged. Its scope was written
for a first slice and is superseded: the "restore, never re-clone" and
"Apple-only sign-in" lines described the ORDER of the first spike, not the
product. The product is this document.
