# Future Voice — Claude Code Context

> Read this before making changes. `docs/SPEC.md` has the original concept but is STALE (still says Phase 1) — this file and the code are the truth.

## What this app is

iOS SwiftUI app. A user clones their own voice once (ElevenLabs), then practices a target language by talking with a "fluent self" — same voice, fluent output. Gemini is the conversation brain and analyzer; ElevenLabs synthesizes every fluent-self line in the user's cloned voice.

**Current state (2026-06): four-tab app in TestFlight prep, NOT a Phase-1 spike.**

Tab order: **Talk · Watch · Practice · Progress** (`RootTabView`) — do → create → review → measure.

- **Talk** (`ConversationHome`) — the speaking launcher, one tap to start the call. A List: Today status (minutes/goal, streak, talks → ActivityView), Free talk, **Scenarios** (header "+" → builder), **In the news** (`NewsTopicSection`, refresh + interests in its header). Every row tap launches `ConversationView` phone-call-mode conversation (live STT → Gemini structured turn `{reply, suggestion}` → cloned-voice TTS, auto VAD turn-taking; per-turn suggestions as inline chips). `MeTab` opens from this tab's header.
- **Watch** (`WatchTab`) — simulate a specific situation BEFORE it happens and mine ideas (how the fluent self handles it, which expressions it uses). Three entries, all landing in the `SituationComposerSheet` bottom sheet: ① a stories-style People row (tap a persona → composer scoped to them, with relationship-grounded ideas from `TopicEngine.suggestForCounterpart`, cached on the counterpart), ② "Make your own situation" — the DEFAULT: describe the real upcoming thing in a blank composer (no person needed; empty `Scenario.role` makes the scene infer its own counterpart), ③ "Likely situations" — a drill-down chain (cafe → ordering → order came out wrong) whose leaves prefill the composer, always editable. **Watch** mints the `Scenario` and plays its scene in `SceneWatchView` (`ScenarioCurriculumEngine` — the same generation stocks the book Practice reviews). A saved `Scenario` is a reusable TEMPLATE: tapping it under "Your scenarios" writes a FRESH take every time (`SceneWatchView(freshTake:)` — per-run idempotency key, previous titles passed as `avoidTitles`), and the new take is `absorb`ed into the scenario's book — latest scene replaces the old, study items accumulate, mastery survives. Replaying past material is Practice's job, never Watch's. No browsing here; books live in Practice. The People row's last bubble is **Find people** (`FindPeopleSheet`) — see below.
- **Practice** (`PracticeTab`) — the REVIEW home; everything here came out of an activity. Three layers: today's cross-cutting SRS queue (`DrillStore` Leitner boxes 0–5 + shadow picks), the **Books** shelves behind chips (**Talks · Topics · Scenarios**), and the Library dictionaries (vocabulary / expressions / shadowing). Every book has the same anatomy — one scene + words/lines to master, then archive. Watch books = `Scenario` + `ScenarioCurriculum` (`ScenarioDetailView`; scene behind its Watch button). Talk books = a finished `Session` whose material is DERIVED by `TalkCurriculum` (fluent-self pickup words + corrected lines as shadow material, mastery via `VocabStore`/shadow attempts — never persisted); their page is `ConversationDetailView` (Continue / Replay; raw transcript + sequential audio replay behind Replay in `TalkTranscriptView`). **Either book exports** from its ⋯ menu (`BookExportMenu` → `BookExport.swift`): both types flatten into ONE `BookDocument`, rendered as an A4 PDF (annotate on an iPad, or print) or Markdown (paste into a notes app). The PDF goes through `UIMarkupTextPrintFormatter` + `UIPrintPageRenderer` because it's the only thing on iOS that flows arbitrary-length text across pages without hand-rolled CoreText pagination — which is why the document is authored as HTML. Add a field to `BookDocument` and BOTH renderers pick it up; never render a book straight to a format.
- **Progress** (`ProgressTab`) — measured CEFR estimate + per-skill pages behind swipeable chip tabs, plus the activity/effort panel (14-day rep bars).
- **Home-screen widgets** (`FutureVoiceWidget` target) — TWO widgets in one bundle, one per `StudyWidgetSection`: a **Vocabulary** widget (notebook `studying` words + recent used, CEFR tag, taps `futurevoice://vocab`) and an **Expressions** widget (`VocabStore.expressionEntries()`, taps `futurevoice://expressions`). Both are list widgets whose window slides every 30 min. App-side `StudyWidgetRefresher` writes a per-section snapshot into the App Group on every `DrillStore`/`VocabStore` write and at scene-phase edges; the extension only reads. App-side `StudyWidgetRefresher` writes a snapshot into the App Group (`group.com.roro.futurevoice`) on every `DrillStore`/`VocabStore.studying` write and at scene-phase edges; the extension only reads. The shared contract `FutureVoice/Shared/StudyWidgetShared.swift` compiles into BOTH targets — keep it free of Models.swift/store imports. Widget tap deep-links `futurevoice://practice` (handled in `RootTabView`). The widgets speak the app language, not the phone's — see "UI text has ONE language" below.

