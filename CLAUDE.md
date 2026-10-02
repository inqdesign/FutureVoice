# Future Voice — Claude Code Context

> Read this before making changes. `docs/SPEC.md` has the original concept but is STALE (still says Phase 1) — this file and the code are the truth.

## What this app is

iOS SwiftUI app. A user clones their own voice once (ElevenLabs), then practices a target language by talking with a "fluent self" — same voice, fluent output. Gemini is the conversation brain and analyzer; ElevenLabs synthesizes every fluent-self line in the user's cloned voice.

**Current state (2026-06): four-tab app in TestFlight prep, NOT a Phase-1 spike.**

Tab order: **Talk · Watch · Review · Progress** (`RootTabView`) — do → create → review → measure. The third tab is still `PracticeTab` in code; its LABEL is "Review" (복습) in every language since 2026-09-30 — a billing commit had flipped the ko label to 연습 by accident on 2026-09-04.

- **Talk** (`ConversationHome`) — the speaking launcher, one tap to start the call. A List: Today status (minutes/goal, streak, talks → ActivityView), Free talk, **Scenarios** (header "+" → builder), **In the news** (`NewsTopicSection`, refresh + interests in its header). Every row tap launches `ConversationView` phone-call-mode conversation (live STT → Gemini structured turn `{reply, suggestion}` → cloned-voice TTS, auto VAD turn-taking; per-turn suggestions as inline chips). `MeTab` opens from this tab's header.
- **Watch** (`WatchTab`) — simulate a specific situation BEFORE it happens and mine ideas (how the fluent self handles it, which expressions it uses). Three entries, all landing in `ScenarioComposerSheet`: ① a stories-style People row (tap a persona → composer scoped to them, with relationship-grounded ideas from `TopicEngine.suggestForCounterpart`, cached on the counterpart), ② **"Your own situation"** (`Mode.custom`) — describe the real upcoming thing in the composer's BOX, with material attached (no person needed; empty `Scenario.role` makes the scene infer its own counterpart), ③ **"Common situations"** (`Mode.browse`) — the drill-down chain (cafe → ordering → order came out wrong). **The two doors are now genuinely different screens, not one composer opened twice** (2026-09-26, user decision): writing lives in the box and ONLY there, and browsing is tap-tap-tap with no text field at all — a category grid, a breadcrumb to undo a step, and at the leaf the assembled sentence READ-ONLY above the CTA. The old "leaves prefill the composer, always editable" is gone: someone who chose to pick rather than write should not be handed a field, and the words are still changeable because a saved card reopens this sheet in EDIT mode, where the field is live. Attaching is the writing door's alone — the browse door shows the Material section only when the scenario already has sources to manage. **Watch** mints the `Scenario` and plays its scene in `SceneWatchView` (`ScenarioCurriculumEngine` — the same generation stocks the book Practice reviews). A saved `Scenario` is a reusable TEMPLATE: tapping it under "Your scenarios" writes a FRESH take every time (`SceneWatchView(freshTake:)` — per-run idempotency key, previous titles passed as `avoidTitles`), and the new take is `absorb`ed into the scenario's book — latest scene replaces the old, study items accumulate, mastery survives. Replaying past material is Practice's job, never Watch's. No browsing here; books live in Practice. The People row's last bubble is **Find people** (`FindPeopleSheet`) — see below.
- **Practice** (`PracticeTab`) — the REVIEW home; everything here came out of an activity. Three layers: today's cross-cutting SRS queue (`DrillStore` Leitner boxes 0–5 + shadow picks), the **Books** shelves behind chips (**Talks · Topics · Scenarios**), and the Library dictionaries (vocabulary / expressions / shadowing). Every book has the same anatomy — one scene + words/lines to master, then archive. Watch books = `Scenario` + `ScenarioCurriculum` (`ScenarioDetailView`; scene behind its Watch button). Talk books = a finished `Session` whose material is DERIVED by `TalkCurriculum` (fluent-self pickup words + corrected lines as shadow material, mastery via `VocabStore`/shadow attempts — never persisted); their page is `ConversationDetailView` (Continue / Replay / **Say it again** (다시 말하기) — Watch books carry the same button under Talk · Watch; raw transcript + sequential audio replay behind Replay in `TalkTranscriptView`, the whole talk done again, the learner's part spoken the corrected way, behind Say it again — see below). **Either book exports** from its ⋯ menu (`BookExportMenu` → `BookExport.swift`): both types flatten into ONE `BookDocument`, rendered as an A4 PDF (annotate on an iPad, or print) or Markdown (paste into a notes app). The PDF goes through `UIMarkupTextPrintFormatter` + `UIPrintPageRenderer` because it's the only thing on iOS that flows arbitrary-length text across pages without hand-rolled CoreText pagination — which is why the document is authored as HTML. Add a field to `BookDocument` and BOTH renderers pick it up; never render a book straight to a format.
- **Progress** (`ProgressTab`) — measured CEFR estimate + per-skill pages behind swipeable chip tabs, plus the activity/effort panel (14-day rep bars).
- **Home-screen widgets** (`FutureVoiceWidget` target) — TWO widgets in one bundle, one per `StudyWidgetSection`: a **Vocabulary** widget (notebook `studying` words + recent used, CEFR tag, taps `futurevoice://vocab`) and an **Expressions** widget (`VocabStore.expressionEntries()`, taps `futurevoice://expressions`). Both are list widgets whose window slides every 30 min. App-side `StudyWidgetRefresher` writes a per-section snapshot into the App Group on every `DrillStore`/`VocabStore` write and at scene-phase edges; the extension only reads. App-side `StudyWidgetRefresher` writes a snapshot into the App Group (`group.com.roro.futurevoice`) on every `DrillStore`/`VocabStore.studying` write and at scene-phase edges; the extension only reads. The shared contract `FutureVoice/Shared/StudyWidgetShared.swift` compiles into BOTH targets — keep it free of Models.swift/store imports. Widget tap deep-links `futurevoice://practice` (handled in `RootTabView`). The widgets speak the app language, not the phone's — see "UI text has ONE language" below.
  **The refresh is COALESCED and never runs in the write's own run-loop turn** (2026-09-23). `refreshBook` rebuilds every talk book (`TalkCurriculum.build`, NLTagger over the whole session) on the main actor, and a single "I know" on a word card writes three files, each asking for it — measured 30 books ≈ 515 ms in the simulator, paid between the tap and the button repainting, which is what the learner reported as the toggle stuttering. `schedule()` now runs ONE refresh 0.4 s after the last write; only the BACKGROUND edge still calls `refresh()` directly (iOS may suspend right after it). The active edge and `RootTabView.onAppear` go through `schedule()`, whose pass yields the main thread after every talk book (2026-09-28): on a cold launch both used to rebuild every book synchronously while the Talk ring drew, and the first `coreLevelLabel` loaded the CEFR list + tagger on main (~230 ms) — those two are now warmed off-main in `FutureVoiceApp.init`. Practice's talk-book pass yields per book for the same reason (first tab switch). The build itself got cheap the same day: `VocabStore.lemmas(in:)`, `offListContentWords(in:)` and `lookupKey(for:)` memoize per text + tagger language (`TextMemo`, lock-guarded, bounded), and `CarryoverDetector.normalized`, `TalkCurriculum.sentences(in:)`, `WordSplitter.count` are single-pass — a warm rebuild of 30 books is ~37 ms (`TalkCurriculumTimingTests` prints it). Don't put a tagger call back on a per-word path without going through the memo.

## Sync between the learner's own devices (iCloud, opt-in) — 2026-09-18

A phone and a tablet must feel like ONE app: a talk on the phone is on the
tablet's Practice shelf, its cards in the tablet's deck, the ring reads the
same, and a review on the tablet moves the phone's deck. Everything under
`FutureVoice/Services/Sync/`. Decided the same day it was built, and the
reasons are the design:

- **CloudKit, the learner's OWN iCloud** — not Supabase. Audio is a
  gigabyte per learner and it's their storage, not ours; nothing they said to
  their future self lands on our servers. iPhone people own Apple devices;
  Android gets its own transport later on the SAME merge rules.
- **Opt-in, default OFF**, Me → Devices (`SyncSection`). It spends their
  iCloud and a sync bug can damage data, so single-device learners are
  untouched. `SyncStore.isEnabled` is keyed per APP ACCOUNT (a family iPad
  can hold two). Never sync an anonymous session. **Turning it off deletes
  nothing anywhere**; "Delete from iCloud" is a separate confirmed button.
- **Audio goes too** (user: "a few GB of iCloud is fine"). Items first, audio
  after, so a second device is useful within a minute. Blob uploads are
  Wi-Fi only unless the Me toggle says otherwise.
- **A pass keeps going after the app closes** (2026-09-22). Leaving the
  app mid-pass holds a `beginBackgroundTask` (~30 s) around it; after that,
  `SyncBackground` hands the rest to iOS — a `BGAppRefreshTask` (pulls the
  other device's talks before this one is opened) and, while items or audio
  are still waiting, a `BGProcessingTask` that iOS runs idle/overnight, which
  is what carries a first sync's gigabyte without the learner holding the
  app open. Every pass is resumable (the index saves per batch), so being cut
  off anywhere costs nothing. Every pass — `enable` included — goes through
  `requestSync`; calling `runSync` directly ran two passes on one index.
- **The server wakes the other device** (2026-09-25, `SyncPush`). Sync had
  two clocks and both were the learner's — a foreground pass, and
  `SyncBackground`'s tasks on iOS's own schedule — so the tablet could only
  learn about the phone's talk by being picked up, which is the one moment
  the delay is visible. A **CloudKit zone subscription** is the third, and
  it is the server's: `CKRecordZoneSubscription` with
  `shouldSendContentAvailable` only, so it is SILENT — no alert, no badge,
  no sound, and therefore **no notification permission**; opting into sync
  can never be the reason a permission sheet appears. The wake runs the
  same `requestSync` every other trigger runs, `.items` scope (a silent
  push is granted seconds, and what it is for is that the TALK is here;
  audio stays with the background tasks). **It is not a guarantee** — iOS
  drops silent pushes freely — so the foreground pass is still the one that
  always runs; this only makes it earlier. Three facts to keep: the
  subscription is **one per ZONE, shared by every device of the account**
  (a private-database subscription already pushes to all of them, and the
  zone is in the id because a shared iPad can hold two app accounts); so
  **turning sync off on one device does NOT delete it** — that device
  unregisters from APNs instead (`SyncPush.deactivate`), because the
  learner said nothing about their tablet, and only "Delete from iCloud"
  speaks for the account; and **a push comes back to the device that caused
  the change** (CloudKit doesn't exempt the sender), which is left alone —
  the pull finds its own records, the merge produces nothing, and the pass
  costs one empty `changes` call, whereas suppressing it would mean
  guessing which of our own writes a push belongs to. `aps-environment`
  rides per config (`$(APS_ENVIRONMENT)`), but the SIGNING PROFILE decides —
  measured: a Release build signed with a development profile comes out
  `development` whatever the entitlement says, and an archive takes
  `production` off the distribution profile — so that line documents intent,
  it is not the switch. The Push Notifications capability is on both App
  IDs as of 2026-09-25; adding it was what `-allowProvisioningUpdates` was
  needed for, and `beta.sh`'s API key cannot do it (use
  `ASC_KEY_ID=none`). It is the app's only SILENT push;
  everything a learner can read comes from `push-send` (below).
  **Testing it has three layers and only the first is ours**:
  `scripts/sync-push-probe.sh` hand-delivers the payload to a booted
  simulator and `SyncPushTests` pins its shape, because the subscription id
  sits INSIDE `ck.fet` beside the zone — at the top of `ck`, where anyone
  would put it, `CKNotification` still returns a zone notification but with
  a **nil `subscriptionID`**, which reads as "somebody else's push" and is
  indistinguishable from no push at all. Then the subscription and APNs
  registration, which need one real device; then delivery, which needs two
  and is the only layer that says the feature works. A probe against a
  signed-out install proves nothing: registration only happens once an
  account has sync ON, so the delegate is never called. Each outcome is an
  `os.Logger` NOTICE (`subsystem com.roro.futurevoice`, category
  `sync-push`) — a silent wake draws nothing, and on a device Console.app
  keeps notice and drops debug.
- **Nothing a screen waits on includes audio** (same day). `enable()` runs
  an `.items` pass and returns — the second device's "Continue" used to sit
  on "Downloading audio 37 of 412…" until the last file, which is the
  "useful within a minute" promise above broken on the one screen it was
  made for. Audio follows in an `.everything` pass nobody waits on, fetched
  `blobFetchBatch` (10) records per round trip instead of one, NEWEST talk
  first (`observedAt` = the record's `modifiedAt` for a wanted blob; a
  first pull hears of everything at once, so "when this device noticed"
  can't order anything). Every CloudKit op runs `.userInitiated` — CloudKit
  defers `.utility` behind everything else on the device and the network,
  and a pass here is either watched or on a background task's clock.
- **The second device asks** (`SyncContinuePromptView`, `RootView` after the
  auth gate and before setup): a signed-in, un-set-up install whose account
  already has a zone is offered "Continue where you left off?" once per
  account per install. Yes = enable + first pull, then `setupComplete`
  from the pulled persona; no = the toggle waits in Me.
- **And it says so when there is no zone to ask about** (2026-09-25,
  `SyncOtherDeviceHintView`). The opt-in lives on device ONE, but the moment
  anyone wants it happens on device TWO — so a learner who never turned it on
  signs in on a tablet and gets onboarding, which reads as "my account is
  empty" to someone with a month of talks on their phone. Measured: zero
  `sync_enabled` events since the feature shipped, the founder's own phone
  included. The tell is the account's ACTIVE voice clone, already adopted by
  `restoreVoiceCloneFromCloud` — a fresh install holding one recorded a voice
  somewhere else, and a clone made HERE can't reach the branch (setup finishes
  long before the voice step). So `checkSecondDevice` has two answers: a zone
  → the offer above; no zone + a clone → this screen, which says which toggle
  to turn on over there and re-checks on a button. Not a wall — "Start fresh
  on this device" walks into setup — and shown once per account per install
  under its OWN flag (`wasOtherDeviceHinted`), never `wasOffered`: dismissing
  the hint must not suppress the real offer the day a zone appears. The clone
  lands asynchronously, so `RootView` re-asks on `voiceCloneId` — but never
  while either screen is up, or the re-check pulls the offer out from under a
  running pull.
- **A pass is not an EVENT** (2026-09-26). The day after the hint shipped the
  first real learner turned sync on, and their two days produced 427
  `sync_push` rows — 363 of them carrying a SINGLE record, 202 of those one
  audio file — because a write debounces into its own pass and a talk's turn
  audio is one file per pass, so the telemetry counted passes. Ten such
  learners would have cost more in PostHog events than the talking does, and
  none of those rows answered a question: what a diagnosis asks is whether
  the BIG pushes landed (a first sync, a backlog) and whether two devices are
  fighting. `push` now captures only `records >= reportPushFrom` (20) or a
  conflict; `sync_pull` is left alone (it is the proof the other device got
  the talk, and it is a tenth of the volume) and `sync_error` keeps every
  failure. Same day, the same mistake one level up: `SyncPush.handle`'s wake
  was also called `sync_push` — the opposite direction under the engine's own
  name — and is `sync_woken`. In PostHog the three routine kinds are
  **Hidden** event definitions: out of the pickers, still in the data.
- **`BackupService` stays for dev↔release moves only.** It overwrites whole
  files; alternating two devices through it loses whatever overlapped.

**How it works — read this before touching any store's write path.**

- **One record per ITEM, one merge rule per KIND** (`SyncKindRegistry`).
  Never a whole file: two devices rewriting `sessions.json` would overwrite
  each other. Talks union by id (newer edit wins, deletion wins outright and
  cascades to cards + turn audio); cards take the HIGHER progress per field
  (`mergeCards`: box, timesSeen, usedInTalkAt) then `DrillStore.keeper`
  collapses duplicate sentences; word/expression records climb only
  (used > known, count = max); notebook membership, snoozes, hand-removals
  are last-writer-wins; dismissed expressions are a permanent union;
  per-day counters take the MAX per day, never the sum; persona scalars LWW
  on `updatedAt`, its notes union on `dedupeKey`; `enrolledLanguages` is a
  union. `SyncMerge` holds the four shapes (lww / tombstoneWins /
  combineOrNewerDelete / union) — add a kind by picking one, not by writing
  a fifth.
- **Change detection is a DIFF, not instrumentation.** Stores rewrite whole
  files; the engine fingerprints each item (`SyncCanonical` — sorted keys,
  ISO dates; the stores' own encoders are NOT stable across launches) and
  compares against `SyncIndex` (`Documents/sync/<userId>/`, excluded from
  backups). A key in the index but not in the file is a deletion → a
  TOMBSTONE record (`deletedAt`), kept forever; a missing record is never
  a deletion. Write funnels only call `SyncEngine.noteChanged(.kind)` to
  debounce a push (3 s); the foreground pass diffs everything anyway, so a
  forgotten hook self-heals.
- **Loop guard:** a pull updates the index to the MERGED result BEFORE
  writing the file, so the next diff sees nothing to push; `needsPush` is
  the one flag that forces a push when the merge produced something the
  server lacks. Tested: `testPullDoesNotPingPong`.
- **Reads and writes go by PATH** (`Documents/lang/<code>/…`), never through
  the singletons — those are pinned to the active language, and a pull for
  another language still has to land. After a write the handler pokes the
  store (`SessionStore.invalidateCache`, `VocabStore.languageScopeDidChange`,
  `PracticeLog.reloadFromDisk`) and `AppState.adoptSyncedChanges` re-reads
  the published copies. `Turn.audioURL` (an absolute sandbox path) is
  stripped from the payload; every reader falls back to `TurnAudioStore`.
- **CloudKit facts baked in** (`CloudKitTransport`, the only file that sees
  `CKRecord`): one custom zone per account (`nawana-<supabaseUserId>`);
  `recordName` hashes the key because a lemma isn't ASCII; two record types
  (`Item` / `Blob`) so a change fetch can list blobs with `desiredKeys`
  minus the asset — otherwise the second device's first pull downloads the
  whole gigabyte before showing a single talk; payloads over 900 KB ride in
  an asset; `systemFields` (the change tag) is carried in the index and
  re-saved with `.ifServerRecordUnchanged` — a stale tag is `.conflict`, never
  resolved inline: the next pull merges the server's copy. `zoneMissing`
  (deleted from another device or Settings) switches sync OFF locally and
  keeps every file; `quotaExceeded` pauses only the blobs. Dev and release
  use DIFFERENT containers (`$(ICLOUD_CONTAINER)` per config, mirrored into
  Info.plist as `FVICloudContainer`) for the same reason the bundle ids
  differ. Before a release the `Item`/`Blob` schema must be deployed to
  Production in CloudKit Dashboard — Development is JIT, Production is not.
- **`SyncSchema.version`**: bump it on any payload change an older build
  could not read harmlessly. A record from a newer build is applied if it
  decodes and FROZEN in the index either way (never pushed back, never
  tombstoned) — the day an old phone quietly deletes what a new one wrote is
  the day sync is uninstalled.
- **Never synced:** every cache (PhraseAudio, DrillEnrichment, topics, news,
  translations, openers), the daily call (two devices must not ring at once),
  consent, and `BackupService.excludedDefaults`.
- **The voice recording IS synced** (2026-10-01, founder decision, kind
  `.blobVoiceSample`): a learner reinstalled, paid, and was sent to record
  again because `voice_sample.wav` lived on one install. `VoiceSampleStore`
  keeps a copy in `Documents/VoiceSamples/sample-<ms>.wav` — a NEW name per
  recording, because a blob is never edited — and reads the newest copy back
  when the phone has none or an older take. `VoiceRevival` fetches it from
  iCloud on demand (`SyncEngine.fetchVoiceSample`). It goes to the learner's
  own iCloud only; our server copy still lives 24 h.
- **A full iCloud is remembered, and SAID** (`SyncEngine.quotaFull`). The
  refused half (audio, or everything) is not retried for 6 h unless Sync now
  is tapped — it was retried on every write, once per turn of a live call —
  and `SyncQuotaNotice` tells the learner once, outside a call, that their
  recordings are on this device only and will go with the app. Me → Devices
  keeps the same words, and the size of this device's practice.
- **Nothing warns at deletion time — iOS gives an app no hook** — so it is
  said before: Me → Devices says "on this device only" while sync is off, and
  `BackupOfferSheet` asks once, after the third finished talk.
- Tests: `SyncTests` runs two engines over `InMemorySyncTransport` as two
  devices (`SyncFiles.documentsOverride`) — convergence, deletion cascade,
  conflict → next pass, no ping-pong, blobs as assets.

## Material on a situation, and the two doors into Watch (2026-09-25)

A job interview is the situation people prepare for most, and the composer
could take only a sentence about it — no posting, no CV, nothing the model
could read. Now a situation can carry MATERIAL (`ScenarioBrief`, on
`Scenario.brief`), and the Watch page splits its entry in two.

- **Two doors, side by side** (`WatchTab.newSituationSection`): **Your own
  situation** opens the composer's BOX (`ScenarioComposerSheet.Mode.custom`
  — one line, the material as chips above it, one tool row: attach · the
  other person · the CTA; no category grid anywhere) and **Common
  situations** opens the same composer on its category chain (`.browse`, the
  original Form). Both mint the same `Scenario`; only the start differs.
  The old "Likely situations" chip grid is gone from the page — those
  categories are the browse door's first screen. Editing a saved scenario
  always uses the Form, which now carries a **Material** section too.
- **The file is never copied.** `fileImporter` hands over a security-scoped
  URL; `ScenarioAttachmentReader` reads the bytes inside the scope, parks
  them in `BriefAttachmentCache` (memory only) and keeps a bookmark on the
  source for "Read again". Nothing lands in the sandbox, the sync payload or
  the usage ledger — the copy on the footer ("Files stay where they are on
  your phone") is literally true. PDF, images (re-encoded JPEG, EXIF
  dropped) and plain text, 10 MB in total; links are read by the model.
- **Read ONCE, before the first scene, with a board** (`SceneWatchView` →
  `ScenarioBriefEngine.read`, `BriefProgressView`). One streaming call on the
  default model, `purpose: "brief"` (cap 20/day, no learner charge); a link is
  fetched FROM THE PHONE first (`ScenarioLinkReader`, Safari's UA and
  Accept, one retry on LinkedIn's 999) and its text rides in the message —
  Gemini's `url_context` fetcher is refused by LinkedIn outright (measured
  2026-10-01, `URL_RETRIEVAL_STATUS_ERROR`), and search can't stand in for
  a fresh posting whose URL names only an id. Only a link the phone could
  not read goes through `url_context` + `google_search` with the fallback
  ladder (tools → search only → none); files ride inline via
  `Message.inlineFiles`. The
  schema's key order is load-bearing for the board (`sources` → `summary`
  → `counterpart_facts` → `likely_questions` → `learner_facts` →
  `key_expressions`). A failed reading is the scene's error state, never a
  scene quietly written without the material.
- **Two sides, kept apart, everywhere the brief is used.** `counterpartFacts`
  + `likelyQuestions` are the OTHER side and ride into the counterpart block
  (`ScenarioCurriculumEngine.userMessage`, `ConversationEngine`'s
  `briefBlock`); `learnerFacts` are the learner's and ride into the persona
  side ("follow up when THEY raise it, never quote it back"). Questions and
  expressions are MATERIAL (target language); summary, facts and source
  details are NOTES (native). `keyExpressions` lead the call's chip row
  (`TalkGoalPicker.pick(forScenario:)`). The book page shows the brief with
  its sources, read date and **Read again**.
- **A public figure is a RELATIONSHIP, not "Other"** (`RelationshipKind
  .publicFigure`), and since 2026-09-28 its whole profile is WHO it is: see
  "A person is a RELATIONSHIP" below. The voice is a PRESET — the stranger
  rule.
- **People have photos** (`CounterpartPhotoStore`, one square JPEG per id
  under `Documents/counterpart_photos/`, re-encoded so EXIF/location never
  survive; deleted with the person). Picked through `PersonPhotoButton`
  (library · camera · Files) on the intake's first card and on the form,
  and drawn by `PersonBubble(photoId:)` and `DialogueLine(avatar:)`, so the
  stories row, the scene's speaker label, the composer and the book cover
  show one face. Local only — not in the sync payload.

### The situation box, and what fills the space above it

- **One control strip, never two.** `SpeakOrTypeField` takes
  `leadingControls` / `trailingControls` so a host's own buttons sit INSIDE
  the field's row beside the mic. The box's first build stacked its own
  toolbar under the field's and the card carried two rows of chrome. The
  locale picker wears the same fill as the buttons next to it (bare, it read
  as loose text), stands down while recording, and `micStyle: .plain` keeps
  the mic from being a second filled accent shape beside a primary button.
- **The CTA is in the HEADER on both doors.** It sat in the box for a day;
  its glyph never aligned next to a mic circle, and its label was one more
  thing whose width moved with the language.
- **A box that sizes to its content resizes itself.** Every control in that
  row has an intrinsic width that changes — the person's name, the dictation
  language's endonym — so without `frame(maxWidth: .infinity)` the whole card
  grew and shrank as the learner picked. Same class of bug as the person
  chip, which framed a 40pt avatar into a 22pt slot: the frame cropped the
  slot, not the circle, so the disc drew through the pill's edge. Build the
  avatar at the size you want (`partnerAvatar(size:)`).
- **`SituationReel` fills the empty middle.** Examples roll slowly past the
  blank box: it answers "what do I even put here", and because every line is
  written at the length the field asks for, it demonstrates "the more detail,
  the better" far better than the sentence saying so. Touch FREEZES the roll
  and lifting picks the line the finger landed on (hit-tested against the
  offset held at touch-down, so the line that scrolled into its place can
  never be the one that lands); a drag picks nothing. Reduce Motion gets the
  same lines, still. It hides the moment there is text or focus.

## Find people (shared persona pool)

Watch's People row is your OWN people. The tab header's `person.2` opens the
ONE people page (`FindPeopleSheet`, titled People, 2026-08-31): your own
people (create, edit, delete — the old separate `PeopleSheet` is gone) on
top, and below them strangers you can practice with, like meeting someone at
a language school. Rows come from the Supabase table `public_personas`, read anonymously, written only by their owner (RLS).

- A row is either **curated** (`owner_user_id` null — seeded by migration, deliberately diverse in job/place/register) or a **real user's** self-introduction. Same pool, same shape; the pool self-mixes as users join.
- The user's own row is a MIRROR of their onboarding `UserPersona` (`PublicPersonaService.autoSyncMyPersona`) — but **nothing is published until they have seen the paragraph once** (2026-09-15, `PublicIntroPreviewSheet`, raised on the Watch tab via `needsIntroDecision`). Until then the profile was written for the fluent self, not for strangers, and it went out on first launch with "wife and 4yo daughter at Kita" in it and the author never saw the text. Three exits: **Publish** sets `autoApprovedKey` and the mirror follows profile edits from then on; **Edit first** lands in `PublicIntroView` seeded with the same paragraph (publishing there sets `manualIntroKey`, as before); **Not now** sets `manualIntroKey` and withdraws any row an older build put up unasked. While undecided, an existing unconsented row is rewritten to the current composition (`trimUnapprovedRow`) — never inserted, never left carrying the old lines. **The intro is a PORTRAIT written by `PublicIntroComposer`, never the notebook read out** (2026-09-25). Until then `composedIntro` was a concatenation — occupation, "city · stay", the situation chips comma-joined, then every unlocked remembered line in the order it was heard, uncapped — and the founder's own read "Gained a new app user from Hong Kong / 아이의 한글학교 등교를 위해 이동 중이었다": a memo pad, in two languages, introducing nobody. The concept is a person at a party: they know everything about their own life (the fluent self's own prompt still carries the whole notebook), they SAY what they'd tell a stranger, and the rest shapes what they have opinions about without being told in detail. So one `flash-lite` call (`purpose: "public-intro"`, free) writes 4–6 first-person sentences in the TARGET language from **occupation · city+stay · interests · situations · `strangerFacts`** — the stranger set narrowed to standing `fact` lines (a `now` line is news, not who you are; the live counterpart block keeps `strangerLines`), `.all` as written, `.gist` as its gist, `.nothing` absent, newest `maxFacts` — and is told to DESCRIBE (who they are; the AREAS their notes point to as subjects they can speak to from experience, "raising kids abroad", never the school run) and to drop single past events, dates, numbers, other people's names, duplicates. Deliberately NOT `household` or `freeNotes`. The paragraph is cached in `Documents/public_intro.json` under a SHA of every input + language + `promptVersion` (bump it to rewrite everyone's), so preview, profile page, mirror and editor seed show ONE text and the model is asked again only when an input changed; `composedIntro` (sync, `@MainActor`) returns the cached paragraph or the old deterministic fallback and never asks — it is the density gate's — while every screen that shows the text awaits `composeIntro` behind "Writing your introduction…" (`ComposedIntroText` / `ComposedIntroLoader`). What is private never leaves the phone, so a stranger's persona cannot leak it however it is prompted. Your own row is filtered out of your own pool.
- A remote persona materializes as a normal `Counterpart` with `remoteId` set (`asCounterpart`). `remoteId != nil` is what keeps strangers OUT of the Watch stories row and the People sheet — they live in the Find sheet's "People you've met" instead, so the row never crowds out people you actually know.
- **The pool section is named "Strangers" and shows EVERYONE unmet**
  (2026-08-31, was "People today", six a day on a daily seed): that they're
  strangers is the point — talking to strangers is what the language is for —
  and the rotation hid most of the pool to manufacture a return visit.