## Find people (shared persona pool)

Watch's People row is your OWN people. The last bubble, **Find**, opens `FindPeopleSheet` — strangers you can practice with, like meeting someone at a language school. Rows come from the Supabase table `public_personas`, read anonymously, written only by their owner (RLS).

- A row is either **curated** (`owner_user_id` null — seeded by migration, deliberately diverse in job/place/register) or a **real user's** self-introduction. Same pool, same shape; the pool self-mixes as users join.
- The user's own row is auto-published from their onboarding `UserPersona` at app start (`PublicPersonaService.autoSyncMyPersona`) so existing users appear without doing anything. Editing or taking it down by hand in Me → Find people sets `manualIntroKey`, after which auto-sync never touches that row again — an explicit choice always wins. Your own row is filtered out of your own pool.
- A remote persona materializes as a normal `Counterpart` with `remoteId` set (`asCounterpart`). `remoteId != nil` is what keeps strangers OUT of the Watch stories row and the People sheet — they live in the Find sheet's "People you've met" instead, so the row never crowds out people you actually know.
- **Talk** starts a normal `ConversationView` call with `initialCounterpart:`. Two things change and nothing else: `ConversationEngine`'s `YOUR CHARACTER` block casts the model AS that person (it outranks ROLE/SCENE inference and the future-self framing, and carries the same context-not-instructions + language guard as the Watch engines), and `activeVoiceId` uses the persona's **preset** voice. Their voice is never a clone — the person on the other end is a stranger, not the fluent self.
- The talk saves as an ordinary `Session` with `counterpartId`, so its review material, transcript and Practice book all come from the existing machinery for free. The person's card lists every talk you've had with them.
- Bookmarks are local only (`UserDefaults`). Nothing a learner does here reaches the persona's author: no notification, no shared record.

Intros are MATERIAL, so they're written in the target language — a persona row serves one `language` and the pool is fetched per `AppState.targetLanguage`. Publishing is gated on intro density (80 chars), not on a privacy toggle: a one-liner can't carry a conversation, and the same bar keeps thin rows out of the pool.

## The daily call (habit anchor)

Nobody opens a language app because a streak asks them to; they answer a phone that rings. Korean 전화영어 runs on exactly that, and its biggest churn reason is the embarrassment of stumbling in front of a stranger — here the caller IS the learner, so only the schedule's pull is left. Opt-in in Me → Call (`DailyCallStore.isEnabled`, default 08:00).

**A third-party app cannot render an incoming-call SCREEN.** iOS gives that to CallKit alone, and CallKit needs a server-sent VoIP push for a real person-to-person call — Apple rejects it for anything else. This was tried and abandoned; don't re-litigate it. The "someone is calling me" feeling is therefore built from **behaviour, not chrome** — the caller has a memory, and an unanswered call leaves a trace.