- **A stranger's VOICE is the learner's pick** (2026-08-31): the card carries
  a Voice row (`VoicePresetPickerView`) and the choice is saved onto the
  Counterpart (`voicePresetId`), which wins forever because `asCounterpart`
  returns the saved row over the pool's. Still never a clone — the footer
  says so out loud.
- **A preset voice id is a SLOT, voiced per target language** (2026-09-28). The four presets are American/British speakers and read Korean like one. What is stored (Counterpart, Scenario, persona row, StockPerson) stays the English id; `VoicePreset.speaking(_:in:)` swaps in the language's own voice at the network edge (`ElevenLabsClient`, the gateway `start`) and in `PhraseAudioStore`'s key. ko and ja use four native Korean library voices (founder's pick, added to the ElevenLabs account — a library voice must be in My Voices to synthesize); de and en keep the originals. Lines cached under the slot before this still play as the lookup's fallback (produced audio is never orphaned); previews and a call's opener pass `allowLineage: false` so they are always the voice speaking now. Every id must also be in BOTH server allowlists (gateway `PRESET_VOICE_IDS`, `elevenlabs-tts`), deployed before any build that resolves to it. A revoiced slot also takes a name from that language (`VoicePreset.localNames`: ko 시안·민준·한별·준호, ja 美咲·翔太·陽菜·健太) — `displayName` follows the target language, and a saved built-in person's row is renamed on read (`StockPerson.localized`, in `CounterpartStore.load` and on a language switch), since one row serves every language.
- **Talk** starts a normal `ConversationView` call with `initialCounterpart:`. Two things change and nothing else: `ConversationEngine`'s `YOUR CHARACTER` block casts the model AS that person (it outranks ROLE/SCENE inference and the future-self framing, and carries the same context-not-instructions + language guard as the Watch engines), and `activeVoiceId` uses the persona's **preset** voice. Their voice is never a clone — the person on the other end is a stranger, not the fluent self.
- The talk saves as an ordinary `Session` with `counterpartId`, so its review material, transcript and Practice book all come from the existing machinery for free. The person's card lists every talk you've had with them.
- Bookmarks are local only (`UserDefaults`). Nothing a learner does here reaches the persona's author: no notification, no shared record.

Intros are MATERIAL, so they're written in the target language — a persona row serves one `language` and the pool is fetched per `AppState.targetLanguage`. Publishing is gated on intro density (80 chars), not on a privacy toggle: a one-liner can't carry a conversation, and the same bar keeps thin rows out of the pool.

## A person is a RELATIONSHIP, and a call knows which kind (2026-09-28)

Reported by the founder: a friend in a call spoke like a polite stranger,
and BTS RM steered every call back to art museums. Both came from one place.
`ConversationEngine`'s character block was written for a Find-people
STRANGER — "new acquaintances with no shared history", open on something
concrete from your own life — and it was handed to everyone. It never
carried the relationship (Watch scenes did; the call didn't), so the STRICT
rule "under YOUR CHARACTER the relationship chooses the form of address" had
nothing to choose from, and it labelled the learner's note about their
shared history as the person's "self-introduction". For a public figure the
3–4 sentences of coverage WERE the person, so the model opened on the one
fact everyone knows every time. `isPublicFigure` was never read by a prompt
— and was never even SAVED: the hand-written `Counterpart.encode` dropped it
along with `publicIdentity` / `factsRefreshedAt` (fixed the same day).

- **A public figure is its IDENTITY, confirmed — nothing else is written
  down** (founder: "the model finds exactly who it is, the learner confirms,
  and the call runs on that"). The intake is name → "Public figure" → done;
  `CounterpartParser.identifyPublicFigure` (search-grounded, default model)
  returns one line ("BTS RM · rapper") or not-found, and the form shows it
  with **Look up again** and hides every descriptive field. The model already
  knows the person's work, manner and interests, so asking the learner for
  them is asking them to do the model's job — four different cards were
  tried and cut the same day (where you'd meet, what you'd say, which side
  you follow, what you'd talk about), each either shrinking the person to a
  scene or duplicating what the model knows. A search-written 3–4 sentence
  profile was the old design, and it WAS the museum bug: the one fact that
  stood out in it opened every call. Old rows keep those fields on disk; no
  prompt reads them for a public figure (call, scene, idea suggestions).
- **Three casts, three blocks** (`Counterpart.Cast`,
  `ConversationEngine+Character.swift`). `ownPerson` (made by the learner):
  they ALREADY KNOW each other, the note is shared history, no introductions,
  no interview, and a close one talks loose and quick; the model may invent
  ordinary detail of its own day but never a big event in the SHARED history,
  because the learner was there. `stranger` (the pool): the old block
  verbatim. `publicFigure`: the confirmed identity and the whole public
  record, told not to fall back on the most famous facts; public ground
  only, private questions deflected like an interview.
- **How the two TALK is its own card** (`SpeechRegister`: casual · polite ·
  formal, in BOTH directions, plus what each calls the other), right after
  the relationship chip in the intake and in the form. Abstract on purpose —
  a person is shared by every target language — and each language names the
  rung (반말/해요체/합니다체, タメ口/です・ます/敬語, du/Sie, tu/vous…);
  English reads it as tone. The intake prefills from the chip
  (`defaultRegisters`: friend/partner/family casual, everyone else polite) so
  it reads as a confirmation. Unset on an own person = the relationship
  decides (every person made before this); a stranger or public figure unset
  = polite. The call, the scene prompt (both sides — the learner's lines are
  the material) and the corrections all read it.
- **The one exception to "the speech level is the learner's"**
  (`relationshipRegisterLine`): if the learner SET how they speak to this
  person and a line comes out in another form, it may be corrected, with the
  relationship as the reason. It is appended only in that case and only for
  a language that marks address, so every other prompt is byte-identical to
  the measured one (`CounterpartCharacterTests` pins it). Not yet measured
  with `scripts/correction-probe.py` — do that before trusting it widely.
- **Someone close knows the learner's life** (`knowsMyLife`, default on for
  friend/partner/family): the whole notebook, private rungs included, framed
  as "you know this from being close to them". A stranger or public figure
  never gets past `strangerLines`, whatever the toggle says.
- Not built yet: per-person MEMORY across calls (the relationship ledger —
  what was talked about, what each said, open loops). Every call with the
  same person still starts without the previous one.

## Push notifications (2026-09-26)

The first thing this app can SAY to someone who isn't holding it. Every
notification before this was LOCAL — the phone scheduling its own reminders —
so the app could only ever tell a learner what it already knew when they last
had it open. Three things it could not say at all, and they are the reason
this exists: a seat in the Core opened, a trial ends tomorrow, and anything
the founder needs to tell everyone at once.

- **`push-send` is the only thing that holds the APNs key** (`supabase/functions/push-send`).
  It signs an ES256 provider token by hand over Web Crypto — the same shape
  `_shared/apple-jws.ts` verifies Apple's own JWS with, and for the same
  reason: no library here can do it. The token is cached in module scope for
  50 minutes, which sits between Apple's two walls (refused if refreshed
  inside 20 minutes, rejected past 60). `verify_jwt = false`; the caller
  proves itself with `PUSH_SECRET` in `X-Push-Secret`, and the function
  refuses everything when that env var is unset — a thing that writes to
  every learner's lock screen fails closed.
- **The HOST and the TOPIC are per TOKEN, never global.** A build signed
  `aps-environment: development` exists only on `api.sandbox.push.apple.com`
  and a shipped one only on `api.push.apple.com`; the dev bundle id is a
  different `apns-topic` from the shipped app's. Both are columns on
  `device_tokens` because the install is the only thing that knows them —
  and `PushTokens` reads the environment out of the embedded provisioning
  profile rather than `#if DEBUG`, because the Release scheme run from Xcode
  is a release build signed for development, which is exactly the
  configuration used to check prices on a real phone.
- **A push is CHROME, so it speaks the language the learner PICKED**, never
  the device's ("UI text has ONE language"). APNs' own `loc-key` would have
  been the obvious mechanism and is unusable for precisely that reason: it
  resolves against the app's localization by DEVICE language. So the install
  reports `app_language` and the sender is handed a `texts` map, picking by
  that column and falling back to `en`. A caller passing one language is
  saying "everyone, in these words", which is what a founder writing an
  announcement by hand means.
- **`push_sends` makes every sender idempotent**, because all of them run on
  a schedule and a schedule runs twice. The unique key is
  (user, kind, dedupe_key) and the row is claimed BEFORE the send, so a
  failure is not retried: a notification nobody can see twice is worth more
  than one that might arrive twice. It is a ledger, not a queue — nothing
  reads it to decide what to say next.
- **410 and BadDeviceToken are the ONLY things that delete a token.** An
  install that was deleted or reinstalled is reaped by Apple's own answer;
  nothing else prunes, and a signed-out device keeps its row (a shared iPad's
  other account may still want it).
- **Registering is not permission.** `PushTokens.register()` runs for every
  signed-in account and asks the learner nothing — a device token is not
  consent, and `UNUserNotificationCenter` is what decides whether anything is
  ever drawn. So a learner who has refused notifications still has a row,
  which is cheaper than having no way to reach them the day they change their
  mind. The consequence to remember: **Apple accepts and delivers a push to
  an unauthorized install and iOS silently discards it** — `sent: 1` with no
  failures and nothing on screen is the signature of missing permission, and
  an app that has never ASKED does not even appear in Settings → Notifications,
  so it cannot be granted by hand either. Today permission is only ever
  requested by the reminder flows (`ReviewNotifications`, `TrialReminder`,
  the daily call), which means a learner who enabled none of them can never
  be reached. That gap is open.
- **Sync must never unregister.** `SyncPush.deactivate` called
  `unregisterForRemoteNotifications()` until this shipped, which would have
  meant switching off an iCloud setting silently killed the Core's arrivals,
  billing notices and announcements. Sync's wakes stop because `handle` drops
  them when sync is off; that was always the real gate.
- **Announcements are `scripts/push-broadcast.sh`, and it is a DRY RUN by
  default.** The text is the founder's — the script never composes a
  sentence — and `--send` is what delivers it. A push cannot be recalled, so
  the flag is the whole point. `PUSH_SECRET` lives outside the repo.
- Deliberately NOT here: anything the phone can schedule itself. The daily
  call stays AlarmKit (it has to ring through silent mode, which no push can
  do) and review reminders stay local (the phone knows when a card is due; a
  push would be a round trip to say something already on the device).

## The daily call (habit anchor)

Nobody opens a language app because a streak asks them to; they answer a phone that rings. Korean 전화영어 runs on exactly that, and its biggest churn reason is the embarrassment of stumbling in front of a stranger — here the caller IS the learner, so only the schedule's pull is left. Opt-in in Me → Call (`DailyCallStore.isEnabled`, default 08:00).

**A third-party app cannot render an incoming-call SCREEN.** iOS gives that to CallKit alone, and CallKit needs a server-sent VoIP push for a real person-to-person call — Apple rejects it for anything else. This was tried and abandoned; don't re-litigate it. The "someone is calling me" feeling is therefore built from **behaviour, not chrome** — the caller has a memory, and an unanswered call leaves a trace.

- **What rings** (`DailyCallAlarm`, iOS 26.1+): an AlarmKit alert, because it's the only thing that rings **through silent mode and Focus** with its buttons visible without a long press. It is an alarm screen and will always look like one. Notification path is the fallback (older OS, alarms refused); `DailyCallScheduler.schedule` tries alarm first, `cancelPendingRequest` clears BOTH or the learner gets called twice.
- **The ring is a bundled phone tone** (`DailyCallStore.ringtoneFilename` → `Resources/ringtone.wav`, a synthesized two-tone warble in double-ring cadence). NOT the learner's voice, and not by choice: on iOS 26 a sound written at runtime — the only kind an app can put in `Library/Sounds` — is silently ignored by both AlarmKit and `UNNotificationSound`; only bundle resources play. A per-learner daily voicemail can never be a bundle resource. The voice arrives the instant they answer, which is what a phone call is anyway.
- **More than one call a day** — `DailyCallStore.times` is a list (max `maxTimes` = 4), edited in Me; the legacy `hour`/`minute` keys migrate into it on first read, and those properties now proxy the FIRST time (setting either collapses the list, so never wire a single-time picker to them). `DailyCallScheduler.fireDates` returns every remaining slot today, else tomorrow's first — and `schedule` arms **all of them at once**, each as its own alarm/notification carrying the same still-unheard message. Arming only the next one would be a no-op: the plan is written in the foreground, but the gap between a slept-through 08:00 and a 13:00 has the app closed with nothing running to schedule the second. Answering cancels the rest; the session that follows writes the next call fresh.
- **Onboarding introduces it** (`DailyCallOnboardingView`, gated in `RootView` on `futurevoice.dailyCall.onboarded`). Placed AFTER the voice clone — the call is the clone's first real job, so it reads as a promise rather than a permissions request. The flag is set on BOTH exits (enabled and skipped) or the screen becomes a wall. Existing installs see it once; that's how they learn the feature exists.
- **Button mapping is inverted on purpose.** `AlarmPresentation.Alert.stopButton` is deprecated in 26.1 (system-drawn, unlabelable), so **Answer is the SECONDARY button** — the only one we can label and give a phone glyph — and the system's button is Decline. `secondaryButtonBehavior` is `.custom`, NOT `.countdown`: countdown would oblige the app to ship a Live Activity widget for that state.
- **Every call settles into a `DailyCallOutcome`** (answered / declined / missed) and lands in `DailyCallStore.history()`. **Declining is just not taking the call** (2026-09-21, user decision): no callback, no "call back in…" choice, and the app does NOT open — `DeclineDailyCallIntent` runs with `openAppWhenRun = false` and the notification's single decline action is a background one. The old callback sheet asked a question every time the learner said no, which was the app nagging; don't bring a callback back. The learner's own later times today still ring (they chose them), so a decline settles the plan as `.declined` only once no slot is left today; until then `callbackCount` (name kept for decoding) counts declines, and a plan that then rings out settles as `.declined`, not `.missed`. An untouched call is settled as `.missed` on the next launch (`settleIfRangOut`, after `rangOutGrace`) — it can't be noticed at the time because nothing is running.
- **That history is what the NEXT script is written from** (`VoicemailEngine.Context.lastOutcome` / `consecutiveUnanswered`). This is the feature, not a nicety: an alarm knows nothing about you; a caller who opens with "couldn't talk yesterday?" reads as a person. Never make it scold — guilt is what makes people stop picking up.
- **The missed-call row on the Talk tab was REMOVED 2026-09-02** (user decision) — a missed call no longer leaves a visible trace on the home. The store machinery survives untouched (`DailyCallStore.unheardVoicemail`, `keepUnheard`/`clearUnheard`, `DailyCallScheduler.markVoicemailHeard`) because the record is a single row overwritten by the next miss, and restoring the row is a UI-only change. If it ever comes back, the old rules still hold: read `unheardVoicemail`, never the plan (`refresh` overwrites the plan with the NEXT call moments after settling), and `markVoicemailHeard` must never stamp `heardAt` on the plan, which by then is the next call.
- **The voicemail is synthesized at generation time**, saved into `PhraseAudioStore` under its own (script, voiceId). `VoicemailEngine` writes a 2–3 sentence script (`flash-lite`) grounded in the last talk's topic and phrases, **always ending in a question** — an unanswered question is the whole pull. Target language: it's material. `synthesizeRingtone` takes the STREAMING TTS path purely for its **raw PCM** output — `UNNotificationSound` only plays Linear PCM / µLaw / aLaw in .wav/.caf/.aiff, never MP3 — levels it through `AudioLoudness.gain(forSpeechRMS:)`, and writes it under `Library/Sounds/` with a **never-reused filename** (iOS caches notification sounds by name). Hard 30s OS ceiling, enforced twice: `maxScriptCharacters` and `VoicemailEngine.trim`.
- **Generation happens at SESSION END, never in the morning** (`SessionSummarizer` → `AppState.refreshDailyCall(force: true)`). iOS won't reliably run background work at a chosen hour, and a call that fails to generate is a call that never rings. By 8am the script and audio are on disk, so the ring works offline. The `scenePhase == .active` re-arm is only a safety net (reinstall, missed fire, language switch) and is a no-op when a usable plan exists.
- **One synthesis, two uses.** The ringtone WAV is saved into `PhraseAudioStore` under the same (script, voiceId), so answering opens `ConversationView(initialOpener:)` and that cache hit IS the call's first spoken line — no second TTS, no round trip, and the voice never changes across the hand-off.
- **A live call holds every ring** (2026-09-28, `DailyCallScheduler.holdForLiveCall` / `releaseAfterLiveCall`, bracketed beside `CallNowPlaying` in `ConversationView`). An AlarmKit alert takes the audio session, so a scheduled call landing mid-talk killed the talk with an error. While a call is live the pending rings are cancelled and `schedule` refuses to arm; on hang-up they are re-armed from the stored plan, and a slot that came due DURING the call settles the plan as answered (they were talking to that same person). The hold is in memory, so a killed app re-arms on its next launch.
- **A decline is not a failure.** No scold, no broken counter, and `PracticeStats`' streak is untouched by a declined or missed call; tomorrow's is written as usual.
- Tapping is handled by `DailyCallNotificationDelegate` (installed from `AppDelegate` — the delegate MUST be set before launch finishes or a lock-screen answer is lost), which posts to `DailyCallInbox.shared`; `RootTabView` presents the call from there.
- `interruptionLevel = .timeSensitive` is set but inert until the Time Sensitive capability is added to the App ID — harmless without the entitlement, no signing change needed today.

## The Core (100 seats, per language)

**One club PER TARGET LANGUAGE** (`20260816120000_core_by_language`) —
`core_membership` is keyed `(user_id, language)`, settlement loops over
languages, and every client read names its club. A seat is a claim about
keeping ONE language up, so it can't follow you when you switch; Find people is
already per language, so a cross-language seal was appearing beside names it
said nothing about. A learner with two target languages earns a seat in each,
separately.

The Core's activity comes from its OWN ledger, `talk_seconds_by_language`,
written by `charge_talk_seconds(p_language)` — not from `tts_char_pool`.
Billing's per-day pool is keyed `(user_id, day, action)` and widening it would
put metering on the critical path of a feature that grants nothing. **`p_language`
is optional**: a build that doesn't send it bills exactly as before and counts
toward no club, which is right — a client that can't say what was spoken must
not be guessed at. `TalkMeter` reads it from defaults rather than taking it as
a parameter, because the meter is started from several surfaces.

A 100-seat club of learners who actually speak most days. It exists to build
and KEEP a core, not to run a contest — so membership is a BAR, never a rank,
and its two halves are deliberately asymmetric (`20260813120000_core_club`):

- **Qualifying** — **30 days IN A ROW** over the daily bar
  (`20260817140000_core_streak_entry`). Break it and the count restarts at
  zero; there is no forgiveness on the way in, and that is the entire value of
  it. Once, hard, and the QUALIFICATION is permanent: `qualified_at` +
  `join_number` are never revoked, which is what fixes your place in the queue
  and lets you re-enter on the keep bar. A low join number IS the founding
  story, which is why there is no separate "founding" flag and no sealing date.
  Permanent qualification is not a permanent badge — see below.
- **Qualifying does NOT seat you.** It puts you in the queue, in qualification
  order; you are seated when a holder vacates. `core_my_progress.queue_ahead`
  exists so the screen can say that out loud instead of letting a progress
  number read as a door.
- **Keeping a seat** — don't break the streak, except **one missed day per
  rolling 30 is forgiven** (`keep_grace_days`). A cold or a flight is free; two
  inside a month vacates the seat, and with it the badge. **A seat is only
  ever vacated by its holder, never taken by a newcomer** — `settle_core_club`
  releases before it promotes, so an arrival is pure good news to the people
  already inside. If qualified people pile up waiting, the answer is to loosen
  the keep bar, not to evict anyone.
- **Re-entry** — within 90 days of leaving you return on the KEEP bar, not the
  streak; the full 30 in a row is asked of first-timers only.

**This replaced 28-of-30 rolling windows on 2026-08-17, and the old argument is
worth knowing before re-deriving it.** Rolling windows were chosen so a missed
day would defer entry by a day instead of resetting to zero — humane, and true.
But it was humane only in the arithmetic, where nobody could see it: what
reached the screen was "Days met 3 / 28" over thirty dots, which is a scoreboard
of a month already spent and says nothing about what to do today. It also could
not state its own rule — nothing in a field of dots tells you which two absences
were forgiven. A streak is a rule people already hold in their heads, and its
instruction is the product's instruction: talk today. The humaneness moved to
the KEEP side, where it is one sentence anyone can repeat.

The two measurements live in `core_streak()` / `core_missed_recent()` and are
called by BOTH the nightly settlement and `core_my_progress`, so the number on
screen is the number the promotion decision was made from — never re-implement
either in a query. The streak is anchored to today if today is already met,
otherwise to yesterday: a streak is alive until its day is over, and without
that every learner reads 0 each morning and the 00:05 UTC settlement sees
nobody qualified at all. The UI shows numbers only — no grid; don't bring one
back to "show progress", the progress is the number.

**The Home streak is NOT the Core's streak** (2026-09-19, user decision). From
2026-08 to this date they were one rule (Core bar, active language, metered
talk only), so the two numbers couldn't disagree — and on Home that rule read
as a punishment: a day of reviews, shadowing and a scene, or a day in the other
language, reset it to 0. Now `PracticeStats.activeDays` is the whole
definition: metered talk in ANY language, a talk the learner spoke in, or any
`PracticeLog` rep (cards, words, phrases, shadow takes, and Watch scenes via
`sceneReps`, logged on a scene's first heard line). Opening the app is not
enough — `AppUsageLog` is deliberately left out. Home, the widget
(`metToday` = `PracticeStats.studied()`), the day card and the Activity
calendar all read it; the calendar's lit run IS the streak. The Core keeps
its hard bar and its own server-computed number on its own page — don't
re-merge them, and don't harden the Home one back toward the bar. No grace day
yet; add one here, not in the Core.

- **The badge IS the seat** (`CoreSeal`, 2026-08-18): one glyph, `seal.fill`,
  drawn only for a member seated right now. It used to have a second state —
  outlined `seal` for qualified-but-seatless, so the thirty days could never be
  taken away — and that was wrong about the badge even while being right about
  the record. The seal's only audience is a stranger scrolling Find people,
  where a row has no space for a legend and two fills can't be told apart; a
  badge that needs explaining which of two things it means isn't one. Filtered
  server-side too (`20260818130000_core_badge_is_the_seat`) so builds already
  shipped stop drawing the outline. Losing a seat is still dormancy rather than
  a scar — it just isn't worn. **`Color.coreClub` (systemIndigo) is reserved —
  nothing else in the app may use indigo.** The UI rules allow only system
  colours, so scarcity of the colour IS the badge.
- **The badge's real home is `FindPeopleSheet`** — the one place a learner is
  seen by a stranger. A stranger sees the seal and nothing else: no number, no
  rank, no talk time. Rank decides who gets in; inside the club everyone is
  equal.
- **The Core grants NOTHING** (`20260816100000_core_grants_nothing`). It used
  to add `bonus_seconds` to the day's talk cap; that was near-worthless to the
  tier most likely to qualify (against Unlimited's 3600 s/day it was under 7%)
  and it made a record of persistence look like a loyalty discount. There is
  no payout, no unlock, no priority. The club is a standing and a record —
  honour, and a promise kept to yourself. **Do not add a perk**; the absence is
  the design, and it is why the Core no longer touches billing at all.
- **Only talking counts.** `core_daily_activity` reads `talk_seconds` alone;
  Watch scenes (`scene_seconds` / `scene_counted`) can never move anyone
  toward a seat. Upgrade path: point that view at per-turn utterance seconds
  once the client reports them — wall-clock is farmable, speech is not.
- **Settlement is a daily UTC job** (`settle_core_club`, pg_cron 00:05) and is
  idempotent per day via `core_settlement_log`. Everything the client sees
  comes from `core_my_progress()`; `core_daily_activity` is REVOKED from
  clients because it would expose everyone's talk time.
- **Arrivals are public, departures are NOT** — the `core_events` read policy
  filters `kind = 'left'`, so nobody can work out whose seat they took.
  `CoreClubService.announceArrivals()` still polls on foreground and posts a
  quiet LOCAL notification (no sound; the daily call is
  the habit anchor and must not be competed with).

The bar (`core_club_config.daily_bar_seconds`, 240 s since
`20260814110000`) is tunable without a migration, but it must stay BELOW the
Daily tier's `daily_seconds` — at the cap there is no slack, and a call that
ends at 4 min 52 s would fail the day. It is currently derived from the plan's
shape, not from behaviour: `TalkMeter` only shipped 2026-08-11, so almost no
account emits `talk_seconds` yet. Re-derive it once real days exist.

## The first call, and the memory it leaves (2026-08-19)

Everything the fluent self knew about the learner used to come off a setup
form, which is not how anyone learns about a person — so the FIRST plain free
talk is spent meeting them, and what it hears is written down.

- **`UserPersona.metAt == nil` is "we haven't met."** While it is nil, a free
  talk opens on `FreeTalkOpeners.introOpener` (bundled per language, so the
  first greeting of all never waits on Gemini, and it outranks both the
  rotating pool and the fallback) and the conversation prompt carries
  `ConversationEngine`'s **FIRST CALL** block.
- **The fluent self introduces ITSELF first** — the opener says who it is
  (them, a few years on) before it asks anything. A line that opens with
  "tell me about yourself" is an interview, and this one isn't even a
  stranger: it's the learner's own cloned voice, which needs explaining
  before it needs answering. That order is then the call's rule — GIVE, then
  ASK: every question is followed, once they've answered, by the fluent
  self's own version of it.
- **It must not invent the learner's life to do that.** It IS them, so a
  fabricated job or city is a claim about the user, and the next thing they
  say will contradict it. The prompt allows exactly one unprompted
  self-disclosure: what being the fluent version of them is like. Everything
  else it says about "itself" has to come after they've said it first.
- **The call is meeting a person, NOT completing a record.** The block used to
  hand the model a seven-item list (their work, their people, their interests,
  where they're from…) and told it to "stop collecting" once it had enough —
  which is an intake form, and reads as one right after an opener that just
  promised to do this together. It now says the opposite: no list, no order,
  follow whatever they actually said, and a first call that ends with ONE
  thing you both enjoyed talking about beat one that got through their
  biography. The memory still fills — `about_user` reads the transcript, never
  a checklist, so it never needed the list. It explicitly suspends "never quiz
  them about their own profile" and "don't always end with a question", which
  otherwise win by volume, and holds one question per turn.
- **Free talk only, and it is not "the first talk ever."** A scenario casts
  the model as the barista and a Find-people call as a stranger; neither can
  run an introduction without breaking what it was launched as (the counterpart
  block bans that shape by name). So `firstMeeting` is gated on
  `topic.isEmpty && counterpart == nil` in BOTH `ConversationView` and the
  engine — someone whose first tap was a news story gets properly introduced
  on their first free talk instead. `metAt` is stamped when such a talk is
  SUMMARIZED, so a call that was opened and abandoned has met nobody.
- **`UserPersona.learnedNotes` is the fluent self's half of the profile.** The
  summary call returns `about_user` — 0-3 durable facts about the person's
  LIFE, native language, ≤ 12 words, only what they actually said — and
  `SessionSummarizer` folds them in via `AppState.rememberAboutUser`. It comes
  back through `personaBlock` on every later call, which is the whole point:
  you tell your future self about your job once, out loud, and it knows next
  week. `absorb` dedupes on a punctuation-stripped key (the model re-tells the
  same fact differently every session) and keeps the newest 40.
- **`about_user` is the LAST field in the summary schema, deliberately.** The
  order above it is load-bearing for `SessionSummarizer.Progress.absorb`;
  appending is safe, inserting is not. Being last also means a response cut off
  at the token ceiling loses this and nothing else.
- **Every remembered line is a STANDING TRUTH with its evidence under it, and carries a three-way lock** (2026-09-16; the two-way `isPrivate` lock dated from 2026-09-15). Reported from the founder's own notebook: "dropped the kids off at kindergarten this morning" sat there as a line, and what does anyone learn from that? The prompt's blanket "never infer" had made the model file the EPISODE instead of what it teaches. The rule is now one step of distillation — from what they said to what it plainly means about their life, never from HOW they speak — and an episode with no standing truth in it is no line at all. `about_user` comes back as `{text, heard, kind, share, gist, why, replaces}`: `text` is the fact ("two kids, kindergarten age"), `heard` the sentence it came from in their words (shown under the line in Me → Profile as "You said …"), and `share` is how much a STRANGER gets — `nothing` · `gist` · `all`. The middle rung is the point: in real life the details of a story are private while its shape is not, so the model writes `gist` beside the fact ("a parent of young kids", "looking for a new job") and a `.gist` line hands out that and nothing else; a line with no honest gist (health, money, someone else's private life) can only be nothing or all. The model SORTS at write time — the rubric is in the prompt, it must give a one-clause `why` the learner reads beside the pick, and it is shown the learner's last hand moves (`UserPersona.shareCorrections`, recorded on profile save) so it sorts the way this person draws the line. `nothing` is the FALLBACK, not the default: old string shape, missing key, a note on disk from before the field, and — since 2026-09-25 — BOTH values of the 2026-09-15 two-way `isPrivate` lock land there (an "unlocked" line from that day was written as an episode by that day's prompt, carried no gist and no reason, and went out in full in every intro; the learner reopens it in Me → Profile after reading it); `isPrivate` is never written back (a pre-2026-09-16 build would read a gist line as unlocked and put the whole line in the intro). Every line still rides into the fluent self's own prompt whatever the rung — that is what the notebook is for — but `UserPersona.strangerLines` is the ONLY set any stranger-facing surface may read: the public intro (through `strangerFacts`, its `fact`-only subset — see Find people), and since the same day a cast counterpart's prompt too (`personaBlock(forStranger:)` — until then a Find-people stranger was handed the whole notebook, private lines included). The profile page shows two lists by `kind` ("What I know about you" / "Right now", the latter with "fades in N weeks"), a "Strangers hear:" line per row, the rung on the trailing button and in the long-press menu (with "Show the talk" and "That's over now"), and the composed intro live at the bottom so a moved rung is visible on the same screen.
- **The notebook has a sense of time** (2026-09-15). Reported: "planning a
  trip to Seoul" sat on file for weeks after the trip, beside a newer "back
  and jet-lagged", and the fluent self asked about the packing. Three things,
  all in one pass: every line is DATED in both prompts (`ConversationEngine.age`,
  coarse — "3 weeks ago"); each line has a `PersonaNote.Kind` — `fact` never
  expires, `now` (a trip, a deadline, a cold) is shown as recent news under
  the durable lines and is dropped a month after it was heard
  (`isExpired`, pruned in `absorb`, filtered by `currentNotes`, which every
  reader goes through); and the summary call can UPDATE a line — the on-file
  notes go to it numbered, and an `about_user` entry carrying `replaces: n`
  swaps line n for the new truth (`UserPersona.NoteUpdate`). The talk prompt
  says the rule out loud: a later line wins, a plan whose date has passed is
  something that happened. `SessionSummarizer` snapshots the numbered list
  once at prompt time and maps `replaces` onto ids — never re-read the
  persona after the call. Lines are editable in Me → Profile, with their date.
- **`rememberAboutUser` is not `savePersona`** — it must not wipe topic
  suggestions or re-sync the public intro on every talk end, and these lines
  must never reach the Find-people pool: `composedIntro` reads only fields the
  user typed, and something said to your own future self was not said to
  strangers. The learner sees the notes in Me → Profile and can swipe any of
  them away; a memory that can't be corrected is a liability.
- **`UserPersona` decodes leniently** (custom `init(from:)`, in an extension so
  the memberwise init survives). A missing key here means `PersonaStore.load()`
  returns nil, which walks an existing user back into onboarding — every
  persona already on a phone predates these two fields.
- `PersonaDeepenSheet`'s auto-prompt stands down once notes exist: the call
  just asked those three questions out loud, and a form re-asking them reads as
  the app not having listened.

## The prompts have a clock (2026-09-28)

Reported by a learner as three symptoms: "long time no see" on a second call
the same day, "this afternoon" at eight in the morning, "our third call" on
the first call of the day. One cause: no conversation prompt carried a date,
a time or a talk history (only `ScenarioBriefEngine` said what day it was),
while the KNOWLEDGE block tells the model never to say it doesn't know — so
it guessed, confidently. `PromptClock` (`Services/PromptClock.swift`) is the
fix and the one implementation; the call-header `TalkClock` in `TalkMeter` is
a different thing.

- **The call prompt carries WHEN THIS IS**: the day, the start time and its
  part of the day, talks earlier today (with how long ago the latest ended),
  the last talk before today, and — on Continue — how long the resumed talk
  was paused, since its old lines otherwise read as said a moment ago. It is
  PINNED once per call (`ConversationView.pinPromptClock`, onAppear and
  `startNewSession`): the prompt is rebuilt every turn and handed to the
  gateway once, and both must describe the same call. Talks are counted
  across every language, only if the learner spoke, dated by their last line.
  The history is left out for a cast stranger and for the first meeting (their
  own blocks define the relationship); a scene character is told the history
  isn't theirs. The guard: anything about time not written there, the model
  does not know.
- **Every day count is a CALENDAR count** (`PromptClock.calendarDays`).
  `ConversationEngine.age` and the voicemail's day count divided elapsed
  seconds by 86,400, so a line heard at 23:00 was "today" at 08:00. Never
  compute a prompt's "yesterday" any other way.
- **The voicemail is dated to its RING, not its writing.** It is written at
  a talk's end and heard at the next ring, usually the next morning, so it
  takes `lastTalkAt` + `ringDates` and measures to the ring. With several
  times armed it may name no time of day.
- **The summary is told the talk's date** (the talk's, not the summary's, as
  a rescued summary runs days later), and `about_user` writes relative times
  as dates ("interview on Thu 1 Oct"); "next week" read a month later points
  at the wrong week.
- **Lines that are REUSED must be timeless**: the scenario opener pool (saved
  on the scenario) and the free-talk pool are told so, and the bundled
  fallback opener no longer asks "how was your day". Pools already on phones
  were left alone rather than regenerated.
- Tests: `PromptClockTests`.

## The day card — today's share card (2026-08-28)

A running app hands you a card the moment the run is saved: a map over a
photo, then the numbers. Here the card is the DAY's, not a talk's
(`DayCardView` / `DayCardSheet`): a first cut was a per-talk book cover with
a picked expression, and it was retired the same day — a talk is too small a
unit to share, and a picker made a moment into a form. Its home is the
**Activity page and only there** — the day summary's Share-card button and
the Cards view; that summary already says what the day was, and the card is
the summary as a picture (`DayCardData.make(day:)`, photo stored per day).
A post-talk button on the book page was tried and removed the same week: the
wrap-up flow is the book's, and a share offer inside it read as an
interruption. `-capture daycard` renders it on a sample day.

- **Topics, a row of numbers, the date, the URL — and it is in ENGLISH
  whatever the app language.** The card is for a feed, not for the learner;
  it has to read the same to everyone it reaches, so it is the one surface
  where chrome does not follow the learner's choice (locale pinned on the
  view, `Talk`/`Study`/`Streak`/`Talks`/`Reviews`/`Shadow` marked
  `shouldTranslate: false`). The numbers row is talk and study minutes
  always, then the streak as of that day (`PracticeStats.streakDays(asOf:)`),
  talks, drill reviews and shadow takes — whatever is non-zero, up to four. The headline is ONE topic —
  the day's main talk (`displayTitle` of the session the learner spoke
  longest in); a stack of titles was shipped and pulled after one real day,
  because news-talk titles are sentences and four of them buried the photo.
  The other talks are the TALKS number; the full list stays in the frozen
  snapshot. Talk minutes are `TalkTimeLog` — the ring's number, metered.
  Study minutes are `AppUsageLog`, foreground seconds per local day written at
  the edges of a stint in `FutureVoiceApp`, never less than the talk figure
  (a call in a pocket is metered but not foregrounded). Both are FLOORED,
  like the home ring and the widget. Nothing is computed for the card alone —
  and nothing else may compute a day's talk time either: summing the
  learner's own turn durations is a DIFFERENT quantity (a call is mostly the
  fluent self talking and the learner thinking), which is why
  `PracticeStats.todayTalkSeconds` settled on the meter. Activity and
  Progress's effort bars were still on that old sum until 2026-09-01, so the
  same afternoon read 11 min on the ring, 8 in Activity and 7 on the card;
  both now read `TalkTimeLog`, and Progress's goal RuleMark finally measures
  the same thing the goal is judged by. `Session.turns` speech sums survive
  only where the learner's own speech IS the subject — ranking the day's main
  talk, the CEFR estimate's ~10-minute gate, and the per-talk fluency stats.
- **The headline is the learner's to settle, and reads across every
  language** (2026-09-07). The automatic pick — the talk spoken longest in —
  was re-read live on every look, so a card shared at noon changed its face
  when a second talk outran the first; and `DayCardData.make` read only the
  ACTIVE language's sessions while the minutes it printed were every
  language's, so a free talk in one language and a news talk in the other
  left the numbers of two talks under the title of none. Three rules now:
  `make` reads `SessionStore.loadAcrossLanguages()` (a day is the learner's,
  not a language's); a talk whose summary never landed — `displayTitle`'s
  quoted first words or "Conversation" — sorts BEHIND every titled talk, so
  it heads the card only when nothing titled exists; and the sheet's
  **Headline** section lists the day's talks to pick from with a field to
  write your own (`DayCardStore.setHeadline`, per local day, empty = back to
  automatic). Picking a photo pins the automatic headline the same way, since
  the card is about to be shared. The pin rides in `DayCardData.headline`
  (optional, so old snapshots decode) and is frozen with the day. A typed
  headline is MATERIAL — the footer asks for the language being learned —
  which is the one thing on this English-chrome card that follows the talk.
- **The call pill is the card's brand badge, in the learner's theme.** A
  first cut laid the Futureself mosaic on a time axis as the day's "map" (lit
  where the fluent self spoke); it was retired the same day because nobody
  could tell what it meant. A full-size pill beside the numbers followed and
  was shrunk the same day: it now sits in the footer as an 88×32 capsule of
  `FutureselfPixels` (6.4 pt cell, five rows, hairline rim, low drive + steep
  colour falloff so most cells stay dark) with the DATE inside — no mark, no
  wordmark; the name is the footer's `nawana.app` under the tagline "Learn a language
  from your fluent self." and nothing else — the thing the learner talked to, wearing the name —
  in `futureselfTheme`, read from defaults because an `ImageRenderer` has no
  environment; dark palette, since the card's ground is ink whatever the
  phone's mode. A
  Futureself circle beside it was also tried and dropped. No Core seal: the
  badge's audience is a stranger in Find people, and a card leaving the app
  is a different audience nobody has decided on.
- **The collection lives INSIDE the calendar, not beside it.** A separate
  Cards view was built and folded back the same week: a second grid of the
  same days was a parallel calendar. Instead, the month calendar is a
  PHOTO WALL — every day is a full-width rounded square tile (`dayCell`), a
  photo day shows its photo, an active day its heat blue, an empty day a
  faint fill — so the month reads as the places you studied (circles showed
  a photo as a smudge), and selecting a day puts that day's card at the
  top of its summary (`cardPreviewRow`, tap → the same `DayCardSheet`).
- **A card is FROZEN once its day is OVER, never while it is running**
  (`DayCardStore.freeze` / `freezePastDays`, JSON beside the photo). The logs
  a card is drawn from are pruned at 45 days and the streak rule can change;
  a card read live months later would lose its minutes or change its streak,
  and a card is what that day WAS. `DayCardData.resolve` prefers the snapshot
  and falls back to the logs for a day that has none (only ever within the
  45-day window). **TODAY is always read live** — `resolve` ignores any
  snapshot for it and `freeze` refuses to write one, so the rule cannot be
  broken from a call site. It was, for three days: the sheet froze the day
  from `renderForShare`, which runs on every OPEN, so a card looked at in the
  morning stopped there and read 7 min beside a home ring reading 11. Nothing
  the snapshot protects against — pruning, a changed streak rule — can reach
  today, so there was never anything to buy. `freezePastDays` re-settles a
  past day whose record was written before that day ended (file modification
  date), which is what repairs the snapshots those three days left behind; it
  never replaces a record with a SMALLER `talkMinutes`, since a re-settle
  reads logs that may since have been pruned.
- **The photo is the place, and that is as precise as it gets.** No location
  permission, ever — the learner photographs where they are (`CameraPicker`,
  the one UIKit wrap, because `PhotosPicker` has no camera and "take it now"
  is the point), and `DayCardStore` (one JPEG per local day) re-encodes on
  save, which drops EXIF/GPS. Opening the sheet stores nothing; only a picked
  photo does.
- It is an exported PICTURE, not chrome, so it wears the brand (ink, paper,
  the mosaic's blue, Geist Pixel with the Galmuri cascade) rather than
  system colours; `DayCardView.render` pins locale and Dynamic Type because
  an `ImageRenderer` has no ancestor to inherit them from. Feed 4:5 (1080×1350,
  Instagram's tall frame, which Threads takes as is — a 9:16 story was the
  first cut and read as a poster, not a card) and square (1080×1080) are the
  same view at two sizes.

## Say it again (다시 말하기) — the whole talk, done again the right way (2026-09-27)

The third door on a talk book, and the only one that puts the learner back
INSIDE the call. Replay plays the conversation at them; Continue starts a new
one; **Say it again re-runs the SAME conversation, the whole of it, with them in
it** — their
corrected line comes up on a prompter, they read it out loud, the fluent
self's stored answer plays, the next line comes up. The founder's own framing:
실전 쉐도잉 — shadowing in the shape of the call it came from, rather than one
line at a time in a drill screen. `SayItAgainScript` (pure, tested) +
`SayItAgainView`.

**It is the whole conversation, not the corrections** — say that before
anything else about it, because it is the misreading the feature invites.
Every one of the learner's turns comes up, in order, between the answers they
actually got; a turn that was corrected comes up corrected, a turn that
wasn't comes up as said. The practice is saying the conversation the way it
SHOULD have gone. **Named "Say it again" / 다시 말하기 by the founder the same
day**, replacing "Teleprompter": that named the screen's mechanics (a line to
read) and not what the learner does, and it read as "a list of fixed lines";
beside Replay (다시 듣기) the pair says listen-again / speak-again.

- **What they read, in order of preference** (`SayItAgainScript.build`): the
  turn's OWN correction (`Turn.suggestion.alternative` — a whole sentence,
  rewritten); else the summary's phrase fixes SPLICED back where they were
  said (`phrasesUsed.userSaid` is a verified quote from that turn, so the fix
  goes into the line and the rest of the sentence stands); else **what they
  said**. That last case is the one that keeps this a CONVERSATION instead of
  a list of fixes (user decision) — a turn nobody corrected is a turn they got
  right, and it is still their line to say. A turn flagged misheard is dropped
  outright: its transcript is the recognizer's mistake, and a prompter showing
  it would ask them to say something they never said. The fluent self's answer
  to it stays — it is still what happened next.
- **Only a line that IS material becomes an attempt on file.** A turn
  correction carries `TalkCurriculum.correctionId(for:)`, so a passing read
  masters the book's Drill chapter exactly as a shadow take on that line does.
  A spliced summary fix carries none — that curriculum item is minted with a
  fresh UUID on every `build`, so no `ShadowAttempt` could ever be matched to
  it (its drill card is the only thing that masters it) — and an uncorrected
  line carries none either. Both are still SCORED, still counted (one take,
  one `PracticeLog` rep — the unit `ShadowDrillView` counts) and their WAV is
  deleted rather than left in Documents under a filename nothing references.
- **`rhythmScore` is nil by construction.** Nobody ever spoke a correction, so
  there is no beat to be measured against; `ShadowAttempt.overallScore` falls
  back to the match score on its own. This is why the mode needs no target
  audio and no synthesis for the learner's own lines.
- **Nothing is synthesized and nothing is metered, so there is no
  `BillingGate`.** Every fluent-self line is the audio that call already
  produced (`TurnAudioStore`, never re-synthesized — the same rule Replay
  holds), and the only network call is the free audio-grounded read of a take
  (`purpose: "transcribe"`, 0 credits, capped 800/day). A learner whose month
  is spent can run this all day, which is the "Shadowing · replays —
  Unlimited" the paywall card already promises.
- **The score walks through the one door and the coach never runs.**
  `ShadowTranscriber` reads the take, `ShadowEngine` grades it — and a run is
  twenty lines, so a bullet per line would be twenty Gemini calls for text
  nobody reads mid-run. The full drill, coach and all, stays one tap away from
  the book. The grading is handed to a task of its own so the fluent self
  answers immediately: **the conversation's own pause is where the scoring
  goes.** A retry cancels the score task it replaced, and `score` re-checks
  `Task.isCancelled` after the read — otherwise the old take's number lands on
  the new one.
- **It never stops** (user decision). A weak read is scored, shown and left
  behind; every read line keeps a **Retry** button for as long as the screen is
  open, and a score under `PracticeStats.retryThreshold` prints what the mic
  actually heard beside it — which words drifted is the only actionable half
  of a low number. Mid-run a retry rejoins the script there (the answer after
  it plays again, which IS the conversation); on the finished screen it is a
  single take and the page stays where it is.
- **No countdown, and "quiet" is the shadow surface's 1.5 s.** The mic opens
  with the line and the take ends when they go quiet — but the earliest it may
  end is measured from their FIRST WORD, not from the mic opening, because
  reading a line you have never seen takes a beat (`ShadowDrillView` measures
  from the go beat, which its 3-2-1 makes the same moment). Silence for
  `firstVoiceSeconds` (8) moves the conversation along rather than holding it:
  a silent take is `heardNothing`, which is not a 0 and is never saved.
- **A run is ONE analytics event, not twenty.** `AudioPlayer` skips
  `audio_played` for `unreportedPlaybackSources` — the live call's per-turn
  auto-play and now a say-it-again run, which reports itself once as
  `say_again_run` (lines, read, average) when it finishes. A line-per-event
  run is the same mistake `sync_push` was cut back for on 2026-09-26.
- **Watch books have the same door** (2026-09-27, `ScenarioDetailView`, a
  row under Talk · Watch). A scene is run with the learner reading its
  "user" lines — the fluent self's side, which IS the book's Shadow chapter
  (`ScenarioCurriculumEngine` extracts it that way) — between the
  counterpart's lines. Nothing is marked as a fix (a scene was written
  fluent), and each line carries its Shadow item's id, matched by normalized
  text the way `WatchView`'s "Shadow this" is, so a passing read masters the
  chapter through `refreshScenarioMastery` (run on the cover's dismiss).
  **The counterpart's lines come only from the audio cache**, under the key
  `WatchView` wrote them with (text + the counterpart's preset voice): a
  scene is claimed by COUNT (`begin_scene_play`), so synthesizing a line here
  would be the one metered act on a screen with no gate; a miss is read, not
  made. `SayItAgainView.Source` (`.talk` / `.scene`) is the only thing that
  knows which it is running — title, other side's name and photo, steps,
  and where the other side's audio lives; `say_again_run` carries `kind`.
- The screen is the app's ONE dialogue surface above (`DialogueLine`, bottom
  anchored) and the prompter below (`fadingBottomBar`) — the current line lives
  on the prompter and nowhere else until it is read. Captures:
  `-capture say-again` / `say-again-reading` / `say-again-done`
  (and `say-again-scene[-reading|-done]` for a Watch scene); the
  two running states are SEEDED (`DebugCapture.sayItAgainStage`) because a
  capture run has no mic, the same trick `captureShadow` plays.

## The learning loop (keep it closed)

```
conversation → summary (+ scorecard metrics) → DrillStore.ingest (SRS cards)
            ↘ LearnerProfile.absorb via ProfileStore  → next conversation's system prompt
            ↘ WeeklyReportEngine (unlocks on accumulated speaking time)
```

**Three states, and USED outranks KNOWN** (2026-09-15, user decision). Every
review item — a word, an expression, a sentence card — is in one of three
states, in order: **studying** (the deck's 10 min / tomorrow / 3 days),
**known** (the learner's OWN verdict: "Got it" on a card, "I know it" on a
word or phrase — a claim, nothing more), and **used in a talk** (the learner
produced it in a real conversation — evidence, and the strongest state there
is). Producing an item live moves it to the top from ANY state: a studying
word leaves the notebook and its schedule (`VocabStore.ingest`, same for
`ingestExpressions` and the bookmark), a known one becomes CONFIRMED (word
record `.known` → `.used`; expression count > 0; `DrillCard.usedInTalkAt`,
which `markUsedInConversation` stamps while taking the card straight to the
top rung, retired), and a `.suggestion` adopted later in the same call
confirms the card that call just minted. `CarryoverDetector` is therefore
given the known-but-unconfirmed items too (`knownWords` /
`knownExpressions`, sources `.knownWord` / `.knownExpression`), read from a
SNAPSHOT taken before `ingest` graduates anything, because the wrap-up still
has to say it was a notebook word they used. "Known" on every list means
known OR confirmed (`hasUsedExpression`, a non-nil word record, box 5), and
the row badge tells them apart: a plain check is the claim, a filled check is
the talk. The manual verdict stays — it is how a learner retires something
the app has no evidence for — but it never outranks their own mouth, and the
old rule (used once → +2 boxes, minimum 3) is gone: a spoken line is not
"probably known", it is known. Don't re-add a partial credit. **The call's
chip row leads with the known-but-unconfirmed items** (`TalkGoalPicker.pick`,
`claimedKnown`, drawn as an empty checked circle): a claim is what the call is
there to check, so it goes in front of the notebook. **Only a claim made on a NOTEBOOK item
counts** (2026-09-21, user decision, `Record.fromStudying`): "I know it" on a
word browsed in a level list, or "Got it" on a core-list top-up dealt for the
first time, was never studied and is not worth a chip — the user: "just saying
I know it in the word list means nothing". `markKnown` / `setKnownExpression`
stamp the flag when the item is in `studying` / `studyingExpressions` at that
moment; `unconfirmedKnownWords/Expressions` require it, so the chip row and the
wrap-up's known-word carryovers agree. Verdicts from before the flag read as
not-from-the-notebook. Same day: `addExpression` ("Save to expressions")
wrote a `.known` row, filing "study this later" as "I know this" — it is a
bookmark now.

**"You used what you practiced" may only list what was PRACTICED**
(2026-09-16, from a real wrap-up that read "nawana · app · english · setup ·
give me feedback"). Three things had gone wrong at once, and each has its own
guard now. ① `keepFromTalk` was filling the notebook with the learner's OWN
words: the fluent self answers about whatever the learner brought up, so its
turns echo their vocabulary, and nothing excluded it — `pickupCandidates`
takes `excludingLemmas` (the learner's turns in that talk) in both the
summarizer and the book chapter, and `offListContentWords` treats a capital
letter mid-sentence as a name, because NLTagger passes "Nawana" and
"English" as `OtherWord` (measured). ② A word the app kept by itself and the
learner never touched is not something they studied: `VocabStore.autoKept`
is a PROVENANCE mark (cleared by a hand bookmark, a deck snooze, a removal,
or graduation), `practicedStudyingWords` is what the detector and the call's
chip row read, and on first run every notebook word without a schedule
entry is treated as auto-kept — the conservative reading, since the only
thing it costs is a row that must never lie. ③ The phrase matcher tolerates
inserted words (right for padding), so "give me a feedback" satisfied the
card "give me feedback" — the learner repeated the exact mistake and was
credited, and under the used-outranks-known rule that retired the card as
confirmed. `firstMatch(rejectingMistake:)` now checks the matched SPAN
against the card's `sourcePhrase`: every token the correction added must be
present, every token it removed must be absent (`showsTheFix`). Cards with
no source line are unchanged. Don't relax the span to the whole turn — an
"a" three clauses later would reject a real fix.

**One card per sentence, enforced by the STORE** (2026-09-13). `ingest` had
deduped on the normalized target since the beginning, so the loop above could
not repeat itself — but `DrillStore.save` replaces by `id` only, and every
mint path outside ingest hands it a freshly minted `DrillCard` with a fresh
UUID: Watch's "Save phrase" on a scene played twice, the book page's
correction tap, the debug seeds a capture run re-plants (which is where it was
caught — one sample sentence sitting in the deck twelve times). `saveIfNew` is
now the one door for those paths: same `matchKey` ingest uses, plus the
`isDrillable` check, returning whatever is on file so a caller can still open
the card. `load()` collapses the copies already on learners' phones, keeping
the one with Leitner progress on it (read-time like the store's other repairs,
so deck, Sentences list and widget agree at once and the next write persists
it). A card the read filter would drop is never minted at all — a card no
lookup can find is what made every visit mint another one.

**"Got it" RETIRES a sentence card** (2026-09-14). The top Leitner rung used
to carry a 30-day interval, so a card marked known came back a month later,
was marked known again, and came back again — for as long as the app was
installed. Nothing else ever removed a card either (`DrillStore` has no cap,
no pruning, and the only deletes are "this talk was deleted" and "that turn
was misheard"), so Known was a waiting room rather than a door and the store
could only grow. `DrillStore.retiredReviewDate` is the top rung's return date
now, which is the rule the word and expression decks have always had
(`ReviewQueue.retire` clears the date outright) — the two decks agree again.
Three things hold it: the card is still LISTED under Known (the deck's folder,
the Sentences page's Known filter), re-filing it from that folder is what
brings it back, and `snooze` can no longer land on the top rung, because a
delay is by definition "not yet known". Cards that reached rung 5 under the
old rule are retired where they sit on read, so the backlog they built stops
returning. `DrillReminder` skips retired cards: their date is
`distantFuture`, and a reminder must never promise a card the deck won't
deal.

**And that is the ONLY way a card leaves** (decided 2026-09-14, when the
accumulation was raised). Nothing expires, nothing is pruned by age, no
backlog is swept: a card the learner never got to is still a sentence they
once said wrong, and an app that quietly deletes it has decided something
they didn't. Do not add a retention window, a card cap, or an "old cards"
cleanup to `DrillStore` — the store grows, and the exit is the learner
pressing Got it. The two deliberate exceptions stay what they are: deleting
the talk deletes its cards, and flagging a turn as misheard deletes the
cards minted from it.

**A talk book is finished when its CHAPTERS are** (2026-09-15).
`TalkCurriculum.Snapshot` counted two things — pickup words and the
turn-suggestion corrections — while the book page offered four chapters:
Words, Expressions, Shadow, Drill. So the Shadow chapter, the Expressions
chapter and every correction the SUMMARY produced (`phrasesUsed`, which is
most of them on many talks) counted for nothing, and a book reached 100%,
left Studying and landed on the finished shelf with the learner having
shadowed nothing and cleared no card. The chapter tabs said it out loud:
only Words carried a `done/total`. The snapshot is now one array per chapter
(`words` · `expressions` · `shadowLines` · `corrections`) and every one of
them counts — **anything the page asks for has to be in the snapshot**, or
the cover is measuring a different book from the one being read. Three
things that follow: the old `shadowLines` (corrections) is now `corrections`
and `shadowLineId` is `correctionId`, while `shadowLines` means the Shadow
chapter's fluent-self lines (`shadowPicks`, so page and count can't ask for
different things); the pages render the snapshot rather than building their
own filtered lists, because the Expressions page dropped a phrase once it
was known and a chapter that empties as you learn can never read as finished
(the same trap `pickupCandidates` avoids for words); and mastery keeps each
chapter's own rule — a word through `VocabStore`, an expression through the
expression pool, a shadow line only by a take at or above the bar, a
correction by its card reaching the top box. Books already showing as
finished go back to in progress, which is the truth: mastery is computed,
never stored. Watch books were always consistent this way — `ScenarioCurriculum`
holds exactly the three chapters `ScenarioDetailView` shows.

**A call's expressions come from BOTH mouths** (`expressions_offered`, 2026-08-19). `expressions_used` is what the learner said, verified verbatim against their own turns — that is EVIDENCE. For a long time it was the only expression a talk produced, so the whole class of "the fluent self said something good and I want it" was dropped: the only survivors were single lemmas (`TalkCurriculum.pickupCandidates`, which needs the word to be in `CoreVocabulary` at or above the learner's level, so phrasal verbs built from A1 words — `push back`, `end up -ing` — were filtered out by construction) and four shadow lines. The reusable chunk in between, which is the unit people actually learn, had no home. The summary call now also returns `expressions_offered` — up to 6 reusable phrases the FLUENT SELF used and the learner didn't — in the SAME call (no new request, no new spend), verified against the fluent-self turns and de-duped against `expressions_used` and against the learner's own words. It is MATERIAL, so it lives on `SessionSummary` and is merged at read time by `ExpressionCatalog` as `Origin.heard`, exactly as scene expressions are: never copied into `VocabStore`, whose rows count times SAID and would have to lie about a phrase nobody has spoken yet. Everything downstream is that merge — the Expressions library, the Practice tile, the talk book's Expressions chapter (offered above used), the book export, and the daily deck, which deals heard-in-a-call BEFORE said-it because a deck exists to teach what you can't say yet. The verbatim check is cheaper on this side than on the other: fluent-self text is model-written, so no transcriber sits between the phrase and the check.

**A word the graded list doesn't carry is still a word** (2026-09-13). The same gap, one size down. The pools are content-word CEFR profiles and small — English is 8,424 entries — so ordinary vocabulary simply isn't in them, and `pickupCandidates` dropped anything `CoreVocabulary.level(of:)` couldn't grade. Reported from a real talk: *chore* was said four times and was what the call was ABOUT, and the app never mentioned it once — not in the book's word chapter, not in the day's hand, not even highlighted in the transcript it was said in. `VocabStore.offListContentWords` now admits them from the FLUENT SELF's turns, which is the one place it is safe: that text is model-written, so no transcriber sits between the word and the check — the identical argument `expressions_offered` rests on. Four filters stand in for the pool (NLTagger content class, so no articles or "oh/wow"; not a name, so not Berlin or Jenny; ≥3 letters; and `CoreVocabulary.isUngraded`, a small hand-checked set that separates a word the list OMITS ON PURPOSE — auxiliaries, modals, indefinite pronouns, spoken fillers — from one it merely lacks, because without it "have" and "chore" are the same kind of missing). **They are NOT capped, and the first version's cap of 8 is the mistake worth remembering.** Its stated reason was that the graded half would otherwise be pushed out of the 24-item chapter — which never said why graded words deserve reserved slots, and they don't: both halves are words the fluent self chose. Worse, a cap has to decide which ones die, and with most of them said once there was nothing to decide it by, so spelling broke the tie and `sublet` lost to `boiler`. That is this section's own complaint re-made one level down. What orders them instead is evidence, in two grades: a word the fluent self came back to across SEVERAL TURNS is what the call was about and no graded list can see it, so those lead outright; a word said once is a weaker claim than a curated level match, so those fill whatever the graded words left. `offListContentWords` therefore counts TURNS, not occurrences — three times in one sentence is a verbal tic, not a thread. The mix balances itself with no quota: at A2 the graded words are plentiful and the singletons wait past the prefix, at B2 there are few and the singletons fill in. Three consequences to keep: `lookupKey` now resolves an ungraded surface form to its lemma ("chores" → *chore*) or the pickup list and the transcript's own tokens never line up and the word is collected without being highlighted where it was said; `ingest` keeps the pool gate on the LEARNER's side but lets their speech credit an ungraded word already in `studying` or `records`, so a kept word can leave the deck instead of being dealt back forever, while a mishearing still cannot MINT one; and Korean is empty by construction, since `koreanLemmas` can only return lexicon hits and an unconfirmable dictionary form is a guess, not a word to track. The fix is RETROACTIVE — talk books are derived at read time, never persisted — so the talk that prompted this shows *chore* without re-summarizing. `shadowPicks`' `teachScore` was deliberately left alone: re-scoring would reshuffle the shadow chapter of every existing book to fix a complaint about a different surface.

**And the notebook fills itself** (`VocabStore.keepFromTalk`, same day). Admitting the word was only half of it: the words a talk taught still stopped at the book page waiting to be tapped, so a word the whole call was about entered review only if the learner went looking for it — the same "it was never mentioned", one step further along. `SessionSummarizer` now keeps them automatically. Four rules hold it: it keeps **exactly the set the book's word chapter shows** (`pickupCandidates` under `TalkCurriculum.maxWords`), so the page and the notebook can never disagree about what a talk taught and no second ceiling is invented; it is **not `addStudying` in a loop**, because that logs a practice rep and fires `word_saved` — keeping a word by hand IS effort, and counting a machine's pick as the learner's would inflate the daily goal with work nobody did; it skips anything already known, used or kept; and it obeys `removedByHand`, a new persisted set written by `removeStudying`, because a talk that puts an unbookmarked word straight back every time is the app overruling a decision the learner made. Bookmarking the word again clears that verdict, so nothing about it is permanent.

**The notebook is spent in the call** (`TalkGoalChips.swift`, 2026-08-19). A talk is the only place a saved word can actually be used, and nobody remembers mid-sentence what they saved on Tuesday — so today's due studying items ride along the call as one pinned line of chips above the transcript, and a chip ticks the moment the learner says it. Three rules hold it together: the judge is `CarryoverDetector` and nothing else (the same matcher writes the wrap-up's carryovers, so the live tick and the summary can never disagree); ticks are ADDITIVE — every version of a user turn's text is checked, from the recognizer's first line to Gemini's audio-grounded rewrite, and a tick is never taken back; and the row writes nothing to disk, because `VocabStore.ingest` + `CarryoverDetector.detect` already credit the word for real at session end. Items come from `StudyScheduleStore` due-ness, the same schedule the daily words/expressions sessions deal from, so the app never asks for the same thing twice in one day — and a phrase that can't clear `CarryoverDetector.isCreditable` is never offered, since a checkbox that cannot tick teaches the learner the whole row is decorative. **Tapping a chip opens `TalkGoalSheet`** — "Use this in the call", the word, ONE sense, ONE example. The header is an instruction to SPEND the word, not to repeat a line after the app: it's material the learner chose to study, and the call is the only place it gets used. A chip that couldn't be tapped was demanding a word the learner may no longer remember the meaning of. It stays thin on purpose: the full entry belongs to the notebook, and the call is still running underneath (nothing pauses, and `WordLore` is free + globally cached, so a mid-call tap costs nothing metered).

**A talk on a scenario book spends THAT book** (2026-09-25, user request: re-running one scene until it's said with confidence is the fun, and the chips should be the words that scene is about). `TalkGoalPicker.pick(forScenario:previousTalks:proficiency:)` fills the row from the scene first — the book's unmastered words and expressions, then what the fluent self OFFERED in the previous runs of the same scene (`expressionsOffered`, pickup words the learner never said) — and only tops up from the global `pick()` after that, so a notebook phrase can never take a slot from a word the book is still teaching. Book items ignore `StudyScheduleStore` on purpose: the deck's "not twice in one day" rule protects the learner from being asked the same thing in two voices, but here they chose the scene and the scene is the reason to ask — don't re-gate them. The book lists rotate by the number of previous runs, so the fourth run doesn't lead with the first run's five. The chip carries the scene's own `example` + `note`, and `TalkGoalSheet` shows that line ahead of the dictionary's. Nothing new is written: `refreshScenarioMastery` already ticks a book word off from any talk on the scene, and `ingestExpressions` credits a phrase, so the row and the book's 13/33 move on the same evidence. Same day, the cause of half of it: `ScenarioDetailView`'s Talk button launched with no `initialScenarioId` (Practice's launcher passed it), so a talk started from the book page was a plain topic call — no stored opener pool, `kind = topic` in telemetry, linked to its book by title string only. `ConversationView.pickGoalItems` still matches previous runs by title as well as id for the talks saved that way.

**The wait at the end of a talk shows its work** (`SummaryProgressView`, 2026-08-19). `SessionSummarizer` reports a growing `Progress` struct — words + expressions kept, expressions offered by the fluent self, corrections that survived verification, carryovers found, cards minted — at the exact point each piece finishes, and the wrap-up screen draws it as a checklist with a determinate bar. Every number is real and is the same number the summary sheet then shows; nothing here is a simulated bar. **The steps follow the model's own writing order**, because the one summary call is the whole wait: it streams, and a section counts as finished when the key AFTER it appears in the partial JSON (`Progress.absorb`) — so the board ticks five times while the model works instead of sitting on step one and then completing all at once, which is what a buffered call produced and what the first version of this screen shipped as. The display trails the truth by `revealInterval` per step (`shown`), because the sections can still land in one burst — a fast write, or a deploy with no SSE at all — and seven rows ticking in a single frame is the same problem again; nothing is ever shown before it is genuinely done. `endSession` then holds the board for `revealTail` so the last rows can't be cut off by the summary sheet. `ConversationDetailView`'s rescue path draws the same board, because it builds the same things.

**The expression card IS the word card, and nothing in the library deletes**
(2026-09-23, user decision: "내표현과 단어의 UI가 다를 이유가 없다"). One
action bar for both (`CardButtons.swift`: Keep · I know · ↑ · ↓, the state on
the icon and tint, never the label — and the titles are `LocalizedStringKey`,
because a `String` handed to `Label` was never localized and both cards read
"Keep / I know" in Korean), one title rule (`N of M` walking a dealt list, the
library count otherwise), numbered senses, the same phrase tile, the same
long-press pair on examples, the same rounded list row and a search drawer on
both pages. The list's swipe-to-remove and the card's ⋯ "Remove from
expressions" are GONE: they existed for a mishearing in the learner's own
words, but under used-outranks-known such a phrase sits in the Known lens,
where nothing is dealt from it, and the words page has no delete either.
`VocabStore.dismissedExpressions` and its sync kind stay (old dismissals still
hide); don't bring a delete back on one page without the other.

**"Show me this later" is honored by the DEAL, not by one source of it** (2026-08-20). `DailyWordsView.pick` / `DailyExpressionsView.pick` fill the day's hand from four sources — the notebook, unmastered Watch-book items, a recent talk's pickup words, then a core-list top-up — and only the FIRST asked `StudyScheduleStore.isDue`. The other three judge by `VocabStore.records` / `isKnownExpression`, and `addStudying` never writes a record, so a word put away for 10 minutes was excluded from the notebook source and re-added by the core list on the very next deal: closing the session and reopening it dealt the same cards back, and the three delays meant nothing. **The gate now lives inside `pick`'s own `add(_:)`**, the one funnel every source runs through, so a fifth source cannot quietly reintroduce it — never re-gate per source.

**A folder is a WINDOW on the return time, and there is one implementation** (2026-08-20). Both decks drop into `DrillBin`, and both now bucket the same way — `DrillBin.folder(forReturnIn:)`, ≤12h Soon · ≤48h Tomorrow · else Later — over whatever is still waiting: the sentence deck from `DrillStore.nextReviewAt`, the word/expression deck from `StudyScheduleStore.upcoming`. So the folder is where a thing IS, not which button last touched it ("3 days" the drop, "Later" the place), it survives closing the sheet, and any row re-snoozes from its context menu. `StudyDeckView`'s folders used to be a `@State` tally of this session's drops that emptied on dismiss, which is why the same drag meant two different things depending on the deck. **"Got it" is the one folder that stays session-local**, and must: marking something known CLEARS its return date (`ReviewQueue.retire`) — a known item has no return, so there is nothing on disk to list. **A folder row offers the tray's FULL set of verdicts** — all four, minus "Got it" on a row that already has it (the only true no-op; a delay always re-times from now). Filing takes one drag, so re-filing can't take a trip through the notebook, and a menu missing a verdict just moves the dead end. "Got it" is the one that can't be undone by rescheduling alone, because it ERASES the return date instead of writing one: `StudyDeckView.bringBack` stops it being known, returns it to the notebook, then snoozes — `DailyWordsView.resolve`'s delay branch in reverse — and clears only a `.known` record, never the `.used` one a spoken word earns. Re-filing logs NO rep in either deck: the card was counted when it was graded, and changing your mind isn't a second one. The menu is a long-press, so both decks' folder lists carry a footer saying so; an affordance nothing points at is the same dead end as not having one. The chips also stay on the deck's done state, because "where did all that go?" is asked after the last card, and reopening the deck to look was the very thing that made the fix look broken.

Every feature should feed this loop. Per-turn suggestions come back in the SAME Gemini call as the reply (structured JSON) — never split the suggestion out, and never remove the field: `ScorecardMetrics.suggestionRate`, drill ingestion, and the weekly report's repeated-mistake detection all depend on `Turn.suggestion`.

**A turn is answered TWICE: the whole thing re-said, and the mistakes named**
(2026-09-27, user decision, from a replay screenshot). `suggestion.alternative`
used to be specified as "ONE sentence only — the single sentence with the most
teachable slip. NEVER the whole turn … ≤ 15 words", and the stated reason was
the drill card: a paragraph is un-drillable. That constraint was right about
cards and wrong about everything else, and it leaked into the two places the
line has to be COMPLETE. On screen a 29-word utterance was answered by a
12-word clause under the heading *더 자연스럽게* — not what a fluent speaker
would say, a twelfth of it. Worse, `SayItAgainScript` reads that line back
IN the conversation, so the re-run replaced the turn with the fragment and
answered questions nobody had asked ("대화가 하나도 맥락이 없게 되고 있어").
The two answers are now separate fields and both ship:

- **`alternative` is the learner's WHOLE turn, re-said** — every idea they
  raised, in their order, in their register, answering what was just said to
  them, with the hesitation (fillers, false starts, a word said twice) gone.
  Not longer than what they said. It is Say it again's line and the
  transcript's Shadow target.
- **`fixes: [{was, now, why}]` is the grammar**, each a CLAUSE (the prompt
  asked for "SHORT" first and got `temporal issue → temporary issue`, which
  no card can use — see below), `was` quoted verbatim. **An empty array is an
  ordinary answer**: a turn can be perfectly grammatical and still not be
  what a native would say, which is the whole reason the two are separate.
  Every ASR guard applies to `fixes` unchanged.
- **`turnSuggestion(for:)` is the gate, per piece.** A fix whose `was` isn't
  the learner's (`ConversationEngine.quotes` — the summary's `isTheirs` rule,
  spaces compared away for ko/ja) is dropped: it accuses them of words they
  never said. A rewrite that changes nothing audible is dropped too, and its
  fixes then ride on THEIR turn with the fixes spliced in — never on a fix
  alone, because a lone clause read in place of the turn is this bug again
  (the first pass did exactly that).
- **`fixes == nil` DATES the record, and that is load-bearing.** The funnel
  always writes a non-nil array, so nil means "saved before this contract":
  `alternative` is a fragment, and `SayItAgainScript.coversWholeTurn`
  demotes it — the prompter reads what they SAID and the better wording rides
  as the note. Don't judge this by length: `어 그 그니까 그게 뭐냐면 좀 복잡해`
  → `그게 뭐냐면 좀 복잡해` is 4 words against 7 and is the contract working.
- **Every reader of "the correction" reads `fixes` now, and there were five.**
  Missing any one of them is a silent regression, found only by a review:
  `DrillStore.ingest` (a card per fix; a clean turn mints none),
  `TalkCurriculum` (a Drill item per fix; mastery by the card's TEXT, because
  every fix of a turn shares its `sourceTurnId` and matching by turn let the
  first graduate card master its siblings; a passing take on the whole line
  masters all of that turn's fixes), `CarryoverDetector` (adoption later in
  the call matches the FIX with `rejectingMistake` — nobody repeats a whole
  turn verbatim, so matching `alternative` would credit nothing ever again),
  `WeeklyReportEngine` (the recurring-mistake pairs are `was → now`, not
  whole turns mixing style with grammar), and the book page / export (the
  Drill row quotes the card's own pair; the transcript prints the fixes under
  the rewrite — `BookDocument.Line.fixes`). Records without `fixes` keep the
  old behaviour everywhere.
- **`DrillStore.cardPair(for:in:)` is the ONE rule for the card a fix
  becomes**, used by all of the above. Usually the fix as written. But
  `CarryoverDetector.firstMatch` never credits under three tokens in a spaced
  language, and a whole Korean clause is often two eojeol (`학교에 갔어`,
  `빵을 먹었어` — 4 of 24 Korean fixes on the probe); a card that can never be
  marked used breaks used-outranks-known for that card. Such a fix is widened
  to the SENTENCE it sits in with the fix applied — the learner's own words,
  one correction. Two surfaces computing the pair two ways would be a Drill
  chapter whose items can never find their cards.
- **`correctionId(for:index:)`** — index 0 is byte-identical to the old id,
  so every attempt on disk still lands; a fix item's turn can't be recovered
  by flipping its id back (byte 14 differs), so the page carries the turn id
  alongside instead.
- **The correction call is given the line said TO them** (`requestRealtimeSuggestion`,
  "They were just told: …"), because a whole turn only reads right against
  what it answers — the coach call had no context at all, which is the gap
  the 2026-09-25 register bug came through. Context only; the prompt forbids
  correcting or answering it. `maxTokens` 512 → 900: the call is buffered,
  so a truncation loses the WHOLE correction, not its tail.
- Measured with `scripts/correction-probe.py`, rescored for this contract
  ("was it flagged" is meaningless now): fixes on clean lines · missed errors
  · fragment rewrites · fixes too short to credit · fixes not quoting the
  learner. **en** (new `correction-cases-en.json`, the reported utterance
  first) 0/8 · 0/12 · 0/20 · 0/24 · 0/24; **ko** 1/86 · 1/24 · 0 · 4/24
  (all widened by `cardPair`) · 0; **ja** 2/72 · 0/24 · 0 · 0 · 0; **de**
  0/70 · 0/24 · 0 · 0 · 0. The outliers on clean lines are naturalness notes
  filed as fixes (`やつ、でも → やつだけど`), not invented errors. Re-run all
  four before touching either prompt. `TurnFixTests` pins the five readers.

**A correction may never be built on something the TRANSCRIBER chose** (2026-08-21). The prompt has said this three ways for a while — the ASR DROP guard (a clipped subject pronoun), the ASR DIGIT guard (spoken numbers written as digits), and "punctuation, capitalization and spelling come from the transcriber". A fourth was missing and shipped as the visible bug: **dictation EXPANDS contractions**, so a learner who said "I'm building" is transcribed "I am building" every single time, and the model dutifully offered "I am" → "I'm" under the heading *더 자연스럽게*. That tells someone they made a mistake they did not make, in their own voice, mid-call. Three layers now, because a prompt is a request and the model had already been asked:

- **The prompt** carries an ASR CONTRACTION GUARD next to the other two.
- **`ConversationEngine.saysTheSameThing`** drops any suggestion whose `alternative` reduces to the same `spokenWords` as the line the model answered — case, punctuation and a fixed English contraction table normalized away. Deliberately narrow: it only collapses differences no mouth can produce, so every real change of words survives. `turnSuggestion(for:)` is the funnel, and it must be given the text the MODEL saw (`chunkModelText[turnId] ?? turns[idx].transcript`), not what is on screen.
- **`highlightedCorrection`** diffs through the same `spokenWords`, so "I'm" and "I am" align instead of lighting up as the fixed part. It expands one display token into several comparison words, so a token is painted only when EVERY word inside it went unmatched.

The narrowness is the point in both directions: a mixed suggestion that fixes something real AND happens to contract still survives the filter, and now highlights only the real fix.

**Same rule, every language, both correction paths** (2026-09-23, after a
review asked whether the grammar/naturalness verdicts hold per language).
`saysTheSameThing` now compares `comparable()` — `ShadowEngine.expandForDiff`
(curly apostrophes, hyphens, DIGITS spelled out in the target language, English
contractions) then `spokenWords`, and for Korean with the SPACES removed,
because 띄어쓰기 is the recognizer's ("한번" / "한 번"). Both prompts carry a
Korean ASR SPACING GUARD next to the Japanese SCRIPT GUARD. The summary's
`phrases_used` had neither check: `SessionSummarizer` now drops a phrase whose
quote isn't the learner's (not contained in a turn, and under three words in
four shared with one) or whose fix changes nothing a mouth can hear — the same
two gates the live suggestion and the grammar quotes already had. And
`DrillStore.ingest` refuses a card whose target or source isn't in the target
script (`TextScript.isInTargetScript`, shared with the weekly test): a learner
who slipped into Korean for a turn got a "Show me the clock once" card and a
test item built on it. `looksLikeMetaRule` knows the Korean/Japanese/German
words for grammar categories too; its list was English.

**The SPEECH LEVEL is the learner's, and a coach never touches it**
(2026-09-25, from the founder's own call: "체험을 하고 계시는 거야" was
corrected to "거예요" under *더 자연스럽게*). Neither correction prompt nor
the summary carried a single Korean rule beyond spacing; the "casual register
is not a slip" line had English examples only, and the coach call gets ONE
line with no context — not that the call is with the future self, not that it
is in 반말. Measured with the live `correctionOnlyPrompt` on Gemini 3.6 Flash
(55 spoken Korean lines × 2 runs, `scripts/correction-probe.py <lang>` over
`scripts/correction-cases-<lang>.json` — it reconstructs that language's
prompt from the Swift source, `NO_REGISTER=1` runs it without the guard): every false correction was one of two kinds —
a SUBJECT honorific beside a 반말 ending pushed to 존댓말 ("주무셔" →
"주무셔요"; 주체 높임 and 상대 높임 are independent and the model reads them
as mixed politeness) and spoken right-dislocation "fixed" to written order
("먹었어 아까 라면"); real errors were all caught, but their alternatives
sometimes drifted to 존댓말 too ("저 … 공부했어요"). `registerGuard`
(Korean + Japanese; the Japanese half is the same rule, unmeasured) now rides
on all three prompts next to the spacing guard: the level spoken in is
correct whoever the counterpart is, never change an ending, and the
alternative stays in that level even when it fixes something else. After it:
0/86 false corrections, 0/24 missed, alternatives in 반말. **Japanese has the
same bug and the same block** (measured the same day, 48 lines × 2): without
the guard, 尊敬語 about a third person beside a plain ending was called
"inconsistent" ("社長がいらっしゃるまで待ってて" → "…ください") and two
alternatives drifted to です; with the guard plus a JAPANESE HONORIFICS line,
0/72 and 0/24, and 0/16 on the honorific lines over four runs. **German needs
nothing** (47 lines × 2, du and Sie lines, spoken "hab / geh / glaub",
dropped subjects, particles): 0/70 false, 0/24 missed, no du → Sie in any
alternative — so it carries no guard and its prompt is unchanged. Code
guarantee for
the second kind: `changesOnlyWordOrder` (Korean only — an English reorder can
be a real fix) drops a suggestion or summary phrase whose words are the same
multiset; it is NOT used for speculative-reply adoption, where a reorder is a
different line. Nothing server-side records a correction's text or a
per-language correction rate (the ledger has model + purpose), so the probe
is the only measurement there is — re-run it before touching either prompt.

**And a SCORE may never be built on it either** (2026-09-13, `ShadowTranscriber`). Shadowing was the last surface still resting on Apple's recognizer alone, and there a transcript is not context for a model — it IS the grade: the diff, the score, the coach bullets and the rhythm card are all computed from it. Reported that day: *"Soak it all in, right?"* came back as **"So right"**, every attempt. Connected speech (`[soʊkɪɾɔlɪn]`) is exactly what an on-device pass collapses, and the learner was told they had skipped three words they said perfectly well. Three layers, in order, all of them in the one new door every shadow score walks through:

- **The audio is levelled before anyone reads it** (`AudioLoudness.peakNormalizedWAV`, boost-only) and the SAME file goes to both readers, so they are judging the same thing. The learner's own playback still uses the ORIGINAL — the take is theirs, the levelling is for the machines.
- **The words come from the audio** — Gemini on the DEFAULT model, not the cheap tier the live talk path uses: nobody is waiting to hear this one, and the words it writes are the learner's grade. **It is never shown the target sentence.** It could only copy it, and a word the model supplies is a mark the learner did not earn; the prompt's own rule says so out loud. Apple's pass keeps its `contextualStrings` bias, because its text is now the FALLBACK and its real job is timestamps.
- **The times come from Apple, realigned onto Gemini's words** (`ShadowTranscriber.realigned` → `LocalAlignment.align`/`fill`). `ShadowEngine.analyzeRhythm` demands exactly one timing per word of the SCORED text, so swapping the transcript without this would have silently killed the rhythm card on every attempt. Under `minAnchorRatio` (0.5) of the words anchoring, the timeline is mostly interpolation and [] is returned — the card hides instead of grading a guess. **That is the reported case's own outcome**, and it is an improvement: two timestamps used to be graded against "So right", which is a rhythm number about a sentence nobody said.

`Source` is `audioGrounded` · `onDevice` · `rough`, worst-first fallback, and only `rough` (nothing read the file) raises the UI's warning — the old behaviour is still a real final pass, just a weaker one. `shadow_transcript` logs the source plus whether the two readers described DIFFERENT sentences, which is the only measure there has ever been of how wrong the single-reader path was.

**The result never waits on the slower reader, and never on the coach**
(2026-09-17). Telemetry from a real take: Apple's pass had the 18-word line
in 4 s, and the learner then sat on "Comparing…" for exactly 60 s more —
the Gemini transcribe request (the whole take as base64, on cellular) had
stalled without failing, and nothing declared it dead before
`URLSession.edgeFunctions`' ceiling; no ledger row, so it never reached the
edge function. Two braces now: once the device pass has landed, the
audio-grounded read gets `ShadowTranscriber.audioGraceAfterDevice` (6 s — a
healthy call lands in ~2 s) and is then CANCELLED and the take scored
on-device (`AudioOutcome.abandoned`); with no device text it keeps a 20 s
leash, and the request carries its own 25 s timeout under both. The
transcribe call runs `fastThinking` — perception, not reasoning, and the
ledger showed ~95 thought tokens on a six-word line. And the coach call
left the critical path: `analyze` puts the score, diff and recording up
and SAVES the attempt as soon as the deterministic half is done, then
fetches the bullets behind a "Writing feedback…" row and
`updateShadowAttempt`s the same record (never `saveShadowAttempt` twice —
that counts an attempt). `shownAttemptId` keeps a late reply off a newer
take's screen. `shadow_transcript` now carries `audio` / `device_ms` /
`audio_ms` and `shadow_coach` its `ms`, so the next "it takes long" can be
read off a row instead of reproduced.

**A phrase take is not the line** (2026-09-17, from a full review of the
surface). Tapping two words and shadowing "the bank" saved a `ShadowAttempt`
under the line's `turnId` with nothing to say it was partial, and every
reader — Talk and Watch mastery, the Practice retry pick, the book pages'
best score — filtered on `turnId` alone, so a two-word take checked off the
sentence. `ShadowAttempt.phraseRange` (optional, old records decode) marks
it; `isPartial` takes are listed, replayable and counted as reps, and
excluded from everything that judges the LINE. Same pass: Watch mastery
read `matchScore` while Talk read `overallScore` — one bar now
(`overallScore`, the number the take is judged by everywhere); a take with
NO speech is not a 0 — it is `heardNothing`, one line under the target,
nothing saved, counted or coached (the auto-stop fires at the line's length
with nobody talking, so this is an ordinary path); the whole-line pace
ratio measures first word → last word like the phrase path always did,
instead of the file length with its silent tail (0.83× and "rushed" for a
take that matched the voice); `expandForDiff` folds typographic
apostrophes so a model-written "I’m" isn't a substitution against the
recognizer's "I'm"; `interactiveDismissDisabled` while recording (a swipe
left the mic hot and let the auto-stop save a take for a screen that was
gone); the karaoke highlight outranks the diff colours while the target
plays, so "Hear target" moves after a result; the free timing recovery is
re-armed once per visit and two seconds late, so a quick retry cancels a
sleep rather than a recognizer. Japanese timelines are cut into words
since 2026-09-18 — see "Japanese as a TARGET language". Chinese is not a
selectable target, but `WordSplitter` already counts it as unspaced and
would cut it with the JAPANESE tokenizer — give `zh` its own segmenter
before it gets a wordlist.

**"Both at once" lines the takes up by EAR, not by timings** (2026-09-18).
The duet skips each file to its first word, and both leads came from word
timings: the learner's from `ShadowTranscriber.realigned`, which is empty on
every take the aligner couldn't anchor (~11% of takes, plus the abandoned
audio read), and the target's from a timeline that is a character-count
estimate on any line that came from a call — an estimate starts at 0 and a
render always opens on silence. A missing lead read as 0, so the take played
from the top of the file and the learner heard their own voice arrive a beat
late ("내 목소리 앞쪽에 여백이 너무 심해"). `AudioLoudness.firstVoiceOnset`
now reads the onset off the audio that is about to play — peak-relative gate,
same `speechGateRatio` the level measurement uses, so a quiet take and a loud
one are judged alike. A PHRASE selection still comes from timings, because
its start is mid-file rather than the first sound in it. It measures an
ENVELOPE (10 ms block RMS), not samples: speech crosses zero every few
hundred microseconds, so a sample-wise "loud for 40 ms" run never completes
and reports silence for every file — `AudioOnsetTests` caught exactly that
before it shipped, which is the reason those tests build their own WAVs
instead of mocking the reader.

**The rhythm card may only grade a beat somebody MEASURED** (2026-09-16, `WordTiming.isMeasured`). The Target row had no such rule: every live-call line is saved with `timings: []` (the streaming TTS returns none), so the shadow view opens on `estimatedTimings` — character-count proportions — while the free `LocalAlignment` pass runs behind it; `startSync` kills that pass (two recognizers on one mic truncate the take) and nothing re-armed it, so a learner who pressed record first had EVERY attempt of that visit coloured against a made-up beat. Both alignments (`LocalAlignment.fill`, `ShadowTranscriber.realigned`) also share out up to half their words across gaps a recognizer never placed, indistinguishable from a measurement. Now every timing source marks its spans — ElevenLabs and Apple segments measured, the estimate and every filled gap not (old caches decode as measured; they passed the anchor gate when written) — and `analyzeRhythm` pins the normalization on measured pairs only, credits only those, needs `minMeasuredPairs` (4: the pinned two score 1.0 whatever happened, so three left one word judged) and returns nil for an estimated target, which `overallScore` already reads as "not measured". `rearmTimingRecovery` restarts the free pass once the mic is down. **The verdict is drawn ON the target line, and there is no rhythm card** (same day, two passes): `beatMark` puts a dot under each word the attempt was timed on, where the learner started — under the centre on the beat, pushed right if late, left if early, in the score's own colour scale — and nothing under a word unmeasured or skipped; the score sits in the target section's header where the word count was, with `6/10` beside it when it stands on fewer than all the words. Two things it replaced: bar timelines (Target / You) whose bars carried WIDTH, a duration the score never reads and one the two sources disagree on by construction (ElevenLabs leaves gaps, Apple's segments abut), so the rows looked different for reasons unrelated to rhythm and a grey interpolated bar still invited comparison ("Target and You look nothing alike, how is that 100"); then a per-word card with `+0.2s` labels, correct but a third of the screen (user: too much space, put it on the sentence, no seconds needed). Colouring the word itself was rejected — text colour already means "wrong word". Don't bring a second timeline or a card back. Known, deliberately untouched: the dot turns green at ±120 ms while credit starts fading at ±60 ms, so an all-green row can read 85.

**The correction card never precedes the voice** (2026-08-21, two iterations). Holding the bubble's TEXT swaps until `voiceDidStart` was not enough: the card itself is a correction the learner READS, and the payload usually closes while the TTS is still loading, so it kept appearing before the voice — "it corrects me, then answers" every turn. It was removed from the live call outright, then restored the same day with its DISPLAY deferred: `requestReply` parks the suggestion on `DeferredTurnWork` while the turn is still held, and `flushDeferredTurnWork` (voice audible) is what sets `turns[idx].suggestion` — so the card appears with the voice, never ahead of it, and nothing ever waits on it (display timing only, zero latency cost). A payload landing after the flush applies directly, which is fine — the voice is already out.

**A live turn is exactly two calls, and they run CONCURRENTLY** (2026-08). Measured: with the audio attached, the reply took 4.1s to start vs 2.1s without — the model has to ingest and transcribe before it can write the reply's first token, and that sat between "learner stops talking" and "fluent self starts talking".

- **Reply call** (`turnPayload` → `sendJSONStream`, default model, TEXT ONLY) — `{reply, suggestion}`. This is the only one the learner waits to HEAR.
- **Transcription call** (`UtteranceTranscriber`, `flash-lite`, audio attached, `purpose: "transcribe"`, priced at **0 credits** so the latency win doesn't double the price of talking) — verbatim line only. Lands whenever; `applyGeminiTranscript` edits the bubble in place.

Do not re-attach audio to the reply call, and do not add a THIRD per-turn call. Ordering between the two is not guaranteed: `lastRecognizerText` is what keeps the recognizer's late rescored pass from clobbering the audio-grounded line (`applyRecognizerUpgrade`).

**The reply call may start BEFORE the VAD confirms the turn** (2026-08-21, `SpeculativeReply`). Measured on device, the model burst-writes — ~2 s of thinking, then all tokens at once — so `firstSpeakableSentence`/split-speech never fires (`tts_split=0` on every logged turn) and the only way to shorten the visible Gemini wait is to start it earlier. At 0.6 s of true silence with a settled partial (`speculateAfterSilenceSeconds` + the `sttSettleSeconds` guard), the endpoint monitor fires the SAME reply request against the recognizer partial (`fireSpeculativeReply` → `fetchTurnPayload`, which is `turnPayload` parameterized over messages); the VAD then spends its remaining 0.5–1 s confirming while the model thinks. `requestReply` adopts it only if the committed text still `saysTheSameThing` as the snapshot — else it's cancelled and the normal request fires. This is NOT a third per-turn call: it's the reply call with a head start, and a discarded one is free (the `gemini` edge function charges nothing, `purpose: "turn"` is only rate-capped). Only a CHANGED PARTIAL cancels it in the monitor tick — never mic energy, which reads as "voice" forever in a noisy room and churned fire/cancel 4x per turn when it was a condition (measured same day; adoption's word match is what correctness actually rests on) — and fires are capped at `maxSpecFiresPerTurn` per listening turn; every mic-stopping exit runs through `stopListeningDiscardingChunks`, which kills it too. `spec=1` / `spec_lead_ms` on `talk_turn_timing` say how often it lands and what it buys. Same day, and part of the same latency pass: `chunkAssemblyDeadlineSeconds` 1.5 → 0.35 → 0.1 (the tail chunk's RTT is ~1.3 s past turn end, so the wait was pure loss — see the constant's comment), and the streaming TTS path sends `optimize_streaming_latency=3` (edge function, deployed 2026-08-21). **The chunk wait is GONE entirely since 2026-08-31** — prod telemetry showed ~87% of turns paying ~130 ms (deadline + poll tick) for a `late` assembly; `adoptChunkTranscript` now harvests only what is already settled at turn end, zero wait. Same pass: the `elevenlabs-tts` and `gemini` edge functions run their pre-work (rate bump · voice ownership · charge / free-usage record) CONCURRENTLY instead of serially — they were 2–3 sequential DB round trips inside both `gemini_first_ms` and `tts_first_ms` on every turn; scene calls keep the old serial order because a scene claim has no un-claim — and `LiveTranscriber.stopAndFinalizeInBackground` defers `engine.stop()` (the voice-processing teardown, the bulk of `finalize_ms` ≈ 200 ms) to a detached task, pausing the engine inline instead.

**The transcription is deferred past the voice** (2026-08-14). Concurrent in control flow is not concurrent in RESOURCES: it was fired first, and its ~100 KB audio upload shared one `URLSession` — and therefore one HTTP/2 connection to one Supabase host — with the reply call *and* the ElevenLabs stream. Measured same-day, turns carrying the upload reached the reply's first sentence **0.8–2.2 s later** (5 of 5 days, same direction). Two changes keep it genuinely in the background:

- `DeferredTurnWork` holds both the transcription call and the recognizer's rescored line until `voiceDidStart()` — the single choke point every TTS path (split stream, plain stream, buffered, cache hit) runs through when audio actually reaches the speaker. Holding the recognizer line too is a PERCEPTION fix: a bubble that rewrites itself mid-wait reads as "it corrects me first, then answers" even though nothing ever waited on it.
- `GeminiClient.background` / `URLSession.edgeFunctionsBackground` gives the upload its own connection pool. Use it for any future call whose result nobody is waiting to hear.

Three consequences to preserve when touching this: the failure path in `requestReply` and `endSession` must both flush (a turn that never speaks still needs its correction, and `endSession` freezes `turns` for the summary — it waits ≤2.5 s for an in-flight call); `voiceDidStart` flushes BEFORE its `turnTiming.isEmpty` guard, so a logging condition can never cost a turn its transcript; and the audio-path field moved from `talk_turn_timing` to `talk_asr_upgrade` because it is now known only after the timing row has shipped.

**NOTHING may rewrite the learner's bubble before the voice — including the thing that makes the reply RIGHT** (2026-08-21). The chunk pipeline (`ChunkASRState`, 2026-08-19) transcribes the turn in pieces while the learner is still talking so the REPLY can be generated from audio-grounded text instead of the on-device guess — a real fix for `asr=fixed` turns, and it must stay. But it landed in front of `requestReply`: `adoptChunkTranscript` waited up to `chunkAssemblyDeadlineSeconds` and then wrote the corrected line straight into `turns`, so on every `chunk_path=full` turn the correction was on screen a whole Gemini + TTS round trip before the fluent self spoke. That is the exact perception `DeferredTurnWork` exists to prevent, re-introduced by a feature that had no reason to touch the view at all. Two rules now hold it:

- **The text the model answers and the text the learner reads are allowed to differ, for exactly the length of that wait.** `chunkModelText` carries the assembled line into `turnPayload` via `modelTurns()`; the bubble keeps the on-device line until `flushDeferredTurnWork` swaps it (chunk text outranks the recognizer's rescore there — it's audio-grounded and already answered). Everything downstream of the call reads `turns` after the flush, so summary/drills/book never see the split.
- **`deferredTurnWork` is armed in `stopAndSend`, the moment the turn is appended** — not in `requestReply`. The chunk wait sits between the two, and while nothing was armed the recognizer's rescored pass (2.0 s timeout, so it routinely lands inside a 1.5 s chunk wait) sailed through `applyRecognizerUpgrade`'s hold branch and painted a second correction. `requestReply` only arms when the turn isn't already held, which is the Retry path.

Any future work that improves the learner's line has the same obligation: improve what the MODEL gets, never what the SCREEN shows, until `voiceDidStart`.

## The grammar band is RANGE × ACCURACY (2026-09-24)

Reported by the founder: an A1–A2 learner who said only easy things read
**≈C2 grammar** on Progress. `ProgressTab.grammarBands` maps verified slips
per 100 words to a band, and a talk of short present-tense clauses carries no
slips because nothing was attempted — accuracy without range, and the
fallback (the scorecard's 0–100 score, "empty slip list ≈ 90–100") lands in
the same place. A CEFR grammar level is the meeting of the structures you
COMMAND and how cleanly, so there are two reads now and the LOWER wins
(`ProgressTab.grammarBand`, pure, `GrammarBandTests`):

- **Accuracy** — the slip density as before, score as the fallback.
- **Range** — `SessionScorecard.grammarRange` (a1…c2), written by the
  summary call as `scorecard.grammar.range`: the band of the structures the
  learner actually PRODUCED in that talk, with a language-agnostic ladder in
  the rubric and the rule said out loud that accurate one-clause replies are
  a1/a2 range whatever the score. It is a judgment code cannot compute
  across four target languages, made by the call that already reads the
  transcript for the scorecard — no new request, no new spend, and the same
  kind of read as `cefr_level`. Progress takes the MEDIAN over the density
  window (one attempted conditional is not a range you command); the weekly
  assessment gets `per_talk_grammar_range` and is told range first, slips
  second. Range never RAISES the band.
- **Talks summarized before the field have no range**: the graded
  vocabulary (words actually used) + 1 band stands in as the ceiling
  (`GrammarCeiling.vocabulary`), and the row says so. Nobody's grammar
  outruns their productive vocabulary by more than a band.

When a ceiling applied, the Grammar row and page explain the ceiling, the
next-band density target goes away (fewer slips would move nothing) and the
focus tip asks for longer sentences instead of fewer slips. The trend chart
stays the accuracy curve — its zones are accuracy bands.

## The weekly test (2026-09-23)

One sit-down a week, built from THAT learner's own week: the words the talks
taught, the phrases the fluent self used, the sentences that were corrected,
the lines worth hearing again. Nothing comes from a generic bank — an item
with no source in the learner's material is not an item. Files:
`WeeklyTestEngine` (build + grade + write-back), `WeeklyTestStore` (+
`WeeklyTestSettings`, `WeeklyTestSchedule`, `WeeklyTestReminder`),
`WeeklyTestView` (+ `WeeklyTestResultView`), `SoundEffects`; entry row on the
Practice Today card, settings section in `StudyGoalsSheet`, route
`.weeklyTest` / `futurevoice://weeklytest`, sync kind `.weeklyTest`.

- **Five kinds, one shelf each, every grade computed in code**: `meaning`
  (a notebook word's gloss → pick the word; decoys are the learner's other
  notebook words, then graded words of the same word class — `WordClass`,
  2026-09-24, read from `word_classes_<code>.tsv` built by
  `scripts/build-word-classes.py` from the sources the wordlists came from:
  the CEFR-J/Octanove profiles for en, JMdict for ja, orthography + a hand
  list for de (capital = noun, -en = verb, else adjective — one class with
  the adverbs) and ko (다 = predicate). Audited over all four lists first:
  a lone-word `NLTagger` agreed with the English profiles 72% of the time,
  had NO model for ko/ja, and swapped German adjectives and adverbs, so the
  tagger and the headword-shape rules are only the fallback for a word off
  the list. A headword can carry several classes (run: noun,verb), so the
  engine asks `sameClass`, never equality; same class outranks the
  learner's own pool, and the graded list spans the level ±1 band), `gap` (a
  fluent-self line with its `expressions_offered` phrase blanked → pick the
  phrase; decoys are the week's other phrases before the library), `build`
  (a correction card: "You said …" → lay the fluent version from shuffled
  tiles, plus up to two decoy tiles taken from the learner's OWN wording),
  `listen` (a fluent-self line with audio on disk, heard with its text
  HIDDEN and rebuilt from its own word tiles — dictation; "pick the line out
  of three" shipped first and was a length test, obvious at any level, user
  2026-09-24),
  `speak` (a fluent-self line said out loud: one mic button, the take read
  through `ShadowTranscriber` — the one door every shadow score walks
  through — scored by `ShadowEngine.analyze`, passing at
  `PracticeStats.retryThreshold`, and SAVED as a `ShadowAttempt` of that
  turn, so the talk book's Shadow chapter sees it). The only model calls
  are the free, cached dictionary lookup that writes a gloss and the
  audio-grounded read of a take; no LLM ever decides whether an answer was
  right.
- **Misses come back.** Last week's wrong answers are dealt again first this
  week (`maxRetake` 3, badge "Again"), and the **monthly test** collects every
  distinct wrong answer of the month's weekly tests (`buildMonthly`, cap
  20, same `minItems`). It opens with the first weekly opening of each
  calendar month (`monthOpening`) over the tests finished since the previous
  month's first opening; its row appears on the Today card only when there
  is something to collect (`monthlyState`). `WeeklyTest.kind` (nil =
  weekly) tells the two apart in one store; the weeks-in-a-row streak and
  the weekly state ignore monthly papers.
- **The week is the learner's, not the calendar's.** `WeeklyTestSchedule` is
  one weekday + time (default Saturday 10:00, in the goals sheet); every
  moment belongs to the most recent opening, so a test taken on Tuesday is
  still "this week's", and a finished test shows its score on the row until
  the next opening. Material window = since the last test was built, else
  seven days. Under `minItems` (5) the row says "a talk or two first" and
  the opening is remembered as thin so the tab doesn't rebuild on every
  appearance. Settings are device-local like the daily call (two synced
  devices must not both ring); the tests themselves sync (`ArrayKind`, LWW).
- **Write-back is a CLAIM, never a verdict** (see "USED outranks KNOWN"):
  meaning right → the word waits 3 days, wrong → back in the notebook, due
  now; gap the same for the phrase (wrong bookmarks it); build right → one
  Leitner rung up (`DrillStore.markCorrect`, which never retires), wrong →
  one down; listen writes nothing. Applied once (`appliedAt`) when the test
  finishes; answers are saved as they land so a closed sheet resumes.
- **Sound + haptic per answer, and nothing else invented.** `SoundEffects`
  plays four synthesized WAVs (`scripts/make-ui-sounds.py`, -12 dBFS) with
  `AVAudioPlayer` on the app's playback route — NOT a system sound: under
  the app-wide `.playAndRecord` session those went to the earpiece or
  nowhere, inaudible on device — toggle in the goals sheet, beside the
  existing `HapticEngine` cues. The run of right answers is a flame on the question's caption line
  (a bar above the host was tried and pulled: it framed the face); the
  result is a system `Gauge`, one positive line, last week's score in a
  footnote, the per-kind rows, then every answer. No confetti, no custom
  chrome; the whole screen is system buttons.
- **The host** (`WeeklyTestCharacter`): two pixel eyes on a rounded-square
  tile — each eye one 12.8 pt cell, stretched tall (0.82 × 1.12), moved and
  blinked with smooth motion, no mouth, no brows, no mosaic behind them.
  Settled by eye on 2026-09-23 after the live Futureself mosaic (colour,
  then grey), a sub-pixel rasterised eye, a mouth, arches and a circle
  backdrop were each tried and set aside the same day: colour and deep
  black fought the eyes, a round face on a round disc read as someone
  else's robot, a squint read as sleepy. Moods: waiting glances and blinks;
  `happy` (right) lifts the eyes with a flutter of three blinks and a
  bounce; `sad` (wrong) drops them, long and low, inner corners up; `angry`
  (second wrong in a row) narrows them into inward slits — a pout at
  itself, brief, never a scold; `thinking` sweeps while the paper is
  written. Preview poses with `-moodhold happy|sad|angry`, `-eyelid 0…1`,
  `-eyeshape 0|1|2`.
- Captures: `-capture weekly-test-{word,gap,build,listen,speak}` (+ `-right` /
  `-wrong` to pre-answer), `weekly-test-result`, `practice-weekly`,
  `monthly-test`, `practice-monthly`. The
  seeders clear the store first — a test minted by one launch would
  otherwise be the next launch's window start.

## Japanese as a TARGET language (2026-09-18)

Japanese was wired for STT, shadow scoring and the clone script from the
start, and hidden from the picker because it had no graded wordlist. It now
has one, and the harder half was everything that assumed spaces.

- **The pool** (`cefr_words_ja.tsv`, built by `scripts/build-ja-wordlist.py`):
  Waller's JLPT N5–N1 (CC BY, via open-anki-jlpt-decks) mapped N5→A1 …
  N1→C1, C2 empty. The attribution is the file's first line — the loaders
  skip a line with no tab, and there is no credits screen. **The headword is
  what the learner SEES**, so its spelling is settled against JMdict (CC
  BY-SA): kana where nobody writes the kanji (ください, not 下さい; ちょうど,
  not 丁度), today's okurigana (落ち着く, not 落着く), and a hand-checked
  list for the rest — JMdict's "usually kana" flag alone is NOT trusted (it
  marks 犬 and 行く). A third column carries the READING(S) (からい・つらい),
  which the word card prints under a kanji headword; `ja_forms.tsv` maps
  every other spelling (わかる, 判る, 朝御飯) onto the headword, skipping any
  spelling that names two words and any one-kana form (that is inflection).
- **`JapaneseMorph`** segments (CFStringTokenizer — NLTagger has no lemma and
  no part of speech for Japanese, measured) and maps stems to headwords,
  lexicon hits only, like `KoreanMorph`. A stem before inflection is the verb
  (行き+ました → 行く, not the noun 行き); a kanji-only surface never grows
  a verb ending (語 is not 語る, 箸 is not 走る); particles, auxiliaries and
  spoken contractions (てる, ちゃう) are grammar and never a word. Read a
  CHUNK, not a segment, wherever a level or key is wanted — 疲れ alone can't
  say it is 疲れる.
- **`WordSplitter` is the one question "where are the words?"** Every
  `split(separator: " ")` over target-language text asks it instead —
  highlights, phrase matching, word counts, titles, sentence ends (。！？).
  Two of those were silent failures: the realtime path requested a
  correction only for `>= 3` space-separated words, so no Japanese turn ever
  got one, and the gateway dropped any ONE-word utterance inside the 1.2 s
  echo window, which was every Japanese answer (`isScrap`, gateway). Never
  count words on " " again.
- **The script is the transcriber's, like punctuation.** 分かった / わかった
  is a choice no mouth makes, so `saysTheSameThing` compares READINGS for
  Japanese and both correction prompts carry an ASR SCRIPT GUARD (appended
  at a line end so every other language's prompt is byte-identical). The
  correction highlight is per CHARACTER — segments are cut differently on
  either side of a fix — so it reads くさ[かっ]た. The shadow diff and the
  character timing alignment follow the same rule (`JapaneseMorph.soundSpelling`,
  2026-09-18): a romaji name in the target (nawana) comes back from ja-JP as
  ナワナ, so Latin runs are cut into kana and katakana/hiragana compare
  equal — before this the app's own name was scored as a miss on every take.
- **Shadowing cuts its timeline into WORDS too** (`WordSplitter.timingWords`
  — punctuation rides on the word before, an opening bracket on the word
  after, so the words joined give the line back, which is what the screen
  draws). ElevenLabs' per-character alignment is grouped into those words;
  Apple's segments, cut wherever the recognizer likes, are aligned to them
  LETTER by letter (`LocalAlignment.alignByCharacters`, used by the free
  karaoke pass and by `ShadowTranscriber.realigned`), and a word counts as
  MEASURED only when its first letter lands on a real segment start — the
  onset is all the rhythm grade reads. A timeline stored as one run is
  refused on load (`cutMatches`) and rebuilt. Karaoke draws the words flush
  for an unspaced language — gaps between them read as spaces Japanese
  doesn't have.
- Captures: `-capture transcript-ja` / `talkdetail-ja` / `wordcard-ja` /
  `shadow-ja` with `-futurevoice.targetLanguage ja`.

## A call does not die quietly (2026-09-13)

Talk runs on the realtime gateway (`gateway/`, a Worker + Durable Object) —
and until this date that path could end a call for nine different reasons
without leaving a single record, on either side. The reply and the voice go
straight to their providers, so `usage_ledger` sees only the meter's ticks;
the app's `RealtimeTalkClient` wrote nothing at all; the gateway had
`console.log`. On 2026-09-12 that produced an admin console reporting zero
errors on a day when **25 of 42 real sessions ended before the learner
finished a sentence**, and the day's two trial cancellations had to be found
by joining `user_subscriptions` by hand. One of them cancelled two minutes
after a summary timed out; the other wrote "좋은데 중간에 끊긴다" and re-dialled
seventeen times.

**Only being unable to HEAR is fatal.** Everything else the call survives:

- **A failed reply is retried once, then apologised for out loud**
  (`CallSession.recoverReply`). It used to emit `error`, which the client
  turns into a teardown. The apology line is the learner's language,
  informal, and is pushed into `history` — otherwise the next reply answers a
  question it never heard the answer to.
- **A refused or dropped ElevenLabs socket ends the LINE** (`warn("tts")` →
  `endLine`): the text is already on screen and the socket reopens lazily.
- **A transcriber failure stays fatal — but only once the socket could not
  be REPLACED** (2026-09-16). Gemini's transcribe socket ends every ~10 min
  and on any upstream hiccup, and `GeminiTranscriber` rotates it (resumption
  handle, mic audio buffered meanwhile). Until 2026-09-16 the socket's
  `error` event skipped that path and ended the call outright, while `close`
  — which always follows an error — would have rotated: three of that day's
  six drops, one exactly 10 min 4 s after the previous connect. Both events
  now go through `rotateFrom`, idempotent per socket generation (the old
  socket's own close, and a second event for the same end, can't start a
  second rotation); a rotation is a `warning` (`transcriber`, "rotating: …"),
  and only a refused reconnect or >4 rotations a minute is `fail`. **The
  rotation itself dropped a call the day after it shipped** (2026-09-17, a
  19-turn call, `internal`: "Can't call WebSocket send() after close()"):
  `rotate` closed the old socket and awaited the new upgrade while
  `setupDone` stayed true and `ws` still pointed at the closed socket, so
  the next mic frame was a `send()` on a dead socket, and that TypeError
  escaped through `handleClientMessage`'s catch — which is `fail`. Now
  `rotate` nulls `ws` and drops `setupDone` BEFORE the await (frames buffer
  in `pendingAudio`, newest-kept, flushed on setupComplete),
  `sendAudioB64` never throws (a refused send buffers the frame and starts
  the rotation itself), and the session wraps the forward in its own
  try/catch as a `warning` — a frame that could not be forwarded is never a
  reason to end a call. The app
  answers that with **Reconnect** (`ConversationView.reconnectRealtimeCall`)
  — same voice, the turns so far as history, no opener. Before this a dropped
  call had no message at all: the screen went quiet and the only move was to
  hang up.

**Every failure now leaves a record, and that is the point.** The gateway
sends two new messages (`gateway/src/protocol.ts`): `warning` (survived) and
`ended` (the session's last word — reason, turns, speech seconds,
commit→voice latencies, warnings). `RealtimeTalkClient.fail(_:_:)` is the ONE
door every client-side failure goes through, and it writes
`talk_rt_failed`; the two gateway messages become `talk_rt_warning` and
`talk_rt_session`. All of it lands in `client_events`, which is where the
admin console's 통화가 어떻게 끝났나 panel reads it from (`rt_sessions` /
`rt_reasons` in `admin_raw()`, `20260913080000`). An older client ignores the
new messages, so the gateway can deploy ahead of an app build.

**A finished line must give its ElevenLabs CONTEXT back** (2026-09-13,
`gateway/src/eleven-tts.ts`). One multi-context socket allows FIVE at a time,
a line is one context, and a context lives until it is closed or goes final.
`isFinal` is not reliable — the play-out fallback exists precisely because it
usually never arrives — so a call that only ever ended lines locally leaked one
context per line: the SIXTH line was refused
(`Maximum simultaneous contexts per WebSocket connection exceeded (5)`), the
socket errored, and the rest of the call had no voice at all while the text
kept appearing. Prod log 2026-09-13 shows it at turn 7 of a real call, and it
is the likeliest reading of launch week's "좋은데 중간에 끊긴다". `endLine` now
closes the context; `closeContext` is idempotent and a context that went final
on its own is dropped from `openContexts` when the final lands, so nothing is
closed twice.

**The app's first line can arrive before the gateway has finished starting,
and must be HELD, not dropped** (2026-09-13). `say` exists so a written
greeting (a scenario, a Find-people call) can be generated while the call
opens — which means the two race, and on the first device test the app won by
0.7 s: the message hit a `!this.started` guard, was dropped, and the call sat
silent. `pendingSay` holds it and `applySay` runs the moment `ready` goes out.
A `say` is only ever the FIRST line: it is ignored once a turn has happened, so
a late greeting can never talk over a conversation already under way.

**The greeting is played from the phrase cache, and the gateway is never
asked for it** (2026-09-13). The Talk launcher already synthesizes every pool
opener into `PhraseAudioStore` (`FreeTalkOpeners.warmAudio`) — and the realtime
path ignored all of it, so the first word waited on the gateway's own
ElevenLabs round trip for a line the phone had had on disk since the tab was
opened. `connect(openerAudio:)` decodes that take and `playLocalOpener` speaks
it the moment `ready` lands; the text goes up in `history` instead of
`start.opener`, so the gateway records what was said and stays silent — no
protocol change. A cache miss or an undecodable file is a nil and the gateway
speaks it exactly as before. The line is otherwise identical to a streamed one
(same echo gate, same `AudioLoudness` levelling, same hand-off with audio), so
Replay and the book can't tell. **It waits for `ready` on purpose**: the
allowance pre-flight runs in front of that, and a spent month must be told
before the fluent self says a word. Measured on device: tap → first word 4.4 s
→ 2.8 s, and the remaining wait is now almost entirely the gateway's
`start` → `ready`.

**Nothing in front of the first word may be serial if it doesn't have to be**
(2026-09-13, `gateway/src/session.ts`). `start` ran verify → ownsVoice →
allowance pre-flight (~1 s) → the transcriber's Gemini Live handshake → `ready`
→ opener, and every hop of it was silence the learner sat through. The voice
check and the pre-flight are independent round trips (`Promise.all`), and the
transcriber's handshake is no longer awaited before the greeting — nobody can
answer a question that hasn't been asked, mic audio arriving meanwhile is
buffered (`pendingAudio`, ~5 s) and flushed on setup. `ready` still goes out
BEFORE `audio_start`: the app reads it as connecting → listening and would
otherwise overwrite the speaking state the opener just set, leaving the line
with no hand-off.

**The audio stack is never rebuilt while the fluent self is AUDIBLE, and
exactly one thing may rebuild it** (2026-09-13). Two watchdogs were restarting
it on two clocks — `startMicWatchdog` at 1.5 s and 3 s from connect, the
per-build `armTapWatchdog` every 2 s — and a restart drops every reply chunk
that lands while the engine is down (`playReplyChunk` guards on
`engineRunning`; the bytes are kept for Replay, not for the speaker). So the
churn ate the one line a call opens with: the learner got the opener's TEXT,
no voice at all, then "the call dropped" five seconds in (three times on
build 45, every one `mic_bytes=0`). A cold voice-processing unit needing more
than 1.5 s for its first buffer was killed twice before it could deliver one.
Now `armTapWatchdog` owns recovery alone (first check at 3 s, then 2 s, three
restarts, then `mic_silent`), `startMicWatchdog` is a passive 12 s deadline,
and both DEFER while audio is playing — measured as `playedBuffers`, buffers
that finished playing, never as queue depth, because a wedged engine accepts
buffers forever and plays none. `fail(_:_:)` now ships `audioFacts()` with
every failure (route in/out, input channels, engine running, tap buffers,
builds, played/queued) — the three `mic_silent` rows could say no byte went
upstream and nothing whatsoever about why.

**The end-of-talk summary gets its own URLSession** (`edgeFunctionsLong`, 240 s
ceiling) and retries once on a timeout. `edgeFunctions` caps every attempt at
60 s; on 2026-09-12 a summary finished server-side at **63 s**, the app called
it a failure, and that learner cancelled her trial two minutes later. The idle
timeout stays 40 s — only the ceiling moved, and only for this one call.

**The `ended` record is read by whoever gets it first** (2026-09-23). The
hang-up drain above never worked: `receiveNext` always has a read
outstanding, so IT received `ended`, and its torn-down guard threw the
message away — 10 records for 179 calls in the week of 09-16. A torn-down
read now keeps exactly that one message (`endedRecord`, `logSession` is
once-only via `sessionLogged`), and a gateway `error` — which the gateway
follows with `ended` a millisecond later — closes through
`closeKeepingSessionRecord` like a hang-up does, instead of a bare
`teardown()` that cancelled it unread.

**A wall is not a failure, and the console's "문제" is an ALLOWLIST** (same
day). Every wall (`insufficient_credits` is the free call's designed
wrap-up) goes through `fail()`, so it lands in `talk_rt_failed` beside a
dead socket; `20260923150000` hands the console the row's `code` and lists
failures as call endings (`rt_sessions.src = 'failed'`), and the page keeps
`RT_WALL` apart from `isDroppedCall`. The problem count itself is
`FAILURE_EVENTS`: `client_events` carries every kind of record the app
writes (shadow timings, paywall views, the wrap-up closing) and a denylist
drew all of it as red dots — 33 of 34 people had "문제", 13 had a failure.
A new telemetry event is not a problem until it is named there.

**A summary that can't be decoded says what it wrote** (same day). Eight
retries and two failures that week were all `dataCorrupted@` at the root —
not truncations (max 2083 of 8192 tokens), and nothing said what the model
produced. `sendJSONStreamAccumulating` now throws `GeminiError.malformedJSON`
with Foundation's line/column, a 160-char excerpt around it, and
`dropped_chunks` (SSE lines that failed to decode — a hole in the text is
the transport's fault, a typo the model's); `decodeDetail` carries all of it
into `talk_summary_retry` / `talk_summary_error`. Read the next one off the
console before guessing at a repair pass.

## A call outlives the screen (2026-08-18)

A phone call doesn't end because you looked at something else. Until now this
one did: no `UIBackgroundModes`, so iOS suspended the app seconds after a lock
or an app switch — engine stopped mid-sentence, recognition task dead — and
nothing put it back together, so returning found a call that was still on
screen and stone deaf.

- **`UIBackgroundModes: [audio]`** is declared in `FutureVoice/Resources/Info.plist`.
  The claim is honest (the app is audibly speaking and recording for the whole
  time it holds the session), but it is the kind of declaration App Review
  reads closely — if it's ever questioned, the answer is the live call, not
  "background processing".
- **The lock screen gets the call** (`CallNowPlaying`): topic as the title,
  flagged as a live stream so there's no scrubber, and play/pause wired to the
  exact two things the mic button does (`handleMicTap` / `pauseCall`).
  Without it iOS shows whatever played before us, and a locked phone has no way
  to hang up. `begin`/`end` must bracket every call path — `endSession` and
  `tearDown` both end it, `startNewSession` begins the next one.
- **Interruptions are handled** (`ConversationView.handleAudioInterruption`) —
  a real incoming call, Siri, an alarm. iOS has already stopped the engine by
  the time the notification lands, so `.began` only stops our state from lying;
  `.ended` reopens the mic when the system says `shouldResume`.
- **`live.isEngineRunning`, never `isRunning`.** An interrupted run still reads
  as started — that gap is what made a stalled call invisible. `resumeCallIfStalled`
  tests the engine and runs on every foreground as a cheap no-op safety net.
- Metering follows from the idle rule above: a backgrounded call bills only
  while someone is actually speaking, so a phone in a pocket costs nothing
  unless it hears a voice.
- **A CAFÉ IS THE HARD CASE, and it took three tries** (2026-08-18, tested in
  a real one). Mic energy alone is permanently true in a room full of other
  people: a call nobody was speaking into never went idle (>3 minutes against
  a 60s bar, all billed) and no turn ever ended — the room never falls silent,
  so energy endpointing can't fire, and the recognizer keeps making fresh
  partials out of other people's voices, so the transcript-quiet fallback
  keeps restarting. Four changes, all needed together:
  - `someoneIsTalkingHere()` takes **three witnesses**: recent energy, the
    recognizer still making words of it, and ≥`minVoicedSecondsPerTurn` (1.5s)
    of this segment above the voiced threshold. Both the meter and the
    watchdog ask it, so the call pauses on exactly the silence it bills zero
    for.
  - `FluencyMeter.noiseMargin` 6 dB → 11 dB. It leans on physics: a mouth
    20 cm from the mic against a table metres away is 15–20 dB. **Quiet rooms
    are untouched by construction** — there the absolute 0.35 floor is the
    higher bar and decides alone.
  - A listening turn has a 30s ceiling (`maxListenSeconds`, logged as
    `vad_path=ceiling`) — but it fires only while `someoneIsTalkingHere()` is
    false, because the clock alone cut real 30s+ monologues mid-sentence
    (reported 2026-08-18, zero silence, quiet room). A person demonstrably
    still speaking holds the turn open up to `maxListenSecondsHard` (120s),
    where it ships what it has; a room's babble never clears the voiced
    threshold, so the café case fires at 30s exactly as before. If a
    ceiling'd turn has no close-mic evidence, the segment is DROPPED and the
    mic reopened (`restartListeningQuietly`) instead of paying for a reply
    to a stranger's sentence.
  - `lastActivityAt` lives OUTSIDE the watch task, because that quiet restart
    re-arms it every 30s and a clock inside the task would never reach the
    bar. Only real activity moves it.
- **After 30s of nothing at all, the call PUTS ITSELF DOWN** — it does
  not end (`idlePauseSeconds`, `startIdleWatch` → `pauseCall`). Ending is a
  decision with consequences: a summary, drills, a book. Pausing has none —
  the transcript stays on screen and one tap resumes the same session, which
  is what the mic tap and the lock screen's pause have always done. The point
  isn't the money (idle is already free) but the open mic: a call nobody is in
  keeps listening, and the first voice it hears — a TV, someone else in the
  room — would be billed AND answered as if it were the learner. `pauseCall`
  is the single place every stop lands; `isPausedForIdle` exists only so the
  hint under the pill can say "paused" rather than leaving a quiet screen
  unexplained.

## The accent is a remix, and the remix must stay the speaker (2026-09-18)

`VoiceAccentSheet` remixes the clone upstream (`elevenlabs-voice-remix` →
`/v1/text-to-voice/{id}/remix`) and saves the picked take as a NEW voice; the
clone it came from is then deleted like any outgoing voice. Three rules,
each from a way the voice stopped sounding like the learner:

- **`prompt_strength` is sent, and it is low** (`VoiceAccentCatalog.promptStrength`).
  It is the upstream knob for how far a remix may leave the reference audio
  (0 keeps the recording, 1 keeps the prompt); the first version sent nothing
  and let upstream choose, while the prompt text asked for "this exact same
  voice" — a request, against a parameter. Retune it by ear with
  `scripts/voice-remix-probe.sh` (same prompt and sample text as the app, one
  file per strength), never by feel, and probe an UN-remixed clone or the
  probe measures drift on drift. The value rides into the ledger row's
  metadata so a complaint can be read against the strength it was made with.
- **Takes always come from the un-accented clone.** A second pick used to
  remix the live voice, i.e. the previous remix, and the learners who tried
  hardest to find themselves (three and four saves in a row in the ledger)
  drifted furthest. With an accent live, `choose` first rebuilds the clone
  from the phone's saved recording (`regenerateVoiceClone`, the same path as
  "Remove accent"), then remixes that. Leaving without applying leaves the
  learner on the un-accented voice — `rebuiltWithoutApply` makes the sheet
  tell its presenter so on ANY exit, because onboarding's greeting audio still
  belongs to the old voice.
- **The recording is the only way back, and it lives on the phone.**
  `VoiceSampleStore` (Documents, so it rides in the backup) is what "Remove
  accent" and the rebuild above read. The server copy in `voice-originals`
  is NOT a fallback for this: it is kept for 24 h to listen to a clone that
  came out wrong, and the consent screen says exactly that. A remixed voice's
  `voice_clones` row has no `original_path` of its own.

## A voice nobody pays for is PARKED (2026-09-28)

ElevenLabs Pro holds 160 custom voices for the WHOLE account, and every
learner's clone is one. Measured that day: 96 used — 87 learners' clones (6
subscribers, 25 lapsed, 56 free), 19 accent remixes, the founder's own — and
37 of the non-paying clones had been idle over a week. So a clone with nobody
paying is deleted upstream after **7 days** (founder's call) and rebuilt from
the phone's recording when it is wanted again. `park-idle-voices` (hourly,
`20260928140000`, cron created DISABLED) + `VoiceParking.swift`.

- **One rule: no plan, and the app not opened for 7 days** (2026-10-01,
  founder decision, `voice_parking_candidates` in
  `20261001150000_park_by_last_open`; free minutes left or not makes no
  difference). It replaced two rules that judged a learner with nothing to
  spend by when they last SPENT, so someone who kept opening the app to look
  was parked as if gone. "Opened" is read off `auth.refresh_tokens` /
  `auth.sessions.refreshed_at` (the client refreshes its token on any launch
  an hour after the last; matched PostHog opens for a real learner), plus
  ledger debits, client events, a subscription's end and the clone itself.
  Grants are not activity. Anonymous users stay with
  `cleanup-anonymous-voices`. `parkable_voice_owners` still holds the old
  rules and nothing calls it.
- **Parking is a stamp, not `is_active = false`.** The row stays active and
  `parked_at` is set, because an old build that finds no active row runs
  `voiceWasDeleted` → re-record → a free clone that takes the slot straight
  back. `elevenlabs-tts` and the gateway's `ownsVoice` read `parked_at` and
  answer with the SPENT-POOL 402 (`insufficient_credits`, `reason:
  voice_parked`), so every build, old ones included, shows its paywall.
  `elevenlabs-voice-clone` refuses the same way to an account with a parked
  row and nothing to spend (`voice_clone_allowed`) — a brand-new account never
  has one.
- **Stop generating, never stop playing** (founder: "that isn't generation").
  `AppState.voiceCloneId` KEEPS the parked id: every cache lookup is keyed by
  it, and nil would both hide audio on disk and route the learner into
  onboarding. `ElevenLabsClient` refuses a parked id before the network with
  `.insufficientCredits`; the word, expression, study-deck, drill,
  enrichment and weekly-test players now answer that with their own
  `PaywallView` (they used to stay silent), the rest already did. The daily
  call stands down while parked.
- **It comes back at the TAP, in front of the learner** (2026-10-01, founder
  decision, `VoiceRevival` / `VoiceRevivalView`). `refreshParkedVoice` only
  LEARNS the state (foreground · sign-in · purchase). There is no "your voice
  is resting" notice anywhere — the tap answers: nothing to spend → the
  paywall, as `BillingGate` always did; allowed to spend → `BillingGate.start`
  / `startScene` presents a full-screen "Recreating your voice" (UIKit-presented
  on top of whatever is up, because a launcher can sit in a sheet), rebuilds
  from `VoiceSampleStore`, then a page to set the speed and accent again (the
  remix died with the old voice), and **Start the call** runs the tap's own
  action. A slot is only taken back by someone about to use it. The sample is
  never synced and the server copy lives 24 h, so a phone without it gets the
  reclaimed-voice "make your voice again" screen instead. Surfaces outside the
  launchers (a word's audio button) still answer a parked voice with their
  paywall.
- **Never parked unannounced** (2026-10-01, `20261001120000_voice_park_notice`).
  `park-idle-voices` announces two days before a voice qualifies — a
  `voice_park_notices` row fixes the date, a push (`kind: voice_parking`, app
  language, title by rule: a plan keeps it / opening the app keeps it) names it, says
  it is deleted for safety and can be made again anytime — and parks only after
  that date, only for the same idle stretch. The date is a UTC day and parking
  waits until noon UTC the day after, so "after <date>" is true in every zone.
  No push token still gets a row; the row is the rule, the push a courtesy.
- A parked id is never staged for deletion (it's already gone), and
  `elevenlabs-voice-delete` now treats `voice_does_not_exist` as done.
  Re-cloning drops the accent remix, and each re-clone spends one of the
  account's monthly voice add/edits (Pro: 290).
- **Deploy order is load-bearing.** Migration FIRST (the TTS function and the
  gateway select `parked_at`; without the column every TTS call 500s and every
  call is `voice_forbidden`), then `elevenlabs-tts` / `-voice-clone` /
  `-voice-delete` / `park-idle-voices` and the gateway, then the app build in
  the store, then `?dry=1` read by a person, then the cron switched on.

## The voice is heard BEFORE the sign-up (2026-08-18)

Onboarding used to ask for an account between "use this voice" and the clone —
the first server-bound act, so it looked like the honest place for it. It was
the worst one: the app was asking someone to open an account for a voice they
had never heard. What the server needs is a **session**, not an account.

- `useThisVoice` opens an **anonymous Supabase session**
  (`AuthService.startAnonymousSession`), clones, synthesizes the greeting, and
  runs the whole Meet act on it. The account step now sits AFTER Meet and asks
  to KEEP a voice already in the learner's ears.
- **Apple is LINKED to that anonymous user** (`linkIdentityWithIdToken`), which
  keeps the user id — so the clone, the consent record, the credit row and the
  referral code all survive the sign-up. Signing in fresh would mint a second
  user and orphan the voice. Requires `enable_anonymous_sign_ins` AND
  `enable_manual_linking` in the project's auth settings (both on in
  `config.toml`; the hosted project needs the same two toggles).
- **A session is not an account, and every gate must know the difference.** Ask
  `auth.isSignedIn`, never `session != nil` — `RootView` and the view's
  `resumeUnclaimedVoice` both hold the flow on the sign-up step for an
  anonymous session, or a killed app would drop someone into an app whose data
  dies with the install.
- **Two fallbacks, both silent.** Anonymous sign-in unavailable (setting off,
  no network) → the old order, sign up then clone. Apple identity already has
  an account (a returning user who tapped "Get started") → linking is refused,
  they're signed into their real account, and the clone is rebuilt under it
  from the take still on disk (`adoptedExistingAccount`).
- **Unclaimed clones are collected 30 minutes after the anonymous user was
  created** (swept every 15 min since `20260822110000`; it was 48h before) —
  `cleanup-anonymous-voices` + `stale_anonymous_users` (ElevenLabs delete
  first, then the user, which cascades). A voice that fails to delete upstream KEEPS its user so the
  next run can retry; deleting it would lose the only pointer to a slot we pay
  for. The cron needs `project_url` + `cleanup_secret` in the vault and
  `CLEANUP_SECRET` in the function env — until then it simply doesn't schedule.
- **A reclaimed voice is SAID, never dialled** (2026-09-21). Someone who clones
  and leaves before signing up comes back to a voice that no longer exists. The
  app used to walk them into Talk anyway: `RealtimeTalkClient.accessToken`
  minted a fresh anonymous user, the gateway refused the dead id
  (`voice_forbidden`) twice, the sign-up that followed linked the stale id to a
  real account, and they left without hearing a word. Now `AppState` keeps
  `unclaimedVoiceSince` (the anonymous owner's `createdAt`, nil once an account
  owns the session) and two checks lead to `voiceWasDeleted`: the CLOCK
  (`checkForReclaimedVoice`, launch + foreground, no network — past
  `reclaimGraceMinutes` the voice is gone whatever the phone knows; keep it
  equal to the function's `GRACE_MINUTES`) and the SERVER
  (`restoreVoiceCloneFromCloud`: the query succeeded, this user owns no active
  row, the phone holds an id → the voice belonged to someone who is gone). It
  drops the id, signs an anonymous session out, and the voice-clone screen opens
  on "Let's make your voice again" (positive first, the deletion is the second line) until the next clone lands. The silent anonymous
  sign-in in `accessToken` is DEBUG-only.

## Coach mode — the listening moment, used (2026-09-28)

Talk time was high and review low, and the chip row only waits for a studied
word to come up by chance. Coach mode (Call settings; **on by default for A1/A2**, off above —
`CoachMode.resolve`, the learner's own flip always wins; a beginner's
slower call) makes it come up on purpose: the fluent self asks a
question whose natural answer uses a studied item, and while the learner
thinks, the line above the pill carries "Try using · **profound**" (under
the "try saying" sentence, below) and ticks when they do (the chips' own
`CarryoverDetector`; tap = the chip sheet). Worded so the word never needs a
particle or article. It sat in the "Listening…" bubble until 2026-10-01. The pool is the chip row
PLUS talk-kept notebook words (`coachExtras`) — the first device test had
eleven words on file, all auto-kept, and the chip row alone was empty.
`CoachMode.swift` + `CoachHintLabel`.

- **The hint comes FROM the question, never from a list.** The first cut
  steered one word at a time in list order and hinted it whenever the line
  ended in "?" — the model rightly ignored words that didn't fit but asks
  questions anyway, so the learner saw words in list order with no relation
  to what they'd been asked. Now the steer offers the whole candidate list
  as permission, and after each line `CoachJudge` (flash-lite,
  `purpose: "coach"`, free) reads the question actually asked and names the
  candidate a natural answer would carry — or null, the usual answer. Probe
  (`judge.py`-style, 8 cases): 7/8, the miss a conservative null; the prompt
  had to rule out reaction words ("awesome") and small words ("one") that
  fit any answer.
- **The steer is permission, not an order** ("if one fits what you're
  already talking about…; never steer the topic; don't say the word"). The
  feature is judged by whether it feels forced.
- **It rides on the gateway's `set` as `steer`**, appended to the reply's
  system prompt until the app clears it — set when a line FINISHES (the next
  reply is generated the moment the learner stops, speculative ones included,
  so later is too late) and cleared once the steered line has been spoken.
  An older gateway ignores the field; the hint then appears without a
  question built for it.
- **A hint is drawn only if the steered line ends in a question**, and
  `CoachPlan` rations in code: never before the learner has spoken, 3 per
  call, 2 plain replies between. `talk_coach` (hints, used) is one row per
  coached call — the measure of "forced".
- **Nothing before the learner has spoken** (enforced 2026-09-30 — the
  ration above was documented but not in code: the opener's question could
  be judged and the first reply steered). `syncCoachSteer` and the WORD
  hint wait for `learnerSpokeThisCall`; the "try saying" below does not.
- **Every line gets a "try saying"** (2026-10-01, founder: "every turn, a
  suggestion of how to answer"; `CoachSuggester`, which replaced
  `CoachJudge`). One flash-lite call per fluent-self line, the opener
  included: a short answer at the learner's level, `___` where only they
  know the fact (a faded example in `[brackets]` since the same day), its meaning in the native language (hidden when native ==
  target). A studied item that fits rides inside it and becomes the word
  hint (still rationed by `CoachPlan`). Drawn ABOVE THE PILL, never in the
  listening bubble — it lands a beat late and the bubble grew out of view.
  A suggestion not in the target script is dropped (`TextScript`): a
  Hangul name in the line once turned the whole suggestion Korean.
- **A coached call is a PRACTICE call** (`Session.coached`, 2026-10-01,
  founder decision): coach mode on at any point = the whole call. It is out
  of the weekly assessment, its unlock gate and every Progress measurement,
  its page shows "Practice call" instead of a score, and NOTHING said in it
  is credited as used (words, expressions, drill cards, book items) — a
  studied item said there is a practice rep. Minutes, streak, the Core,
  corrections → cards and the book all stand.
- **The grammar FOCUS** (2026-09-30, founder: "a real coach goes past
  words — mind the tense"; `GrammarFocus.swift`, `GrammarFocusViews.swift`).
  One recurring mistake per call, from `LearnerProfile.recurringMistakes`
  (frequency ≥ 2, seen within 45 days, highest first), named once in the
  native language by flash-lite (`describe`, cached per pattern + language:
  "과거 시제" + one tip line) and pinned ABOVE the chip row as a strip —
  the name beside the learner's own pair, trimmed to the span that changed
  (`GrammarFocusPair.compact`: "…I go to… → …I went to…"; whole sentences
  truncated to one line kept the ends and cut the one word that differed).
  The steer gains a GRAMMAR FOCUS paragraph (a question that needs the
  structure, never a correction in the reply). Every live correction with
  `fixes` is judged by flash-lite `isRepeat` — the same grammar POINT, not
  the same words (probe: 20/20 on ten same/different cases, ko/en/de) — and
  a repeat badges that card ("다시 · 과거 시제", orange, a reminder not a
  failure) and moves the strip's counter. The result rides on the talk as
  `Session.grammarFocus` (the book page shows it under the score) and is
  what RETIRES a focus: two focused calls with no repeat, and no summary
  re-detection since (`lastSeenAt`), and the next pattern takes over; a
  re-detection brings it straight back. A call the learner never spoke in
  records nothing, so it can't count as clean. Captures: `-capture
  call-focus` / `call-focus-sheet` / `focus-result`.
- Next: expression VARIETY (the learner's overused phrase paired with one
  the fluent self offered, hinted the moment they reach for the old one),
  then a one-time offer of coach mode on the wrap-up for low levels or
  repeated mistakes — offered, never switched on silently.

## Source of truth

- **Domain types** → `FutureVoice/Models/Models.swift`. Update there first.
- **Prompt templates** → `ConversationEngine.swift` (conversation + summary), `ShadowEngine.swift`, `WeeklyReportEngine.swift`, `TopicEngine.swift`, `DrillEnrichmentEngine.swift`. The shared two-language preamble every coaching prompt splices in lives in `CoachingLanguage.swift` — see "Two languages" below.
- **HTTP** → `GeminiClient.swift` and `ElevenLabsClient.swift` only. Both route through Supabase Edge Functions (`supabase/functions/`) so the app never holds raw provider keys. `ClaudeClient.swift` is a dead transport (no call sites) — don't wire new features to it.
- **Persistence** → JSON-on-disk stores in `Services/` (`SessionStore`, `DrillStore`, `ProfileStore`, `PersonaStore`, …), all following the same pattern. Supabase tables exist for auth/voice-clone/subscriptions (`supabase/migrations/`).
- **Billing** → minutes-NATIVE since 2026-08-11 (**pool SHAPE and tier NAMES in this paragraph are superseded by the two bullets below** — daily allowances became monthly pools on 2026-08-20, and Plus's talk pool was removed entirely on 2026-08-21; kept because the metering, the 402s and the idle rule are all still exactly as described) (`20260811160000_minutes_native`, `docs/launch-billing.md`): the unit is **seconds of synthesized talk** — "credit" survives only in table/RPC/field NAMES. `user_credits.balance` = a FREE user's one-time seconds pool (signup grant 3960 s); subscribers have no balance — an entitled `user_subscriptions` row buys `subscription_plans.daily_seconds` per day (Daily `daily_*` 300 s, Unlimited `unlimited_*` 3600 s, resets midnight UTC), enforced by `consume_metered_seconds`. Talk = call time (`talk-tick`) and is the ONLY thing that spends `daily_seconds`. **Idle seconds are not charged since 2026-08-18**: `TalkMeter` polls `isBillable` once a second and only accumulates seconds where the fluent self is speaking, a reply is generating, or the learner's voice was heard within `voiceGraceSeconds` (6 s, wide enough to cover the longest end-of-turn wait) — a screen left open used to bill silence, minutes at a time. The predicate lives in `ConversationView.isBillableMoment` because only the call screen knows what is happening; a meter with none set bills every second, which is the old behaviour. **Watch left the talk meter on 2026-08-14** (`20260814100000_watch_scenes_by_count`): scenes are metered by COUNT against `subscription_plans.daily_scenes` (Daily 2/day, Unlimited 20/day fair-use), claimed once per scene by `begin_scene_play(user, scene_key)` — the client sends ONE key for every line of a scene, so a long scene costs one count and a scene in progress is never cut off. Sharing the pool meant buying "5 min of talk" and getting three on any day with Watch use; a count also costs ~half what the seconds did, since scene audio is on `fidelityModelId` (~2x/char). Everything else is free behind daily caps. Three 402s: `insufficient_credits` → paywall, `daily_cap_reached` (talk) and `scene_cap_reached` (Watch) → NEVER a paywall. **Since 2026-08-18 those two cap alerts split by TIER**: a **Daily** subscriber is offered Unlimited ("keep going today"), an **Unlimited** one is told to come back tomorrow — there is nothing left to sell them, so for that account the answer really is tomorrow. The 402 body carries no tier, so the branch is `AccountStatus.isLightPlan`, resolved client-side (`canUpgradePlan` in `ConversationView` / `WatchView`); both live in their OWN alert, never the error one, because a finished day is not a failure. Keep plan SIZES out of that copy — the client doesn't know Unlimited's numbers and a hardcoded "20 scenes" goes stale silently. **Enrolling extra practice languages is NOT gated** (decided 2026-08-17, after a gate was built and reverted): every pool — `consume_metered_seconds` `(user_id, day, action)`, `record_free_usage` `(user_id, day, purpose)` — is keyed per ACCOUNT with no language in it, so a second language adds zero cost; someone splitting 5 minutes across three languages is spending their own time, and the day's cap is what converts them. Don't put a plan check on `AddLanguageSheet`. **Hard paywall since 2026-08-11** (`20260811180000_hard_paywall_trial`): new signups get a credit row at ZERO — no free pool — so the first talk hits the paywall; the voice clone and the ≤120-char onboarding greeting stay free as the entry ticket. A subscription in `trialing` is metered at the DAILY allowance (300 s/day) whatever plan it trials, so a 7-day Unlimited trial can't burn 60 min/day for free. Existing beta balances are untouched. Don't price anything new in credits, and don't grant on webhook renewals. **The FIRST CALL is free since 2026-09-18** (`20260918100000_first_call_is_free`): the signup grant is 300 s — one conversation, never refilled — because the launch week measured the wall in the wrong place. Of 37 signups, 37 cloned their voice and 36 reached the Talk tab, but only 23 ever started a call; 13 of the 14 who stopped had no subscription row and left within two minutes, having never heard the fluent self answer them. The trial rows said it from the other side: median talk of the people who turned auto-renew off was ~2 min against ~25 min for those who left it on. So the paywall now arrives AFTER that call's summary (`ConversationView.firstCallPitchShown`, asked at most once per install and skipped for an entitled account), and `OnboardingPaywallView` steps aside on its own while the grant is unspent — it already declines to pitch anyone `BillingGate` doesn't block. This is not the old free pool coming back: 300 s buys one call at the measured 3.5-minute mean, and every other free surface is unchanged. **When the pool runs out MID-CALL, the call wraps ITSELF up** (2026-09-18, `handleTalkPoolSpent`): the 300 s are SPOKEN seconds — silence is free (see the idle rule), so on the clock the free call runs 10–18 min (one caller: 23:39→23:57, 288 s billed) — and on its first day the wall raised the error alert and waited for End; a 42-turn first caller never pressed it, so no summary, no book, no pitch (the pitch hangs off the summary sheet's Done), and they left for Watch and never subscribed. Now the gateway HOLDS the wall until the playing line's `audio_end` (`CallSession.wall`, 20 s cap) and the client holds it again until the player drains (`RealtimeTalkClient.heldWall`, 15 s cap) — "sent" is not "heard", and `error` is the client's teardown, which stops the player — then `endSession()` runs by itself with the board's banner saying why, and the summary sheet's Done pitches the plans EVEN IF the pitch was made once (`freeCallSpent`): this time it is the answer to "what now". A wall with no learner turn behind it keeps the old alert; there is nothing to wrap up. **The free seconds are the learner's, not the plan's** (2026-09-25, `20260925120000_free_seconds_are_not_plan_seconds`): a tick paid from `user_credits.balance` no longer writes into `tts_char_pool`, which is the PLAN's meter. Step 1 of `consume_metered_seconds` had always promised that and delivered it for subscribers only — on an account with no subscription row the `select ... into v_entitled, v_trial, v_unlimited, v_cap` finds nothing, PL/pgSQL nulls every target, step 1's `not (v_unlimited and ...)` is NULL and an IF reads NULL as false, so every free second fell through to the unconditional pool insert. Buy a plan the SAME day and `billing_period_start()` is that day, so the pool swallowed them: one learner opened a Plus trial at `seconds_period: 608` of 2,100 and was walled after 1,493 s of trial talk (compensated by hand, `20260924190000`). The insert now carries step 2's own condition, so the row that records a tick and the payer of that tick cannot disagree. Fixing step 1's NULL instead was rejected: it would rename the free tick's `covered_by` from `balance` to `invite_minutes` — the key every free-offer top-up is sized from — and drop step 3's spend-the-pool-to-zero rule.
- **Allowances are MONTHLY POOLS, and the tiers are Light / Plus** (2026-08-20, `20260820180000_monthly_pools_light_and_plus`). Like a mobile data plan: **Light 150 min talk + 30 Watch scenes per billing period, Plus 120 scenes and no talk ceiling** (Plus's scene pool was 600 until `20260823140000_plus_scene_count` — 20 a day, $114/mo of upstream cost against $17 net; its `monthly_seconds` is descriptive since `20260821120000`), and **no daily limit of any kind** — spend the month in one call if you want. `daily_seconds`/`daily_scenes` are DESCRIPTIVE only now (the "5 minutes a day" figure the cards print); `monthly_seconds`/`monthly_scenes` are enforced, counted from `billing_period_start()` — the BILLING period, not the calendar month, because that's the month they paid for. Trial is pro-rated 7/30 so a week's sample can't spend a month. **Light's scenes were 60 until `20260925140000_light_thirty_scenes_new_signups_only`** — 60 of them cost $11.42 against $8.49 of net revenue, so the scene half alone was more than the plan earned. **Nobody who had already bought was moved**: the size a subscription was SOLD is stamped on `user_subscriptions.monthly_scenes` and the plan's own figure applies only where that is NULL, which is everyone new. Every LIVE row was stamped before the catalog moved (a lapsed one was not — coming back later is buying today's plan), so a new trial of either tier now gets 30 × 7/30 = 7 scenes where the two running that day kept 14. Stamp a row the same way before changing any allowance again; halving what a live subscriber bought is the one thing this app does not do. **Four designs shipped and were replaced in one day getting here** (daily-only → a bank of unused days → a rolling 7-day window → this); the bank double-spent idle days by +40% because nothing debited them, and the window was correct but took three migrations and still couldn't be explained in a sentence. **Do not re-derive a daily cap, a bank, or a rolling window.** The old objection to a monthly pool — fill rate, since this tier's margin came from unspent allowance — was retired by the pricing principle, not out-argued. What survives from it: a month-long balance must not become a meter, so the figures live one tap away in Me and the home shows an arc with no digits.
- **Plus has NO talk pool at all** (2026-08-21, `20260821120000_plus_talk_unlimited`). Watch keeps its count on every tier; talking is uncapped on Plus and only on Plus. **The two sides differ for one reason and it is not a compromise: a scene plays itself on a TAP, so an idle afternoon can farm a month of them — and each is billed to us on `fidelityModelId` at ~2x per character — whereas talking costs the learner EFFORT, and nobody speaks for six hours.** Effort is a limiter no ceiling improves on, so the 1,800-minute pool was doing no work while charging us the thing it was meant to protect: a subscriber rationing the one activity the product exists for. `subscription_plans.talk_unlimited` is the switch (a COLUMN, so restoring the ceiling is one `UPDATE`, not a migration); `consume_metered_seconds` gained an entitled-and-uncapped path, because nulling `monthly_seconds` means "no plan" and would have dropped Plus into `charge_credits` against a balance it doesn't have. **The effort argument holds only while the meter charges for SPEECH** — `TalkMeter.isBillable` + `ConversationView.someoneIsTalkingHere()` are what make that true; weaken them and this becomes an open tab. A TRIAL is never uncapped. Usage is still recorded in full, deliberately: no account has ever run without a talk ceiling, so the number can be re-derived from behaviour instead of estimated. **`monthly_seconds` on Plus is now descriptive only** — nothing enforces it, and nothing user-facing prints it.
- **Every plan is a BOUNDED pool, and the tail buys minutes** (2026-09-26, `20260926110000_bounded_plans_and_topups`, founder decision: "Plus unlimited is too much risk"). This supersedes the two bullets above where they say Plus is uncapped. The numbers that forced it: a talk minute costs ~$0.03 all in (ElevenLabs Pro, 145–170 cr/min + Gemini), a scene ~$0.12, net revenue is $8.49 on Light's $9.99 — so Light fully used (150 + 30) cost $8.1 and lost money in Korea/EU, Plus's 120 scenes alone cost $14.4 of its $16.99 net, and one trialer talked 35 min a day, which on an uncapped Plus is −$27/mo on that account. The pricing principle asks what a plan earns when EVERY subscriber uses everything, so: **Light 150 min + 10 scenes at $9.99** (33% at full use — the SCENES paid for the minutes: one scene costs four talk minutes, so 60 → 10 scenes buys back the 150 the plan is bought for; the heaviest Light account ever played four in a month, and a Light learner who hits it has Plus to move to), **Plus 600 min + 30 scenes at $24.99 / ₩29,000** — 20 minutes a day. The USD price was raised on 2026-09-26 (the dollar was the cheapest storefront in real terms, and only 3 of 24 payers are on it against 18 in Korea); **KRW deliberately was not**, because raising it would put Apple's ₩0→정가 consent sheet in front of every Korean subscriber, which is the mechanism that killed the Korean trials. So Plus is +$0.8 fully used in the US and **−$4.4 in Korea**, which the founder chose twice over cutting the pool to 450 min. Bounded (−$80/month if all 18 Korean accounts maxed out) and far away (heaviest paying account projects to 232 min per 30 days). Revisit when a Korean Plus crosses ~450 min in a period — and then by the POOL, not the price. The difference from unlimited is that the worst case is a known four dollars, not $90 at `abuse_seconds`, and **+100 min for $4.99** (`talk_topups`, consumable `com.roro.futurevoice.talk_100`, 29%) in place of "unlimited" — built end to end but **NOT on sale**: two products for now, no ASC consumable, and `TalkTopUpButton` draws nothing without a live price, so the app is a two-subscription app with no code change. The consequence to hold: a Plus learner who empties the pool has nothing to buy and no tier to move to, which is why Plus is the generous side of the pair. Five things to keep: ① **nobody who already bought is touched** — `user_subscriptions.monthly_seconds` / `.talk_unlimited` / `.monthly_scenes` stamp what a row was SOLD, every meter reads the stamp before the plan (`consume_metered_seconds`, `talk_allowance`, `begin_scene_play`, `scene_allowance`), so the Light row from September keeps 150 min + 30 scenes (a row still TRIALING is stamped with the CURRENT plan's figures instead — `20260926130000` — because the stamp outlives the trial and a Light-sized stamp would have converted a Plus trial into a 150-minute Plus). **The three legacy Plus rows are the one deliberate exception to the stamp's own rule** (`20260926140000`, founder's call the same day): uncapped talk is a tail we keep paying for ($90 at `abuse_seconds`), so they were moved to **900 min + 60 scenes** — 3× the new pool, bounded at −$17 worst case, and 8× more than the heaviest of them has ever talked (108 / 93 / 5 min, 0 / 28 / 1 scenes in September), so nothing that would have run now stops. What they DO notice is the screen: a capped row draws the Home ring, says "N of 900 min" and can buy packs. The stamp survives renewals because neither webhook writes those columns — and therefore survives a plan CHANGE too, so a legacy Plus that downgrades to Light would carry 900 minutes onto a $9.99 plan; unfixed with three rows, watch it; the app's `AccountStatus.isUncappedTalk` (entitled + nil cap from `talk_allowance`) is what every "no ring / N min talked / no invite row" rule hangs off now — **never the tier**; `isPlusPlan` says only which size was bought, and the paywall card reads `subscription_plans.talk_unlimited` (in the catalog select since this date; the column has existed since 2026-08-21, so the old deploy-ordering objection no longer applies). ② **A top-up lands in `user_credits.balance`** through `apple-topup` → `apply_talk_topup` (JWS verified with the same chain as `apple-claim`, keyed on the transaction id, and the app FINISHES the consumable only after the server answers — `TalkTopUpService.redeem`, also on `Transaction.updates`, so an offline purchase is retried, never lost). It is spent BEFORE the plan's pool (step 1, as invite minutes always were — the button lives on the spent-pool sheet, so the pool is empty when it is bought) and shows as "+N extra min" (`talk_allowance().bonus` → `bonusSeconds`, which the app had never decoded). `TalkTopUpButton` is the one button (sheet + Usage page); it draws only with a live App Store price, for entitled, counted, non-trial accounts; the free account gets the plans, not a pack. ③ **Plus now has a ring, a fraction and a spent-pool sheet like Light** — the 2026-08-21 "Plus never counts anything down" rule was about an UNCOUNTED pool and applies only to the grandfathered rows. ④ **The annual plans came OFF SALE the same day** (`20260926160000`): at the new pools Light annual is break-even (−$0.4/yr) but **Plus annual is −$137/yr** fully used, and an annual discount cannot be repaired on its own — Plus monthly already loses $4.61, so a discount multiplies a loss, and breaking even would mean listing above 12× monthly. It is a CATALOG flag (`is_active = false`), not an App Store change: the paywall's period picker is data-driven, the Annual segment disappears, and the picker hides itself at one option; the four ASC products stay (a product id is permanent) and one UPDATE brings them back. Nothing live is cut off — every meter joins the plan by id with no `is_active` filter and every live row carries its stamp. Light annual could have stayed on its own numbers, but an Annual tab holding a Plus card with no price is worse than no tab. **It is a PAUSE, not a deletion**: annual comes back at **"2 months free" (10 × monthly — Light $99.99 / ₩150,000 / €99.99, Plus $199.99 / ₩290,000 / €229.99)** once those prices are set in ASC, which `20260926170000` is written and waiting for. That shape fixes Light (+$17/yr) and halves Plus's annual loss (−$137 → −$89) but cannot remove it — no discount can, while Plus monthly is −$4.61; at NO discount the year is still −$55 — so the annual simply follows whatever Plus monthly is re-derived to. Ten months is also the same offer in every storefront, which the old table never was (33/39/25% on Light, 40/40/46% on Plus), and the paywall badge now says "2 months free" whenever the LIVE prices divide that way (`PaywallView.annualSavingLabel`, percentage otherwise). ⑤ App Store Connect is by hand and is the real cut-over: intro offers deleted (done 2026-09-26; verified 0 on all four via the ASC API, the two remaining offer codes are the launch 50%) — no price changes and no consumable; `docs/launch-billing.md` "2026-09-26 revision" has the table and the checklist. The 3-day trial went with it (0 of 20 trials had converted; the paying subscribers had all bought without one; and Korea's ₩0→정가 consent sheet was where four of the last six purchase attempts died), and the free pool went 600 → **1200 s** (`20260926100000_twenty_free_minutes`, `AccountStatus.freeGrantSeconds`) — of 29 signups only the 28% who hit the 10-minute wall ever subscribed, so the runway costs only them, ~$0.1 a signup.
- **Plus never counts anything DOWN** (2026-08-21). A remainder is a monthly receipt for time NOT used; it reads as money wasted and is the likeliest thing to end the subscription. So: no avatar ring on Home (`ConversationHome.headerControl`, and the accessibility label follows it — never announce a gauge that isn't drawn), and Me reports what was SPENT (`AccountStatus.talkTimeLabel` → "55 min talked this month"). Light keeps the fraction, because 150 minutes is a number that account actually meets, and how they spend it — all today or across the month — is their business.
- **Every billing surface is scoped to the BILLING PERIOD, and the three pages quote ONE set of numbers** (2026-08-20). Me → Plan & talk time (`PlanPageView`) is three sections — what's left this month (both allowances in the same fraction shape), the plan and its refill date, then help — and states the refill date exactly once; it used to be six undivided rows saying it three times. **Its receipt was folded INTO it on 2026-09-04** — `UsageDetailView` is gone. That page opened with the same figure the row above it already showed and then re-told the month as three time-scales (period · today · recent days) plus every free surface with a count; two pages quoting each other is how the pair reached eleven rows to say four facts. What survived is the part the rows can't say — WHICH DAYS the talking happened on, capped at 7 (`daysSection`, the window can be 32 days and thirty bars is the same complaint again; the full history is Activity's, which has a calendar to put it on). What was dropped went where it was already written: `CreditGuideView`'s "Always free" section lists every free surface in full, and today's own minutes are on Home and in Activity. `UsageBreakdown.fetch(periodStart:)` sizes its ledger window from `talk_allowance().period_start` and now supplies only the bars. **The headline minutes come from the server's pool figure, never from re-summing the ledger** — the ledger is capped at 8000 rows and truncates the oldest, so a second count of the same month can only drift from the one the meter enforces; the ledger supplies the split, the free rows and the day bars. Both pages render from `DebugCapture.sampleLightAccount` (`-capture plan` / `plan-guide`), one account on purpose: they quote each other, so separate samples would hide the disagreement the captures exist to catch. **A date on any of these surfaces says what will happen to the pool, and `cancel_at_period_end` decides which** (`AccountStatus.cancelAtPeriodEnd`, 2026-09-04): a plan told to stop ENDS on that date rather than refilling, and the app said "Refills on…" to everyone who had cancelled — same date, opposite promise — because the client never read the column. Four surfaces name that date (the plan row, the usage header, the guide's scene footer, `DailyAllowanceSheet`); all four branch on the flag.
- **The paywall card IS the offer, and both cards carry the same four rows** (2026-08-20). Light: `Talking 150 min/mo` (+ `about 5 min a day`) · `Watch scenes 30/mo` · `Your own review book — Unlimited` · `Shadowing · words · replays · drills — Unlimited`, then the price. Plus is identical except its talk row reads **`No limit`** with no figure and no per-day line — there is nothing to print, because nothing is counted (see the bullet above). **Its Watch count stays on the card**: that is a real limit, and hiding a real limit is how you ambush someone. Three rules hold the rest: **same unit on both tiers** (Plus printed "30 hours" beside Light's "150 min" and nobody divides 30 by 2.5 — the reason hours were reached for, that an interpolated `Int` is grouped by the FORMATTING locale so a German "1.800" reads as one point eight in Korean, is handled in `minutesLabel` by grouping in the learner's own language instead); **the period rides on the figure** (`/mo`), which retired a "both refill every billing period" footnote nobody read; and **the free half lives on the card**, not in an "Always free" box underneath — split across two places, the offer had to be assembled by the reader and the free half looked like a consolation prize. The per-day line under Light's talk figure (`about 5 min a day`, from the catalog's own `daily_seconds`, defined as `monthly_seconds / 30`) is a SIZE CUE, never a rule. It is deliberately absent from Plus: the same device that makes a small number feel adequate advertises a daily budget the buyer knows they will never hit, which is the "I'm about to waste money" objection Plus exists to answer. **The card's one prose line describes what the plan LETS YOU DO, never who you are** ("As much as you want, whenever you want" / "Keep it up as a habit") — "for experts / for beginners" promises a feature difference that isn't there and misroutes, since one interview needs ~90 minutes and belongs on Light. And **never restate the size in words** — "talk at length, most days" above a row that already states the size is the meter reading twice and sells nothing. **`isUncappedTalk` reads the TIER, not `subscription_plans.talk_unlimited`**: a `.select()` naming a column the database hasn't got yet fails the WHOLE catalog query, and the paywall then renders with no plans on it — the client must never be one deploy-ordering mistake away from having nothing to sell.
- **"No daily limit" is deleted, everywhere** (2026-08-21). It answers an objection nobody in this app has: no account reading any of these screens has ever had a daily limit, so the sentence denies a rule the reader never knew about. Where the point still needs making, state it POSITIVELY and once ("use them all in one call today, or spread over the month") — a negative restatement of what the numbers already say is noise.
- **Buying and metering are separate rows in Settings** (2026-08-21). `MeTab` opens with **Subscribe / Subscription** on its own, directly under the profile — it is the one control that decides whether the app works at all, and it used to be a button three rows deep inside "Plan & talk time". Below it, **Usage** (`PlanPageView`, titled "Talk time" until 2026-09-12 — wrong, since it reports Watch scenes and the subscription too) reports the month and holds no purchase button. Since 2026-09-12 it also carries a **Subscription** section — since when, the last charge as the store made it, "half price with your launch code until …" when Apple's `offer_type` on the latest transaction is 3, and a link to Apple's manage page. READ only: changing or cancelling is Apple's screen, and an in-app copy could only disagree with it. `subscription_transactions` is owner-readable for this (`20260912100000`); the offer length (12 months) is `AccountStatus.offerCodeMonths`, because Apple's receipt names the offer but not how long it runs.
- **The Home avatar ring is not drawn on Plus** (`ConversationHome.headerControl`, 2026-08-21). An hour a day is a pool that tier will almost never approach, so the arc would sit near-empty all month, and a gauge that never moves is decoration on the one tier that paid its way out of counting. Light subscribers and free accounts keep it; the admin `unlimited` flag keeps it too (that account exists to watch real burn). The accessibility label follows the ring — it must not read out a balance that isn't on screen. Capture both states: `-capture home-light` / `home-plus`.
- **Tier names are keyed, not literal** (`explain(key:default:)`). A string catalog is keyed by the English text, so `explain("Light")` for the PLAN and `explain("Light")` for the APPEARANCE mode shared one row — naming the tier 라이트 renamed the appearance picker from 밝게 to 라이트. `AccountStatus.tierName` is the only place tier names are built; every screen calls it rather than writing the word.
- **Tier names say SIZE and never grade the BUYER.** Daily→Light, Unlimited→Plus, including the internal plan ids (`light_*` / `plus_*`). **The APPLE product ids deliberately stayed `…daily_*` / `…unlimited_*`** (`20260820220000`): four subscriptions were already registered in ASC, and an Apple product id is permanent per app — never renamable, never reusable, not even after removal from sale. Nobody reads a product id; the buyer reads the localized Display Name, which is editable in ASC. `apple_product_id` means "what Apple calls this", never "what this plan is" — don't "fix" the mismatch. "Unlimited" was never true and its ceiling is now printed on the card. The size isn't IN the name because the numbers are still being tuned. Not Light/**Heavy**: `PaywallView` has always held that a label must not tell the buyer what they are. `AccountStatus.tierName` is the one place the names live.
- **Fair use is a line we WATCH, never a wall the learner walks into** (2026-09-04, `20260904130000_fair_use_is_not_a_wall`). Plus is sold as no limit and the card says so, so the spent-allowance sheet — "All 1800 minutes of talk are used up" — is the one sentence that tier must never be shown; it is the promise being broken in the learner's own hands. But "no limit" cannot mean a script may bill us for a thousand hours, so the fair-use figure (`monthly_seconds`, 1,800 min) became a FLAG: crossing it writes `fair_use_flags` and the learner sees NOTHING. A real stop lives far above it (`subscription_plans.abuse_seconds`, 3,000 min = 100 min a day every day) and raises its OWN error — `FAIR_USE_LIMIT` → 402 `fair_use_limit` → an alert that says the account is being checked, never that an allowance ran out. **The enforcement is a person reading the admin console's 이상 사용 table**, which is why the flag exists at all; nothing in the app may render that list. Two things were broken alongside it: prod's `talk_allowance` had never had the unlimited branch (it handed Plus its `monthly_seconds`, so the app printed "1,795 of 1,800 min left" — a pool that tier does not have), and invite minutes were being spent by a plan that cannot run out, destroying a bonus for no gain AND hiding those calls from the month's own figure. `PlanPageView.isUncappedTalk` reads the TIER for exactly this reason — the client must never be one deploy behind the truth about what it sold.
- **A spent day is a SHEET, never an error and never a bare paywall** (`DailyAllowanceSheet`, 2026-08-20). Both walls land there — talk minutes and Watch scenes — though since 2026-08-21 a Plus account can only ever meet the Watch one. It offers the free review first, then Plus only where there is something to sell (`canUpgrade` = `AccountStatus.isLightPlan`; on Plus the upgrade half is ABSENT, not disabled). It replaced two alerts that could state the rule but had nowhere to put the thing to do next. The 402 that raises it is `daily_cap_reached`, split from `insufficient_credits` in ONE place (`ElevenLabsError.wall(body:)`) — the streamed and buffered paths each parsed the body before that, and the streamed one's omission is what told a paying subscriber they were out of credits.
- **Inviting a friend is the THIRD answer to a spent pool, and the only free one** (2026-09-27, `InviteMinutesCard.swift`). The minutes had worked this way since `20260821100000` — `redeem_referral` grants 30 min a side and step 1 of `consume_metered_seconds` spends `user_credits.balance` BEFORE the plan's pool, so a subscriber whose month has run out is talking again the moment a friend joins — and nothing anywhere said so: the invite sat two taps deep in Me → Usage, which is not where anyone is standing when they are stopped mid-call. `InviteOffer.load` is the one gate and each of its three clauses is a way the offer would otherwise be a lie: an ENTITLED account only (a free account's answer is the paywall, and this is the one place a free way round the purchase would cost real money), a COUNTED pool only (`!isUncappedTalk` — step 1 skips the balance on the grandfathered uncapped Plus rows, so there the minutes are granted and never spent), and rewards left (`invitesUsed < rewardedInviteCap`; past 10 the friend still gets theirs but this card promises the LEARNER's). **A TRIAL sees it** (user decision, same day), unlike the pack and the plan move, which both stand down for a trialer — so without it a spent trial's sheet offers nothing but review; the balance is spent during a trial exactly as after one, so nothing about the offer is different there. Two surfaces: a `ShareLink` line in `DailyAllowanceSheet`, drawn LAST and only on a `.talk` wall — an invite cannot resume this call, the friend has to join first, so above the pack or the plan move it would sell a wait as an instant fix, and a scene pool cannot be topped up with talk minutes at all — and `InviteMinutesCard` on Me → Usage, directly under the pool it answers, standing in for the ordinary invite row for as long as `poolIsSpent` (never both: two invitations on one page is the page arguing with itself). The sheet takes the offer as a parameter like every other fact on it; the callers resolve it beside `AccountStatus` so no button grows under the learner's thumb. Captures: `-capture day-spent-invite` / `day-spent-plus` / `plan-spent`.
- **A button with no price may not hold the lead slot** (same day, and this is what a shipped pack would hide again). `packLeads` was `canTopUp && kind == .talk && !isTrial` — the ACCOUNT's shape — while `TalkTopUpButton` draws nothing without a live App Store price, and the consumable is not on sale. So a Plus subscriber who spent the month met a sheet whose primary action was reserved for a button that never appeared: one bordered "Go to Practice" and nothing else, under a line that said "add minutes to keep going now". The button now reports whether it drew anything (`onAvailability`), `packOffered` asks for it, `packLeads` waits for the price, and `nextLine` branches on `packLeads` too — copy and prominence can't name a button the sheet hasn't got. When the pack goes on sale nothing changes: the price arrives and the lead slot is its again.

- **A TRIAL's pool is said before the purchase, and a spent trial is never a paywall** (2026-09-25). A trial is metered at 35 min for the WHOLE trial whatever plan it trials (`consume_metered_seconds`: Light's `monthly_seconds` × 7/30), and until this date nothing said so: the card said "3 days free", the timeline said "talk time on us", and a trialer who talked it out on day one met the MONTH's sheet — "that's this month's talk time", a refill date that was really the conversion date, and a "Move to Plus" button that would have cost money and changed nothing (a Plus trial is capped at the same 35 min). One real trialer tapped through to the paywall three times and left. Now the number rides on every trial surface: the card row `During the trial · 35 min of talk`, the CTA footnote, the timeline's first and last rows, the "You're in" alert, and Me → Usage ("Trial talk time", "150 min a month once your plan starts"). `StoreKitService.trialTalkMinutes` computes it from the SAME catalog row the server uses — keep the formula in step with the migration. `DailyAllowanceSheet(isTrial:planMinutesAfterTrial:)` says the trial's pool is spent, when the plan starts and with how many minutes, offers review only, and never Plus; `AccountStatus.planMonthlySeconds` (a query of its own) is where "150" comes from. Capture: `-capture day-spent-trial`.
- **The paywall is asked BEFORE the spending, at the tap** (2026-08-18, `BillingGate`). A hard paywall met only as a 402 arrives too late to be an answer: the call screen was already up, and on Watch a whole scene had been written and watched being written before the learner was told it wasn't theirs to play. Every metered launcher now runs its action through `BillingGate.start(orShow:)` — the free-talk ring and the widget deep link (one gate, in `RootTabView.startFreeTalk`, where both paths meet), Talk's news/scenario cards, the composer's CTA (`ScenarioComposerSheet.commit`, before the categorize call and before any scenario is minted), Find people's Talk/Watch, and the Talk/Continue buttons on the book pages. Two rules keep it honest: it gates on `AccountStatus.needsSubscription` ONLY — a daily cap is not this, that learner already paid and the client's copy of today's usage is stale often enough to refuse a call the server would allow — and a "no" is never given from cache (a purchase or invite that landed a minute ago must not be paywalled again), while a "yes" always is, so the app's primary button never waits on the network. **A sheet hosting a paid button owns its own `PaywallView`**; a paywall raised by the host underneath never appears. Onboarding offers the plans once at the end (`OnboardingPaywallView`, after the daily-call step, flag on every exit, skipped silently for anyone with nothing to buy) — so the first tap on Talk stops being where the hard paywall introduces itself.
- **`apple-webhook` verifies Apple's JWS BY HAND, and must keep doing so** (2026-08-20). Apple's official `@apple/app-store-server-library` cannot run here: `SignedDataVerifier` validates the certificate chain through `node:crypto`'s `X509Certificate.verify()` / `.checkIssued()`, and the Supabase edge runtime implements **neither** — it throws `Not implemented: crypto.X509Certificate.prototype.verify` with an EMPTY message, so every notification failed identically and silently. The webhook had never once succeeded; it was found the day before launch by a runtime self-test, not by reading the code. The replacement uses `@peculiar/x509` on Web Crypto and does four things in order: read the header's `x5c` chain, verify each link against the next one's public key, require the last to be **byte-identical** to a pinned Apple root, then verify the body with the leaf's key — followed by checking the payload's own `bundleId`/`appAppleId`/`environment`. **Step 2 is not optional**: Apple's root is public, so pinning alone would let anyone append it to their own leaf. The nested `signedTransactionInfo`/`signedRenewalInfo` go through the same path — they carry the product, the price and the `appAccountToken`, so decoding them unverified would make a forgery inside a genuine envelope. Verified end-to-end on 2026-08-20 (Sandbox: `2000001224361429` → `light_monthly`, active).
- **A subscription the app didn't sell still has to reach the server** (2026-09-11, `apple-claim`). The webhook attributes a notification through the `appAccountToken` that only `StoreKitService.purchase()` stamps; an App Store **offer code** redeemed from a link, a restore on a new phone, or a purchase from the store's own page has none, and until this every one of those was logged and dropped — the person paid Apple and the app said "No plan". Now `StoreKitService.claimCurrentEntitlements()` (every foreground, and on each `Transaction.updates` delivery) POSTs the transaction's `jwsRepresentation` to `apple-claim`, which verifies Apple's signature with the SAME chain check as the webhook (`_shared/apple-jws.ts`, moved there for exactly this) and files the row with `apple_original_tx_id`; the webhook's token-less fallback then looks the owner up by that id, so renewals and expiries follow. Rules on the claim side: one original transaction → one account (409 otherwise), a dead transaction never downgrades a live row, and a live Apple transaction DOES replace a comp — redeeming the code is how a beta tester leaves the comp. `PaywallView` has a "Have a code?" button (`AppStore.presentOfferCodeRedeemSheet`), but the mail's redeem link works without it. Half-price launch codes and how they are dealt: `docs/launch-billing.md` §7.
- **A subscription is TWO facts, and the app used to hold only one** (2026-09-18, `20260918100000`). What was charged is a transaction; what will be charged next is `signedRenewalInfo`, which rides on every Apple notification and was decoded for `autoRenewStatus` alone. That gap is visible the moment an offer code is involved: **Apple runs the intro trial first and applies the code from the first RENEWAL**, so for the whole trial week every transaction on file says `offer_type = 1 / FREE_TRIAL`, nothing anywhere mentions the code, and Me → Usage showed the regular price to someone who had just discounted their plan. The first redeemer wrote in the next day asking whether it had worked; three of the first four did the same week. `user_subscriptions` now carries `renewal_offer_type` / `renewal_offer_id` / `renewal_price_milliunits` / `renewal_currency` / `renewal_product_id`, written from renewal info ONLY (a notification without it must never blank a still-true answer), and `AccountStatus.offerCodeUntil` counts the 12 months from the renewal when the code has not started yet. Three rules the surface keeps: the app reads those columns in a **query of their own** — a `.select()` naming a column the database hasn't got fails the WHOLE query, and folding them in beside `plan_id` would show "No plan" to paying subscribers on any build that shipped ahead of the migration; the next-charge row appears only where it is NEWS (a trial, or an amount that is about to CHANGE), because on a steady subscription the figure is already on screen as the last charge and the date as the refill; and the code row sits UNDER the charge it explains. `scripts/apple-subscription.sh <originalTransactionId>` prints Apple's own answer for any subscription — cancelled or not, which storefront, what renews — and is the first thing to run on a billing question, because our tables can only ever agree with themselves.
- **One account can hold TWO live Apple subscriptions** (2026-09-17, same case). Two Apple IDs, or one that changed storefront — a plan change *inside* a subscription group keeps its original transaction id, so a second `apple_original_tx_id` means a genuinely separate subscription. `apple-claim` and `apple-webhook` both keep the row on the one that ends LATER and record the other as a transaction only; before that, a fresh sign-in re-claimed a cancelled-but-still-running trial and buried the subscription the learner was actually on.
- **The update sheet has two audiences** (2026-09-11, `20260911140000_app_release_testflight`). `beta.sh` moves `app_release.latest_testflight_build` on upload; `latest_build` — what an App Store install compares against — moves only with `./scripts/beta.sh released`, which first checks the store's own lookup shows the version. Before the split every App Store user was told about a build the store didn't have yet. **Release notes are part of the build**: `beta.sh` prints `fastlane/metadata/*/release_notes.txt`, refuses the generic placeholder and refuses notes unchanged since the last published row (`FORCE_SAME_NOTES=1` to override), because those files are what the sheet shows AND what App Store Connect gets.
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

### UI text has ONE language: the one the learner picked

Four string catalogs (+ `SWIFT_EMIT_LOC_STRINGS`) hold every UI string, and the build extracts SwiftUI literals into them automatically, so they can't drift from the code: `FutureVoice/Resources/Localizable.xcstrings` (the app), `FutureVoiceWidget/Localizable.xcstrings` (the extension — `StudyWidgetShared.swift` compiles into both targets, so its literals land in BOTH and must be translated identically), and an `InfoPlist.xcstrings` beside each Info.plist (permission alerts and the Home-screen name — OS-drawn, so they follow the DEVICE language; an alert is not our surface).

**Every string the app writes resolves in `LanguageCatalog.currentNative`** — the language chosen in setup, changeable in Me → App language, defaulting to the device's. Tabs, chips, buttons, titles, footers, alerts, onboarding, Settings: all of it. Wired once in `RootView.body` as `.environment(\.locale, UILanguage.chromeLanguage)`, so every `Text("literal")` follows with **no per-call code**. `chromeLanguage` and `explanationLanguage` now return the same thing.

**This replaced "chrome follows the TARGET language" on 2026-08-17**, and the rationale is worth keeping because it was a good argument that was still wrong. The claim was that a tab bar seen a hundred times a day beside an icon is free A1 vocabulary at no comprehension cost. It only holds if the words are incidental, and they aren't — the target audience is Korean speakers learning English *and German*, so the rule handed a Korean learner a German app, and even the English case put every control of the product in a language the learner is by definition still learning. Exposure belongs in MATERIAL, which is where it still is (scene lines, drill cards, expressions, corrections — see "Two languages" above; that split is untouched). Do not re-derive the old rule from the icon argument.

**The pixel display face must carry every UI language's script.** `UIFont.appPixel` cascades Geist Pixel → a bundled Galmuri14 SUBSET (`Resources/Fonts/.galmuri-subset.txt` lists exactly what is in it); a script missing from the subset drops titles to the system font mid-line, which is how Japanese looked until 2026-09-12. The subset now holds Latin + Hangul + all kana + the kanji the ja catalog actually uses; when a new UI language lands, or new kanji enter the ja column, regenerate with `pyftsubset` from the upstream Galmuri release (`--text-file` = that list, `--name-IDs='*'` so the PostScript name the cascade looks up survives).

**One line on the Talk tab is NOT chrome: the greeting above the ring** (`HeroGreeting`, 2026-09-15). It is the fluent self speaking, so it is MATERIAL and resolves in the TARGET language through `material(…)` (`UILanguage.swift`), following the language switcher the moment it moves. It rode along with `chrome()` when chrome moved to the app language and spent a month as the app's voice, reported as "the line above the ring doesn't change when I switch languages". Any future on-screen line the fluent self says goes through `material`, never `chrome`.

Two things survive the collapse and still matter:

- **`explain(…)` / `chrome(…)` are how a `String` gets localized at all.** `Text("literal")` follows the environment locale; a `String` never sees it. So any literal that flows through a `String` first — a computed nav title, a `switch` returning a label, a function parameter — has to go through one of them or it is frozen English in every language. This is not a style rule: `MeTab.row(icon:title:subtitle:)` takes `String`, and ~35 settings rows sat untranslated behind it until 2026-08-17, as did most of onboarding until 2026-08-16. The two helpers are now interchangeable; prefer `explain(…)` for new code.
- **Never write a bare `String(localized:)`.** It resolves against the main bundle and the SYSTEM locale, so it follows the phone's language instead of the learner's.

**Widgets and the `String(localized:)` ban.** The one sanctioned exception is `StudyWidgetSection.displayName` / `.galleryDescription`, which are drawn by iOS in the Add Widget sheet. Inside the widget extension the app-side helpers don't exist: `Text("literal")` follows `\.locale` (set to `.widgetChrome` at each widget's root) and `String`-typed labels go through `widgetChrome(…)`, both reading `StudyWidgetSnapshotStore.chromeLanguage` — the app language, mirrored into the App Group by `StudyWidgetRefresher` because an extension can't read the app's defaults. Anything the widget shows that is DATA (a book's subtitle) has to be resolved app-side at write time; the extension can only draw it.

**Refreshing the catalog:** a plain `xcodebuild build` does NOT write newly-added strings back into `Localizable.xcstrings` — it only compiles what's already there. Run `xcodebuild -exportLocalizations -localizationPath <tmp> -exportLanguage ko` to merge new keys in, then translate them. Skipping this is why a string can look wired up and still be missing from the catalog.

Nothing here names a language. Adding German is a `de` column in the catalogs plus its code in `project.yml`'s `knownRegions` — no other code change.

**Chinese is listed BY SCRIPT, and that took real code** (2026-09-13, `zh-Hant` + `zh-Hans`). Traditional (Taiwan/HK/Macau) and Simplified are different vocabularies, not just different glyphs, and every Foundation API resolves a bare `zh` to Simplified — so `nativeLanguages` now carries `zh-Hant`/`zh-Hans` and `LanguageCatalog` gained the four helpers that a script-qualified code needs: `normalizedNative` (a stored bare `zh` from before this migrates to `zh-Hans`), `nativeCode(matching:)` (device locale → the list entry, keeping the script), `sameLanguage` (target/native collision checks that used `==` and would have let `zh-Hant` sit opposite `zh`), and `name(_:in:)` — `localizedString(forLanguageCode:)` DROPS the script, so both scripts came back as plain 中文 / "Chinese"; every on-screen language name goes through `name`, and `englishName` spells out "Traditional Chinese" so a prompt can't quietly write Simplified. `translatedLanguages` now matches `Bundle.main.localizations` verbatim (a `.lproj` is called `zh-Hant`, never `zh`), and `sttLocale` maps the scripts to `zh-TW` / `zh-CN`. **Both Chinese columns ship.** `zh-Hant` was written first (Taiwanese Mandarin) and `zh-Hans` was DERIVED from it, which is the honest record: OpenCC `tw2sp` for script + idiom, then a review pass that fixed ~255 keys the converter got wrong or left Taiwanese. Three classes of error, and they recur if this is ever redone — **domain words the converter destroys** (核心, the club, became 内核 "kernel"; 登出 became 注销, which in the mainland reads as DELETE ACCOUNT; 複製 became 拷贝 where a voice clone is 克隆), **Taiwan terms it doesn't know are Taiwan terms** (單字→单词, 字彙→词汇, 文法→语法, 程度→水平 for proficiency but NOT for 私密程度/認真的程度, 口說→口语, 分頁→页, 畫面→界面, 回饋→反馈, 音檔→音频), and **dated jargon it prefers** (預設→缺省 instead of 默认). Verify with OpenCC in both directions: no character may survive `s2t`, and every word-level substitution the converter made should be eyeballed (diff against a `t2s` character-only conversion to isolate them). ICP filing is about listing the app in the mainland App Store — a separate, later business decision — and was never a reason to withhold the language; Simplified readers are in Singapore, Malaysia and everywhere Chinese people live abroad.


**One badge, two words — the failure mode of chunked translation** (2026-09-13). `BookCards` renders `"Mastered"` OR `"%lld/%lld mastered"` in the SAME pill, and because the two keys land in different chunks of the extract, all five languages added in 2026-09 translated them with different words: 完了/習得, 完成/已掌握, Terminé/maîtrisés, Completado/dominados. Korean was the only consistent column (완료/완료) because it was written by hand in one pass. All four counter keys now match their own short label. **When a language is added, diff the keys that share a call site** — a per-key validator can't see it, and neither can a reader of one chunk. The same applies across CATALOGS: the four literals in `Shared/StudyWidgetShared.swift` extract into BOTH `Localizable.xcstrings` files and render through one view, so their values must be byte-identical (`mastered`, `left`, `Done for today`, `Nothing in progress` had drifted in fr/es/zh). A key that merely happens to appear in both files — the widget gallery's `Streak`, say — is a different surface and may legitimately differ.
**The pixel display face gives up on a script it can't spell.** `UILanguage.pixelFaceCoversChrome` is false for Chinese, and BOTH pixel entry points check it — `Font.geistPixel` and `RootView.roundedNavFont`, which is UIKit's nav-bar path and does NOT go through the SwiftUI Font (that's how the first fix half-worked). Galmuri is a Hanja font, so it has thousands of CJK ideographs but not the Traditional forms of common ones (說, 錄, 每 are missing while 説, 録, 毎 are present), and a missing glyph falls back PER CHARACTER — a title half pixel, half SF. Whole-title system font is the lesser evil. `DayCardView` uses `brandPixel` instead, because the day card is pinned to English. `Localizable.xcstrings` is fully translated for **ko** (verified 2026-08-17, 1302 keys, zero gaps) and **es** (2026-09-13 — ONE neutral column for Spain, Latin America and US Hispanics, which is a real constraint and not a shrug: **tú** throughout, never usted/vos, never **vosotros**, and never the verb **coger** (vulgar across most of Latin America — "contestar la llamada", never "coger"). Region-locked nouns are avoided rather than picked: **teléfono** (not móvil/celular), **auriculares**, **la app**, and "un coche estacionado" because both halves travel. Apple's own `es` terms carry the OS-facing words — **Ajustes**, **Toca**, **Cuenta de Apple**. Glossary: Talk→Hablar, Watch→Escenas, Progress→Progreso, Me→Mi perfil, fluent self→tu yo fluido, Streak→Racha, books→cuadernos but the word notebook→libreta, Got it (a sentence)→Memorizado vs Known (a word)→Ya lo sé. Spanish runs 20–25% longer than English, so labels were cut rather than crammed) and **ja** (2026-09-12, every key in all four catalogs — drafted from the ko column as the tone reference, with a fixed glossary: Talk→トーク, Watch→シーン練習, Progress→成長, fluent self→流暢な自分; chrome in です・ます, the fluent self's own lines in タメ口, never あなた; second pass 2026-09-12 rewrote ~150 lines as Japanese product copy rather than translation: no mid-sentence “—” (Japanese uses 。/、/·), sentence “Got it” = 覚えた vs word/phrase “Known” = 知ってる, appearance modes use iOS's own ライト/ダーク/システム設定, plural-suffix `%2$@` args dropped the way ko drops them — still not read by a native speaker); **zh-Hant** (2026-09-13, same pipeline and the same second review pass — Taiwanese Mandarin, not a Simplified conversion: 軟體/影片 vocabulary, 點一下 not 点击, verified character-by-character with OpenCC so not one Simplified glyph ships); **fr** (2026-09-13, same pipeline, read line by line afterwards — **tu** throughout, never vous, because the fluent self IS the learner; apostrophes are always the typographic ’ and every « »,  :,  ?,  ! carries a NO-BREAK SPACE (184 lines were normalized); glossary Talk→Parler, Watch→Scènes, Practice→Pratique, Progress→Progression, Me→Mon profil, fluent self→ton moi fluide, books→carnets, Settings→Réglages, Unlimited→Illimité — « Passer à Plus » for "Go Unlimited" named the wrong tier and was caught in that read-through); **de** (2026-09-28, its last 736 keys — the column had drifted to 894 missing as other languages were added; **du** throughout like tu/tú, glossary Talk→Sprechen, Watch→Ansehen, Practice→Üben, Progress→Fortschritt, Me→Ich, fluent self→dein fließendes Ich, books→Buch, notebook→Vokabelheft/Wendungsheft, plan→Tarif, subscription→Abo, Got it→Kann ich vs I know→Weiß ich, " – " never "—", „…“ quotes), so `LanguageCatalog.partialUILanguages` is empty again. Keep that set for the next column that is filled in stages; never widen `translatedLanguages` to mean "has a `.lproj`" again. Verify with a re-export: extracted count == repo count, and no entry missing a language unless it carries `shouldTranslate: false`, which marks punctuation, format shells and dev samples. One gap remains: outside Settings and onboarding, most explanatory strings are still unwrapped, so they read as chrome. Literals that flow through a `String` variable (`source = "Free talk"`) still neither extract nor localize until they go through `chrome(…)`/`explain(…)`.

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
- Conversation turns: structured JSON, **streamed** via `sendJSONStream` (`stream: true` → the `gemini` Edge Function proxies `streamGenerateContent?alt=sse`). Field order is load-bearing — `{reply, suggestion}`, reply FIRST. Don't put a field before `reply` and don't reorder the prompt's schema line. `onEarlyField` fires up to **twice** for `reply`: once with its first complete sentence (`isComplete: false`, ≥25 chars, terminator + whitespace — `GeminiClient.firstSpeakableSentence`) and once at its closing quote. The opening sentence goes to TTS immediately and the remainder is fed into the SAME open PCM stream (`beginSplitSpeech` / `finishSplitSpeech`), so the model's remaining writing time overlaps the TTS round-trip. Every failure in that pair degrades to speaking the whole reply once. Analysis calls (shadow bullets, weekly report) stay on buffered `sendJSON`. **The summary is the one exception** (`sendJSONStreamAccumulating`, 2026-08-19) and NOT for latency — nothing there can be used before the payload closes, and the decoded result is identical. It streams so the wrap-up board can move while the model writes; **its schema field order is therefore load-bearing too** (`SessionSummarizer.Progress.absorb` reads which section is finished from which key has appeared next). Reordering the summary schema misreports a step, never a number. Temperature args still exist on the API for 2.5-era callers but are ignored on gen-3.
- TTS: **speaker similarity is the product** — the user must believe the voice is theirs. Model choice ranks `eleven_multilingual_v2` > `eleven_turbo_v2_5` > `eleven_flash_v2_5` on similarity, and exactly the reverse on latency. Defaults:
  - **Everything is `eleven_turbo_v2_5` since 2026-09-26.** Talk turns always were (`conversationModelId`, and the gateway's own `CONVERSATION_MODEL`); Watch scenes (the clone's lines), the daily-call voicemail, the onboarding greeting and the voice-comparison sheet moved onto it that day (`ElevenLabsClient.cloneModelId`). Flash was tried on turns and reverted: same price, less like the user.
  - **Why the fidelity tier lost.** `eleven_multilingual_v2` bills 2x per character and was on the clone's scene lines — 70% of a scene's bill (26,514 credits against the counterpart's 11,354 over the launch window) for half the lines. The founder A/B'd both models on their own clone (`scripts/tts-model-probe.sh`, production voice settings and speed, weighted to the cross-lingual case that is the only place 2x should show) and turbo held up, in places sounding BETTER. A scene went $0.112 → ~$0.073. The argument that retired it is one sentence: **Talk runs the same cloned voice on turbo and always has, so nothing can need a better model than the live call.** The once-per-user surfaces followed for a different reason — a greeting on a better model than every line after it is a demo, and the gap it hides is the disappointment it sets up.
  - `fidelityModelId` stays defined but **nothing in a release build speaks on it**; it is the DEBUG A/B target. The old rule ("only where `PhraseAudioStore` caches it") was already broken by `freshTake`, which writes new text every run — the rule is now "only where it fires once per user, ever", and today nothing qualifies.
  - `fidelityModelId` bills ~2x per character upstream while `priceFor("tts")` in the edge function is model-BLIND, so that 2x was pure margin absorbed. Before putting any path back on it, re-run `scripts/tts-model-probe.sh` and hear the difference first.
  - Voice settings are fixed server-side in `supabase/functions/elevenlabs-tts/`. `style` MUST stay `0` — any style exaggeration pulls the output away from the reference speaker.
  - **The level changes WHICH WORDS, not HOW MUCH** (2026-08-20, `ConversationEngine.SpeechScale`). Turn length used to scale with the band (2 sentences at A1, 4 at C1); it now stops at 3 for everyone and says one thing — this is a phone call, nobody monologues. A learner doesn't need shorter turns than a fluent speaker gets, they need easier ones, so the band drives vocabulary + sentence SHAPES and nothing else. The old ceiling made replies stop mid-thought and pushed the model to satisfy the count by writing longer sentences, which is how a rule meant to keep the call spoken made it read written. Keep the ceiling COUNTABLE though — the qualitative version lost to the concrete REACT/VARY bullets and an A1 turn came back at four sentences.
  - **A SCENE is the same size at every level too** (2026-09-26, user
    decision — `ScenarioCurriculumEngine.sceneTurnRange` / `sceneTurnStyle`).
    The same rule as the turn ceiling above, arrived at two ways. It USED to
    scale: 8–10 turns of one 5–10 word sentence at A1/A2 up to 10–14 turns of
    1–3 full sentences at C1/C2 — and it read wrong in both directions (an A2
    scene too thin to hold the situation, a C1 scene too long to sit
    through), AND length is where a scene's cost lives. Measured on two real
    watches the same afternoon: 8 lines for $0.090 against 9 lines for
    $0.401 — ONE more line and 4.4x the ElevenLabs bill, so one scene from
    the plan's pool meant four different things depending on who played it
    and `docs/launch-billing.md`'s $0.12-per-scene arithmetic was four times
    under at the top band. Now: **9–11 turns of 1–2 sentences for everyone**,
    and the band is read from `ConversationEngine.speechScale` rather than
    restated, so a band means ONE thing across the call and the scene. Two
    things follow. **Substance is NOT band-dependent** — the prompt's
    SUBSTANCE rule asks every level for the complication and the hard
    question ("a beginner's scene is not a thinner scene, it is the same
    situation in easier words"), because the A2 complaint was about
    substance and stripping length must not take that with it. And
    `LevelHeader` may no longer promise a per-band size on EITHER surface.
  - **Punctuation is the breath** (2026-09-15, rewritten 2026-09-16, `CoachingLanguage.breathPunctuation`). Reported as "when it speaks Korean it reads without breathing". Measured on both TTS models and on the gateway's per-sentence path: the synthesizer pauses at punctuation and nowhere else — a Korean turn with no commas got ~1.1 s of internal pause in 12 s, the same text with a comma at each clause boundary ~1.7 s, and the gap BETWEEN sentences was ~400 ms on every path, so the text never asked. `speed: 0.9` slowed the words and REDUCED the pauses — wrong axis. **The first wording ("a comma between two clauses") made the model end finished sentences on a comma** ("나 방금 너랑 비슷한 사람 봤다, 어찌나 반갑던지, 뭐 하고 지내?"), which keeps the voice suspended on a sentence that is over — 10 of 18 opener lines against 2–6 with no rule. It is now stated as INTONATION: a period finishes, a comma hangs, a comma only after an ending that leaves the sentence open (~는데/~서/~니까/~고/~던지/~면), never after a sentence-final ending (0 wrong commas on both models after the rewrite). Don't delete it to fix choppiness — that brings the breathless reading back. It also carries the other half of the fix: **don't stack three short sentences** — two clauses that are one thought (a reason and what it led to) join with a connective and a comma, which is the take the learner picked by ear from four synthesized voicemails. That is not a licence to merge past the turn ceiling; over it, an idea is still dropped. The older choppiness (short lines on an English skeleton, "지금 괜찮아? 목소리 듣고 싶어서.", in ElevenLabs history since August) is a separate problem this rule doesn't address.
  - **The pause BETWEEN sentences is the generation boundary** (2026-09-30, `CallSession.eachSentence`). Reported: "it doesn't stop between sentences, especially in Korean". The "~400 ms on every path" above held only when each sentence was its OWN auto_mode message — measured on the founder's clone in ko/en/ja/de, sentences sent in one message come out 0.08–0.29 s apart (one English take had none), one sentence per message 0.35–0.50 s. The gateway had been joining every complete sentence in the buffer into one message, and the model burst-writes, so most turns went out whole. It now sends one sentence per message (founder's pick by ear over the same plus 0.25 s of inserted silence; files in `~/Desktop/beta audio/sentence-gap-probe/`), and the splitter cuts at CJK 。！？ without a following space (no Japanese reply was cut mid-stream before) but not after "Mr."/"z.B." or a quote closed by と/って. `<break>` tags are out: two 0.35 s breaks added ~3 s, broken with noise. The call's cached opener and the voicemail follow the same day (`PacedSpeech`): over HTTP, splitting alone does NOT reproduce it (`previous_text`/`next_text` glue the pieces back to 0.09–0.24 s, and without them each clip carries 0–0.43 s of its own edge silence), so each sentence is synthesized as PCM, its INNER edges trimmed to the voice, and a fixed 0.42 s goes between — measured 0.38–0.42 s in all four languages. New audio only; openers already on phones keep playing as made until the next speed re-bake. Still whole-line: Watch lines (1–2 sentences, prosody-conditioned) and the HTTP talk fallback.
  - **The learner sets the SPEED, and the default is 0.9** (2026-09-23, `SpeechSpeed`, Me → Voice). `voice_settings.speed` (0.7–1.2) was never sent by anything here; it now rides on every synthesis — the three `ElevenLabsClient` bodies, the `elevenlabs-tts` edge function (clamped, out-of-range means no preference) and the gateway's `start` → `ElevenTTS` context settings. It is SYNTHESIS, not playback: the pitch is untouched, so a slowed line still sounds like the learner, and the word timings come back measured against the audio that was actually made, so karaoke and the rhythm grade need no adjustment. Three rungs, **Normal 1.0 · Relaxed 0.9 (default) · Slow 0.8** (보통 · 여유있게 · 천천히 — the middle one is the default and is deliberately not called "slower"): 0.9 was chosen by ear against the production settings as the most natural reading in English and Korean, so it is what everyone gets; 1.0 is the clone at the speed it was recorded, kept because the learner asked for it and labelled Normal, never "fast" — nothing on this control speeds the voice up. Each step is ~12% by `scripts/tts-speed-probe.sh` (five lines, two languages; 0.9 = +13% over 1.0, 0.8 = +27%), while **0.95 is +3.3%, which is INSIDE the synthesizer's take-to-take variance** — two of five lines came back shorter than the un-slowed take. That number is the rule for adding a rung: a rung the learner cannot reliably hear teaches them the control is fake. Nothing below 0.8 has been listened to, so nothing below 0.8 ships. **Audio already produced is never touched** (user decision, same day, after a one-time cache clear was built and reverted): the DEFAULT rung's cache tag is EMPTY, so every `PhraseAudioStore` line made before the setting existed — synthesized with no speed at all — is still found and still plays; a learner who never touches the setting hears old cached lines as they were and new ones at 0.9, a 13% gap accepted over re-billing a whole library. A rung the learner picks on purpose, Normal included, gets its own key — the empty tag cannot tell an old 1.0 line from a new 0.9 one, so it belongs to the default alone. This is the same rule the store has always had for a re-cloned voice, and it holds for any future key change too — never orphan, never prune. **The DEFAULT is tunable from the server** (2026-09-24, `app_release.default_speech_speed`, `scripts/speech-speed.sh`, build 58+): 0.9 was chosen by ear on five probe lines before anyone had lived with it, and a knob added after the setting spreads can only reach the installs that come later — so it went in the day after. `AppUpdateService.check()` mirrors the column into defaults once per launch, BEFORE its own version guards (they stop for reasons about this build, none of which is a reason to ignore a retuned speed), and the mirrored value is read from disk so a launch with no network is a day behind rather than snapped back. NULL means the app's own default — the column is written only to CHANGE the number, so an untouched row can't drift from the code — and a value outside 0.7–1.2 is DROPPED, not clamped, because guessing which edge a typo meant is how it becomes a voice nobody recognises. Only the default rung moves; Normal and Slow are the ladder's ends and stay in the build, where ears can be put on them first. Cached audio is untouched by construction: that rung's cache tag is empty — with ONE exception, the free-talk openers (`FreeTalkOpeners.needsBake`, 2026-09-25). Those are the handful of lines that OPEN a call, and keeping them meant a learner with warm opener audio heard the greeting at the old speed and every answer after it at the new one, on every call, for as long as the pool text held — the first thing a call says is the worst place for that seam. They are re-made whenever the speed moves, recorded per LINE (the pool is per language and per persona name, and the intro and fallback lines are warmed from another path, so a language-wide flag would leave the rest stale). Don't widen the exception: everything else in the library is heard on its own, where 13% is nobody's complaint. The voicemail's character budget (`VoicemailEngine.maxScriptCharacters`) scales with the speed, or the 29 s hard cut would take the closing question off a Slowest voicemail. The same probe retired this list's own note that `speed: 0.9` eats the pauses: across five lines the silence holds or grows (0.69 s → 0.98 s per 10 s of audio), so the breath rule above is what buys breaths and the speed setting does not spend them.
  - **The rung is CHOSEN in onboarding, on the meet act, by ear** (2026-09-27,
    user decision — Option A of two mockups, the other being a step of its
    own). The ladder shipped with a picker in Me → Voice and nothing to
    listen to, so the rung was picked by reading three words and almost
    nobody picked at all. Now the Meet screen carries three pills under the
    colour row: a tap SELECTS the rung and SPEAKS it, so re-tapping the
    selected one replays rather than doing nothing. The sound rules of that
    screen, in full: the greeting plays ONCE on arrival at the default rung,
    a colour tap is SILENT (it used to replay the greeting "so the choice is
    felt", which meant the clone's first words up to six times), the big orb
    replays the greeting on tap (the one replay there is, captioned because
    an affordance nothing points at is not one), and the pills are the only
    other thing that speaks. **What they speak is `VoiceCloneScript.paceSample`,
    never the greeting and never the first call's opener** — measured: the
    greeting is 6 s and ends on a question already answered, the opener is
    190 characters in English (12 s a take, over the free gate), and three
    takes of a SHORT line cannot be told apart at all — at 24 Korean
    characters the 0.9 takes ran 2.38–2.92 s against 1.0's 2.42–2.50, i.e. a
    Relaxed take measurably FASTER than every Normal one, which is exactly
    what the founder heard. The line is sized so every rung is strictly
    ordered (~4.5 s; 4.36–4.63 / 4.74–5.05 / 5.27–5.80 over three takes
    each). **The takes are LAZY**: nothing is synthesized until a pill is
    tapped, and the first tap buys the other two — free to the learner
    (`purpose: "greeting"`, ≤120 chars) but ~1.4¢ (ko) to 3.3¢ (en) of
    upstream cost per signup if all three are made, which is not worth
    spending on a learner who keeps the default. Same pass, the bigger
    saving: `AppState.warmFreeTalkOpeners` now WAITS for the meet act
    (`holdVoiceOnboarding`) and runs from `finishMeet`, because baking the
    opener pool at the default and then having the learner pick Slow made
    `needsBake` delete and re-synthesize every one of those lines on the
    first Talk visit — the same lines paid for twice.


## Audio format

16kHz mono PCM WAV for recordings. Whisper and ElevenLabs both accept this. Don't change it without checking both providers' docs.