- **What rings** (`DailyCallAlarm`, iOS 26.1+): an AlarmKit alert, because it's the only thing that rings **through silent mode and Focus** with its buttons visible without a long press. It is an alarm screen and will always look like one. Notification path is the fallback (older OS, alarms refused); `DailyCallScheduler.schedule` tries alarm first, `cancelPendingRequest` clears BOTH or the learner gets called twice.
- **The ring is a bundled phone tone** (`DailyCallStore.ringtoneFilename` → `Resources/ringtone.wav`, a synthesized two-tone warble in double-ring cadence). NOT the learner's voice, and not by choice: on iOS 26 a sound written at runtime — the only kind an app can put in `Library/Sounds` — is silently ignored by both AlarmKit and `UNNotificationSound`; only bundle resources play. A per-learner daily voicemail can never be a bundle resource. The voice arrives the instant they answer, which is what a phone call is anyway.
- **More than one call a day** — `DailyCallStore.times` is a list (max `maxTimes` = 4), edited in Me; the legacy `hour`/`minute` keys migrate into it on first read, and those properties now proxy the FIRST time (setting either collapses the list, so never wire a single-time picker to them). `DailyCallScheduler.fireDates` returns every remaining slot today, else tomorrow's first — and `schedule` arms **all of them at once**, each as its own alarm/notification carrying the same still-unheard message. Arming only the next one would be a no-op: the plan is written in the foreground, but the gap between a slept-through 08:00 and a 13:00 has the app closed with nothing running to schedule the second. Answering cancels the rest; the session that follows writes the next call fresh.
- **Onboarding introduces it** (`DailyCallOnboardingView`, gated in `RootView` on `futurevoice.dailyCall.onboarded`). Placed AFTER the voice clone — the call is the clone's first real job, so it reads as a promise rather than a permissions request. The flag is set on BOTH exits (enabled and skipped) or the screen becomes a wall. Existing installs see it once; that's how they learn the feature exists.
- **Button mapping is inverted on purpose.** `AlarmPresentation.Alert.stopButton` is deprecated in 26.1 (system-drawn, unlabelable), so **Answer is the SECONDARY button** — the only one we can label and give a phone glyph — and the system's button is Decline. `secondaryButtonBehavior` is `.custom`, NOT `.countdown`: countdown would oblige the app to ship a Live Activity widget for that state.
- **Every call settles into a `DailyCallOutcome`** (answered / declined / missed) and lands in `DailyCallStore.history()`. Declining rings back later (`maxCallbacks`), then the caller gives up for the day. **Where the "call back in…" choice is asked differs by surface**: the notification shows one action per `callbackOptions` entry inline (its category takes an array); the alarm can't, so `DeclineDailyCallIntent` sets `openAppWhenRun` and the app opens on `DailyCallCallbackSheet`. That sheet dismissing without a pick falls back to `defaultCallbackMinutes` — never to cancelling the day, which would be the app deciding something the learner didn't. An untouched call is settled as `.missed` on the next launch (`settleIfRangOut`, after `rangOutGrace`) — it can't be noticed at the time because nothing is running.
- **That history is what the NEXT script is written from** (`VoicemailEngine.Context.lastOutcome` / `consecutiveUnanswered`). This is the feature, not a nicety: an alarm knows nothing about you; a caller who opens with "couldn't talk yesterday?" reads as a person. Never make it scold — guilt is what makes people stop picking up.
- **A missed call leaves its message on the Talk tab** (`ConversationHome.missedCallRow`) until they listen or call back. A dismissed alarm leaves nothing; that difference is the whole point. It's a trace, never a standing pile. The waiting message lives in its OWN file (`DailyCallStore.unheardVoicemail`, `@Published`), NOT on the plan — there is only one plan on disk and `refresh` overwrites it with the next call moments after settling the one that went unanswered, so a trace kept on the plan was erased inside the same `refresh` that created it and the row appeared only if a render landed in between. For the same reason `markVoicemailHeard` clears that record and must never stamp `heardAt` on the plan, which by then is the NEXT call.
- **The voicemail is synthesized at generation time**, saved into `PhraseAudioStore` under its own (script, voiceId). `VoicemailEngine` writes a 2–3 sentence script (`flash-lite`) grounded in the last talk's topic and phrases, **always ending in a question** — an unanswered question is the whole pull. Target language: it's material. `synthesizeRingtone` takes the STREAMING TTS path purely for its **raw PCM** output — `UNNotificationSound` only plays Linear PCM / µLaw / aLaw in .wav/.caf/.aiff, never MP3 — levels it through `AudioLoudness.gain(forSpeechRMS:)`, and writes it under `Library/Sounds/` with a **never-reused filename** (iOS caches notification sounds by name). Hard 30s OS ceiling, enforced twice: `maxScriptCharacters` and `VoicemailEngine.trim`.
- **Generation happens at SESSION END, never in the morning** (`SessionSummarizer` → `AppState.refreshDailyCall(force: true)`). iOS won't reliably run background work at a chosen hour, and a call that fails to generate is a call that never rings. By 8am the script and audio are on disk, so the ring works offline. The `scenePhase == .active` re-arm is only a safety net (reinstall, missed fire, language switch) and is a no-op when a usable plan exists.
- **One synthesis, two uses.** The ringtone WAV is saved into `PhraseAudioStore` under the same (script, voiceId), so answering opens `ConversationView(initialOpener:)` and that cache hit IS the call's first spoken line — no second TTS, no round trip, and the voice never changes across the hand-off.
- **"In an hour" is not a failure.** `maxSnoozes = 3` re-fires the SAME plan (no new spend). Past the cap the day goes quiet and tomorrow's is written as usual — no scold, no broken counter, and `PracticeStats`' streak is untouched by a missed call.
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
  filters `kind = 'left'`, so nobody can work out whose seat they took. There
  is no push infrastructure, so `CoreClubService.announceArrivals()` polls on
  foreground and posts a quiet LOCAL notification (no sound; the daily call is
  the habit anchor and must not be competed with).

The bar (`core_club_config.daily_bar_seconds`, 240 s since
`20260814110000`) is tunable without a migration, but it must stay BELOW the
Daily tier's `daily_seconds` — at the cap there is no slack, and a call that
ends at 4 min 52 s would fail the day. It is currently derived from the plan's
shape, not from behaviour: `TalkMeter` only shipped 2026-08-11, so almost no
account emits `talk_seconds` yet. Re-derive it once real days exist.

## The learning loop (keep it closed)

```
conversation → summary (+ scorecard metrics) → DrillStore.ingest (SRS cards)
            ↘ LearnerProfile.absorb via ProfileStore  → next conversation's system prompt
            ↘ WeeklyReportEngine (unlocks on accumulated speaking time)
```

**The notebook is spent in the call** (`TalkGoalChips.swift`, 2026-08-19). A talk is the only place a saved word can actually be used, and nobody remembers mid-sentence what they saved on Tuesday — so today's due studying items ride along the call as one pinned line of chips above the transcript, and a chip ticks the moment the learner says it. Three rules hold it together: the judge is `CarryoverDetector` and nothing else (the same matcher writes the wrap-up's carryovers, so the live tick and the summary can never disagree); ticks are ADDITIVE — every version of a user turn's text is checked, from the recognizer's first line to Gemini's audio-grounded rewrite, and a tick is never taken back; and the row writes nothing to disk, because `VocabStore.ingest` + `CarryoverDetector.detect` already credit the word for real at session end. Items come from `StudyScheduleStore` due-ness, the same schedule the daily words/expressions sessions deal from, so the app never asks for the same thing twice in one day — and a phrase that can't clear `CarryoverDetector.isCreditable` is never offered, since a checkbox that cannot tick teaches the learner the whole row is decorative. **Tapping a chip opens `TalkGoalSheet`** — "Use this in the call", the word, ONE sense, ONE example. The header is an instruction to SPEND the word, not to repeat a line after the app: it's material the learner chose to study, and the call is the only place it gets used. A chip that couldn't be tapped was demanding a word the learner may no longer remember the meaning of. It stays thin on purpose: the full entry belongs to the notebook, and the call is still running underneath (nothing pauses, and `WordLore` is free + globally cached, so a mid-call tap costs nothing metered).

**The wait at the end of a talk shows its work** (`SummaryProgressView`, 2026-08-19). `SessionSummarizer` reports a growing `Progress` struct — words + expressions kept, corrections that survived verification, carryovers found, cards minted — at the exact point each piece finishes, and the wrap-up screen draws it as a checklist with a determinate bar. Every number is real and is the same number the summary sheet then shows; nothing here is a simulated bar, which is why the first step (the one model call) just spins for as long as it takes and shows facts already known about the talk instead of a fake percentage. The last four steps land milliseconds apart, so `endSession` holds the finished board for 0.9 s before presenting the summary — otherwise the board fills and vanishes in one frame and the learner never sees what their talk produced. `ConversationDetailView`'s rescue path draws the same board, because it builds the same things.

Every feature should feed this loop. Per-turn suggestions come back in the SAME Gemini call as the reply (structured JSON) — never split the suggestion out, and never remove the field: `ScorecardMetrics.suggestionRate`, drill ingestion, and the weekly report's repeated-mistake detection all depend on `Turn.suggestion`.

**A live turn is exactly two calls, and they run CONCURRENTLY** (2026-08). Measured: with the audio attached, the reply took 4.1s to start vs 2.1s without — the model has to ingest and transcribe before it can write the reply's first token, and that sat between "learner stops talking" and "fluent self starts talking".

- **Reply call** (`turnPayload` → `sendJSONStream`, default model, TEXT ONLY) — `{reply, suggestion}`. This is the only one the learner waits to HEAR.
- **Transcription call** (`UtteranceTranscriber`, `flash-lite`, audio attached, `purpose: "transcribe"`, priced at **0 credits** so the latency win doesn't double the price of talking) — verbatim line only. Lands whenever; `applyGeminiTranscript` edits the bubble in place.

Do not re-attach audio to the reply call, and do not add a THIRD per-turn call. Ordering between the two is not guaranteed: `lastRecognizerText` is what keeps the recognizer's late rescored pass from clobbering the audio-grounded line (`applyRecognizerUpgrade`).

**The transcription is deferred past the voice** (2026-08-14). Concurrent in control flow is not concurrent in RESOURCES: it was fired first, and its ~100 KB audio upload shared one `URLSession` — and therefore one HTTP/2 connection to one Supabase host — with the reply call *and* the ElevenLabs stream. Measured same-day, turns carrying the upload reached the reply's first sentence **0.8–2.2 s later** (5 of 5 days, same direction). Two changes keep it genuinely in the background:

- `DeferredTurnWork` holds both the transcription call and the recognizer's rescored line until `voiceDidStart()` — the single choke point every TTS path (split stream, plain stream, buffered, cache hit) runs through when audio actually reaches the speaker. Holding the recognizer line too is a PERCEPTION fix: a bubble that rewrites itself mid-wait reads as "it corrects me first, then answers" even though nothing ever waited on it.
- `GeminiClient.background` / `URLSession.edgeFunctionsBackground` gives the upload its own connection pool. Use it for any future call whose result nobody is waiting to hear.

Three consequences to preserve when touching this: the failure path in `requestReply` and `endSession` must both flush (a turn that never speaks still needs its correction, and `endSession` freezes `turns` for the summary — it waits ≤2.5 s for an in-flight call); `voiceDidStart` flushes BEFORE its `turnTiming.isEmpty` guard, so a logging condition can never cost a turn its transcript; and the audio-path field moved from `talk_turn_timing` to `talk_asr_upgrade` because it is now known only after the timing row has shipped.

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
- **Unclaimed clones are collected nightly** — `cleanup-anonymous-voices` +
  `stale_anonymous_users` (48h grace, ElevenLabs delete first, then the user,
  which cascades). A voice that fails to delete upstream KEEPS its user so the
  next run can retry; deleting it would lose the only pointer to a slot we pay
  for. The cron needs `project_url` + `cleanup_secret` in the vault and
  `CLEANUP_SECRET` in the function env — until then it simply doesn't schedule.

## Source of truth

- **Domain types** → `FutureVoice/Models/Models.swift`. Update there first.
- **Prompt templates** → `ConversationEngine.swift` (conversation + summary), `ShadowEngine.swift`, `WeeklyReportEngine.swift`, `TopicEngine.swift`, `DrillEnrichmentEngine.swift`. The shared two-language preamble every coaching prompt splices in lives in `CoachingLanguage.swift` — see "Two languages" below.
- **HTTP** → `GeminiClient.swift` and `ElevenLabsClient.swift` only. Both route through Supabase Edge Functions (`supabase/functions/`) so the app never holds raw provider keys. `ClaudeClient.swift` is a dead transport (no call sites) — don't wire new features to it.
- **Persistence** → JSON-on-disk stores in `Services/` (`SessionStore`, `DrillStore`, `ProfileStore`, `PersonaStore`, …), all following the same pattern. Supabase tables exist for auth/voice-clone/subscriptions (`supabase/migrations/`).
- **Billing** → minutes-NATIVE since 2026-08-11 (`20260811160000_minutes_native`, `docs/launch-billing.md`): the unit is **seconds of synthesized talk** — "credit" survives only in table/RPC/field NAMES. `user_credits.balance` = a FREE user's one-time seconds pool (signup grant 3960 s); subscribers have no balance — an entitled `user_subscriptions` row buys `subscription_plans.daily_seconds` per day (Daily `daily_*` 300 s, Unlimited `unlimited_*` 3600 s, resets midnight UTC), enforced by `consume_metered_seconds`. Talk = call time (`talk-tick`) and is the ONLY thing that spends `daily_seconds`. **Idle seconds are not charged since 2026-08-18**: `TalkMeter` polls `isBillable` once a second and only accumulates seconds where the fluent self is speaking, a reply is generating, or the learner's voice was heard within `voiceGraceSeconds` (6 s, wide enough to cover the longest end-of-turn wait) — a screen left open used to bill silence, minutes at a time. The predicate lives in `ConversationView.isBillableMoment` because only the call screen knows what is happening; a meter with none set bills every second, which is the old behaviour. **Watch left the talk meter on 2026-08-14** (`20260814100000_watch_scenes_by_count`): scenes are metered by COUNT against `subscription_plans.daily_scenes` (Daily 2/day, Unlimited 20/day fair-use), claimed once per scene by `begin_scene_play(user, scene_key)` — the client sends ONE key for every line of a scene, so a long scene costs one count and a scene in progress is never cut off. Sharing the pool meant buying "5 min of talk" and getting three on any day with Watch use; a count also costs ~half what the seconds did, since scene audio is on `fidelityModelId` (~2x/char). Everything else is free behind daily caps. Three 402s: `insufficient_credits` → paywall, `daily_cap_reached` (talk) and `scene_cap_reached` (Watch) → NEVER a paywall. **Since 2026-08-18 those two cap alerts split by TIER**: a **Daily** subscriber is offered Unlimited ("keep going today"), an **Unlimited** one is told to come back tomorrow — there is nothing left to sell them, so for that account the answer really is tomorrow. The 402 body carries no tier, so the branch is `AccountStatus.isDailyPlan`, resolved client-side (`canUpgradePlan` in `ConversationView` / `WatchView`); both live in their OWN alert, never the error one, because a finished day is not a failure. Keep plan SIZES out of that copy — the client doesn't know Unlimited's numbers and a hardcoded "20 scenes" goes stale silently. **Enrolling extra practice languages is NOT gated** (decided 2026-08-17, after a gate was built and reverted): every pool — `consume_metered_seconds` `(user_id, day, action)`, `record_free_usage` `(user_id, day, purpose)` — is keyed per ACCOUNT with no language in it, so a second language adds zero cost; someone splitting 5 minutes across three languages is spending their own time, and the day's cap is what converts them. Don't put a plan check on `AddLanguageSheet`. **Hard paywall since 2026-08-11** (`20260811180000_hard_paywall_trial`): new signups get a credit row at ZERO — no free pool — so the first talk hits the paywall; the voice clone and the ≤120-char onboarding greeting stay free as the entry ticket. A subscription in `trialing` is metered at the DAILY allowance (300 s/day) whatever plan it trials, so a 7-day Unlimited trial can't burn 60 min/day for free. Existing beta balances are untouched. Don't price anything new in credits, and don't grant on webhook renewals.
- **The paywall is asked BEFORE the spending, at the tap** (2026-08-18, `BillingGate`). A hard paywall met only as a 402 arrives too late to be an answer: the call screen was already up, and on Watch a whole scene had been written and watched being written before the learner was told it wasn't theirs to play. Every metered launcher now runs its action through `BillingGate.start(orShow:)` — the free-talk ring and the widget deep link (one gate, in `RootTabView.startFreeTalk`, where both paths meet), Talk's news/scenario cards, the composer's CTA (`ScenarioComposerSheet.commit`, before the categorize call and before any scenario is minted), Find people's Talk/Watch, and the Talk/Continue buttons on the book pages. Two rules keep it honest: it gates on `AccountStatus.needsSubscription` ONLY — a daily cap is not this, that learner already paid and the client's copy of today's usage is stale often enough to refuse a call the server would allow — and a "no" is never given from cache (a purchase or invite that landed a minute ago must not be paywalled again), while a "yes" always is, so the app's primary button never waits on the network. **A sheet hosting a paid button owns its own `PaywallView`**; a paywall raised by the host underneath never appears. Onboarding offers the plans once at the end (`OnboardingPaywallView`, after the daily-call step, flag on every exit, skipped silently for anyone with nothing to buy) — so the first tap on Talk stops being where the hard paywall introduces itself.
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

Two things survive the collapse and still matter:

- **`explain(…)` / `chrome(…)` are how a `String` gets localized at all.** `Text("literal")` follows the environment locale; a `String` never sees it. So any literal that flows through a `String` first — a computed nav title, a `switch` returning a label, a function parameter — has to go through one of them or it is frozen English in every language. This is not a style rule: `MeTab.row(icon:title:subtitle:)` takes `String`, and ~35 settings rows sat untranslated behind it until 2026-08-17, as did most of onboarding until 2026-08-16. The two helpers are now interchangeable; prefer `explain(…)` for new code.
- **Never write a bare `String(localized:)`.** It resolves against the main bundle and the SYSTEM locale, so it follows the phone's language instead of the learner's.

**Widgets and the `String(localized:)` ban.** The one sanctioned exception is `StudyWidgetSection.displayName` / `.galleryDescription`, which are drawn by iOS in the Add Widget sheet. Inside the widget extension the app-side helpers don't exist: `Text("literal")` follows `\.locale` (set to `.widgetChrome` at each widget's root) and `String`-typed labels go through `widgetChrome(…)`, both reading `StudyWidgetSnapshotStore.chromeLanguage` — the app language, mirrored into the App Group by `StudyWidgetRefresher` because an extension can't read the app's defaults. Anything the widget shows that is DATA (a book's subtitle) has to be resolved app-side at write time; the extension can only draw it.

**Refreshing the catalog:** a plain `xcodebuild build` does NOT write newly-added strings back into `Localizable.xcstrings` — it only compiles what's already there. Run `xcodebuild -exportLocalizations -localizationPath <tmp> -exportLanguage ko` to merge new keys in, then translate them. Skipping this is why a string can look wired up and still be missing from the catalog.

Nothing here names a language. Adding German is a `de` column in the catalogs plus its code in `project.yml`'s `knownRegions` — no other code change. `Localizable.xcstrings` is fully translated for **ko** (verified 2026-08-17, 1302 keys, zero gaps); **de has drifted** — 170 keys were already missing before the settings work and it is now ~225, which is knowingly deferred (German UI isn't a launch requirement; German is a target language, not a native one). Verify with a re-export: extracted count == repo count, and no entry missing a language unless it carries `shouldTranslate: false`, which marks punctuation, format shells and dev samples. One gap remains: outside Settings and onboarding, most explanatory strings are still unwrapped, so they read as chrome. Literals that flow through a `String` variable (`source = "Free talk"`) still neither extract nor localize until they go through `chrome(…)`/`explain(…)`.

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
- Conversation turns: structured JSON, **streamed** via `sendJSONStream` (`stream: true` → the `gemini` Edge Function proxies `streamGenerateContent?alt=sse`). Field order is load-bearing — `{reply, suggestion}`, reply FIRST. Don't put a field before `reply` and don't reorder the prompt's schema line. `onEarlyField` fires up to **twice** for `reply`: once with its first complete sentence (`isComplete: false`, ≥25 chars, terminator + whitespace — `GeminiClient.firstSpeakableSentence`) and once at its closing quote. The opening sentence goes to TTS immediately and the remainder is fed into the SAME open PCM stream (`beginSplitSpeech` / `finishSplitSpeech`), so the model's remaining writing time overlaps the TTS round-trip. Every failure in that pair degrades to speaking the whole reply once. Analysis calls (summary, shadow bullets, weekly report) stay on buffered `sendJSON`. Temperature args still exist on the API for 2.5-era callers but are ignored on gen-3.
- TTS: **speaker similarity is the product** — the user must believe the voice is theirs. Model choice ranks `eleven_multilingual_v2` > `eleven_turbo_v2_5` > `eleven_flash_v2_5` on similarity, and exactly the reverse on latency. Defaults:
  - Talk conversation turns → `eleven_turbo_v2_5` (`ElevenLabsClient.conversationModelId`). Flash was tried here and reverted: it costs the same but sounds less like the user, on the app's highest-exposure surface.
  - Watch scenes (the user's OWN voice only) + the onboarding greeting → `eleven_multilingual_v2` (`ElevenLabsClient.fidelityModelId`).
  - Everything else — Shadow, drills, library, counterpart preset voices → `eleven_turbo_v2_5`.
  - `fidelityModelId` bills ~2x per character upstream while `priceFor("tts")` in the edge function is model-BLIND, so that 2x is pure margin we absorb. Only put a path on it when `PhraseAudioStore` caches the result (making the 2x one-time per unique line) or when it fires once per user, ever. NEVER for live conversation turns.
  - Voice settings are fixed server-side in `supabase/functions/elevenlabs-tts/`. `style` MUST stay `0` — any style exaggeration pulls the output away from the reference speaker.

## Audio format

16kHz mono PCM WAV for recordings. Whisper and ElevenLabs both accept this. Don't change it without checking both providers' docs.
