import AVFoundation
import SwiftUI
import UIKit

/// Voice-first conversation screen, redesigned around a scrolling transcript
/// feed. The mic is small and lives at the bottom; the dominant content is
/// what the user and the fluent self just said — including a live partial
/// transcript while the user speaks, and a gentle inline correction chip
/// underneath each user turn when the LLM finds a more natural alternative.
struct ConversationView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var live = LiveTranscriber()
    /// The realtime transport (`gateway/`). When `RealtimeMode.isEnabled`, the
    /// per-turn HTTP machine below — VAD tiers, speculative replies, chunked
    /// ASR, deferred turn work — is bypassed entirely and turns arrive from
    /// the gateway instead. EVERYTHING downstream of `turns` is unchanged:
    /// the summary, drills, books, goal chips, the meter and the day card all
    /// read the same array they always have.
    @StateObject private var realtime = RealtimeTalkClient()
    /// Gateway reply context → the turn showing it, so a line's text and
    /// its audio land on the SAME bubble.
    @State private var realtimeReplyTurns: [String: UUID] = [:]
    @StateObject private var player = AudioPlayer()

    @State private var topic = ""
    @State private var topicBlurb = ""
    @State private var turns: [Turn] = []
    @State private var phase: Phase = .idle
    /// The written greeting is taking too long — the call is up and the screen
    /// says so rather than sitting in an unexplained silence. See the branch
    /// in `openConversation` that opens the line before the opener exists.
    @State private var openerIsLate = false
    @State private var error: String?
    @State private var summary: SessionSummary?
    @State private var showTopicPicker = false
    @State private var dueDrillCount = 0
    @State private var phoneCallActive = false
    @State private var silenceTask: Task<Void, Never>?
    /// True only while `endSession` is wrapping up (summary generation in
    /// flight). Distinct from `phase == .thinking`, which also fires per-turn
    /// mid-conversation — this drives the full-screen "wrapping up" overlay so
    /// the End tap gives immediate feedback instead of a silent wait.
    @State private var isEnding = false
    /// Real counts from the wrap-up as each piece of it lands — see
    /// `SummaryProgressView`.
    @State private var summaryProgress = SessionSummarizer.Progress()
    @State private var didAutoStart = false
    @State private var isResuming = false
    /// When this call started, and what the learner's talk history looked
    /// like then — pinned once per call (`pinPromptClock`), because the system
    /// prompt is rebuilt every turn and the realtime gateway is handed it
    /// once, and both must describe the same call.
    @State private var promptClock: PromptClock?
    /// A free talk's hello is written before the prompt carries the clock
    /// (2026-11-17, founder: "it keeps saying the time"). Nobody has spoken
    /// yet, so the hello was filled with whatever fact sat nearest, and that
    /// was the day and the hour, on every call. The clock joins the prompt
    /// once the hello is said (`giveClockAfterHello`).
    @State private var helloBeforeClock = false
    /// How this call follows a hello answered with no subject — drawn with
    /// the clock, once per call (`ConversationEngine.FreeTalkCue`).
    @State private var freeTalkCue: ConversationEngine.FreeTalkCue = .plainQuestion
    /// What came earlier today (`EarlierToday`) — read with the clock, so the
    /// opener and the prompt agree on it. Nil on the day's first talk and
    /// on a resumed talk, which has its own lines.
    @State private var earlierToday: EarlierToday?
    /// The earlier talks a free talk knows of, and the ones looked up
    /// because the learner brought them up (`TalkRecall`). Read once per
    /// call, with the clock.
    @State private var recallIndex: [TalkRecall.Entry] = []
    @State private var recalledTalks: [TalkRecall.Entry] = []
    @State private var recallQueries: [UUID: String] = [:]
    /// Set when a reply (Gemini/TTS) fails for the latest user turn — drives
    /// an inline Retry button so a network blip doesn't lose what they said.
    @State private var failedTurnId: UUID?

    /// Whether the feed still follows new lines to the bottom.
    ///
    /// It has to be a state, not a reflex. Live dictation rewrites the
    /// partial bubble many times a second and every one of those used to
    /// yank the view back down — so a learner reading back what they said
    /// three turns ago got dragged to the floor while they were still
    /// talking, which is the one moment they cannot do anything about it.
    /// A DRAG is the only thing that turns following off, and coming back to
    /// the bottom is the only thing that turns it on: content arriving must
    /// never decide this, or appending a line would look exactly like the
    /// learner scrolling away and following would end up switching itself
    /// off the first time anyone spoke.
    @State private var followTail = true
    @State private var settleScroll: Task<Void, Never>?
    /// Bumped whenever a correction card is attached. The card hangs off a
    /// turn that is already on screen, so the feed's other triggers
    /// (`turns.count`, the last transcript) never fire — the row simply grew
    /// taller and pushed everything below it out of view, including the
    /// fluent self's reply (reported 2026-09-01).
    @State private var suggestionsShown = 0
    /// Viewport height of the feed, read from a background overlay so it
    /// costs no layout. Paired with the bottom sentinel's offset to answer
    /// "is the end of the transcript on screen".
    @State private var feedViewportHeight: CGFloat = 0
    /// The last failure was a 402 — the user is out of credits. Retry is
    /// pointless until they top up, so the recovery UI leads with the paywall.
    @State private var outOfCredits = false
    /// The free first call's seconds ran out mid-call. The call wraps itself
    /// up (`handleTalkPoolSpent`) and the plans are offered after the book,
    /// whether or not the pitch has been made once already.
    @State private var freeCallSpent = false
    /// The free minutes are over on a never-subscribed account: the report
    /// of what they showed comes up in place of the plans, which are its
    /// last card (`TrialReport`).
    @State private var trialReport: TrialReport?
    /// The report actually came up on this screen. A close before that
    /// hands it to the root (`close()`).
    @State private var trialReportAppeared = false
    /// Wall-clock talk metering (4.5 cr/min via `talk-tick`). Started when
    /// the call seat opens, stopped on end/teardown; its 402 ends the call
    /// gracefully through the same out-of-credits alert as a turn failure.
    @StateObject private var meter = TalkMeter()
    @State private var showingPaywall = false
    /// The call's own settings sheet — the mic pill's only neighbour.
    @State private var showingCallSettings = false
    /// The tutor's card over the top of the call (`CallIsland`): open when
    /// the call starts, folded into the bar once the learner speaks.
    @State private var islandExpanded = false
    @State private var showingIslandTopics = false
    /// Where the bar puts its title, in screen points.
    @State private var islandBarY: CGFloat?
    /// Screen state the learner owns while the call runs (`CallSettings`).
    /// Persisted, so a call opens the way the last one was left.
    @AppStorage(CallSettings.showsTranscriptKey) private var showsTranscript = true
    @AppStorage(CallSettings.showsCorrectionsKey) private var showsCorrections = true
    @AppStorage(CallSettings.showsGoalChipsKey) private var showsGoalChips = true
    /// nil until the learner flips it in Call settings — until then the
    /// level decides (`CoachMode.resolve`: on for A1/A2).
    @AppStorage(CoachMode.key) private var coachModeChoice: Bool?
    @AppStorage(AppState.proficiencyKey) private var proficiencyRaw = CEFRLevel.b1.rawValue
    /// Read from UserDefaults, not from the two wrappers: the realtime
    /// callbacks (`advanceCoach` and the rest) are closures captured when the
    /// call opened, and in that copy of the view the wrappers kept the value
    /// they had then — measured 2026-10-04, coach mode switched off mid-call
    /// on build 71 and `CoachSuggester` kept running and drawing "Try saying"
    /// for the rest of the call. The wrappers stay so the view still
    /// re-renders (and `onChange(of: coachMode)` fires) when the sheet flips it.
    private var coachMode: Bool {
        _ = coachModeChoice
        _ = proficiencyRaw
        return CoachMode.isOn && !pronThisCall
    }
    /// nil until the learner flips it — the level decides (`SendToAnswer`).
    @AppStorage(SendToAnswer.key) private var sendToAnswerChoice: Bool?
    /// Send-to-answer: a pause never ends the learner's turn, their Send
    /// does. Read like `coachMode`, for the same captured-closure reason.
    /// The pronunciation call and a tutor lesson always run on Send
    /// (founder, 2026-11-13: the tutor should have the pronunciation call's
    /// reset): a try there is one line to get right, and only a held turn
    /// can be thrown away and said again.
    private var sendToAnswer: Bool {
        _ = sendToAnswerChoice
        _ = proficiencyRaw
        return SendToAnswer.isOn || pronThisCall || tutorThisCall
    }
    /// Watched only to tell a live call when the rung moves (the sheet
    /// writes it) — see the `CallSettingsSheet` presentation.
    @AppStorage(SpeechSpeed.key) private var speechSpeedRaw = SpeechSpeed.default.rawValue
    /// The call screen is waiting on that pitch to close before it exits.
    @State private var closeAfterPaywall = false
    /// Which of this screen's doors opened the paywall — `PaywallView`'s
    /// `source`, set beside every `showingPaywall = true`.
    @State private var paywallSource = "talk"
    /// How the summary sheet is going away, read by its `onDismiss`: Done
    /// and a swipe take the same exit (and are told apart in
    /// `talk_summary_closed`); `.code` is `startNewSession` clearing it,
    /// which must not exit. That function has no caller today — the case
    /// keeps the protection it always had, now that Done exits too.
    enum SummaryClose: String { case done, swipe, code }
    @State private var summaryClose: SummaryClose = .swipe
    /// The summary sheet's `onDismiss` has run once. It is terminal for this
    /// screen (every exit goes through `close()`), so nothing resets it
    /// except the unreferenced `startNewSession`.
    @State private var postCallExitStarted = false
    /// "How was your first call?" (`FirstCallCheckSheet`) — raised once,
    /// between the first call's summary and the rest of the exit.
    @State private var showingFirstCallCheck = false
    /// The check was raised by `close()` (an exit with no summary sheet), so
    /// its dismissal finishes closing rather than continuing the wrap-up.
    @State private var closeAfterFirstCallCheck = false
    @State private var firstCallCheckTrigger: FirstCallCheckSheet.Trigger = .summary
    /// Today's talk allowance is spent. Its own SHEET, not the error alert —
    /// a finished day is not something going wrong.
    @State private var dailyCapReached = false
    /// An uncapped plan past the abuse line. Its own alert, never the spent-
    /// allowance sheet: nothing ran out.
    @State private var fairUseHalted = false
    /// This account is on Light, so there IS somewhere to go when the pool
    /// runs out. Resolved at call start so the sheet's button is there the
    /// moment the wall lands. False on Plus: nothing left to sell, and the
    /// answer really is next month.
    @State private var canUpgradePlan = false
    /// The tier "Move to …" lands on (`AccountStatus.upgradeTier`).
    @State private var upgradeTier: String?
    /// A minute pack is on offer at the wall: counted subscription, not a
    /// trial (2026-09-26).
    @State private var canTopUpTalk = false
    /// Resolved with the account, long before the wall — the sheet's own
    /// buttons must not grow a new one under the learner's thumb.
    @State private var inviteOffer: InviteOffer?
    /// The plan's own pool in whole minutes, from the account snapshot.
    /// Never hardcoded: the number is a plan setting on the server and a
    /// stale constant here would misstate what they bought.
    @State private var poolMinutes: Int?
    /// Trialing: the sheet must speak of the trial's pool, not the month's,
    /// and never offer Plus. With the plan's monthly minutes so it can say
    /// what starts when the trial converts.
    @State private var accountIsTrialing = false
    @State private var planMinutesAfterTrial: Int?
    /// When the pool refills, for the sheet's "back on the 14th" line.
    @State private var renewalLabel = ""
    /// The plan stops on that date instead of refilling (cancelled).
    @State private var planEndsAtPeriodEnd = false
    /// What the cap sheet was dismissed FOR. A sheet can't raise the next
    /// sheet while it is closing, so the choice is recorded and acted on in
    /// `onDismiss`.
    @State private var capChoice: CapChoice?
    /// Set while the exit is on its way to the Practice tab — staged only
    /// once the call screen is actually gone (see `close`).
    @State private var routeToPracticeOnClose = false
    /// Which tier the paywall should open on, when a caller named one.
    @State private var paywallTier: String?

    private enum CapChoice { case upgrade, review, topUp }
    /// Unified beta feedback modal — set to a milestone to present it.
    @State private var feedbackContext: FeedbackSheet.Context?
    /// endAndClose defers its dismiss until the first-talk feedback closes.
    @State private var dismissAfterFeedback = false
    @State private var showMicPermissionAlert = false
    /// One-time "which mic?" question (see `MicPreferenceStore`). Asked at the
    /// top of the call, never per turn — a modal between turns would be a
    /// modal in the middle of a conversation.
    @State private var askingMicChoice = false
    @State private var micChoiceContinuation: CheckedContinuation<Void, Never>?
    @State private var askingFirstCallSetup = false
    @State private var firstCallSetupContinuation: CheckedContinuation<Void, Never>?
    /// Flipped by tearDown() when the screen closes. Every async continuation
    /// (Gemini reply, TTS synthesis, stream chunks, auto-restart) checks it
    /// and bails — otherwise a reply in flight at close time keeps talking
    /// over the home screen and overlaps the next call's session.
    @State private var isTornDown = false
    @Environment(\.dismiss) private var dismiss
    /// Watched only to recover a call whose mic died while the app was away —
    /// see `resumeCallIfStalled`. With background audio declared this is a
    /// safety net, not the normal path: a backgrounded call keeps running.
    @Environment(\.scenePhase) private var scenePhase

    /// RootTabView's free-talk presentation hosts this view in a ZStack (not
    /// a cover), where dismiss() is a no-op — closing must hand control back
    /// to the presenter so it can play the pill morph in reverse.
    private var onClose: (() -> Void)?

    /// A line the fluent self has ALREADY said — the daily call's voicemail,
    /// which the learner just heard ring on their lock screen. When set, the
    /// call opens on exactly this instead of writing a fresh greeting: the
    /// question they were asked is the question still waiting when they pick
    /// up. Its audio is already in the phrase cache (`DailyCallScheduler`
    /// stores the ringtone under the same text + voice), so speaking it costs
    /// no second synthesis and the voice never changes mid-hand-off.
    private let initialOpener: String?
    /// The learner tapped "pick up where you left off" on a person.
    private let pickUpLastTalk: Bool
    /// What this call's person remembers of earlier talks, pinned with the
    /// clock (`PersonHistory`).
    @State private var personHistory: PersonHistory?
    /// A "my own topic" call (topics page): opens by asking what to talk
    /// about, and the subject the learner names is the call
    /// (`ConversationEngine`'s THEY CHOSE THE TOPIC block).
    private let learnerPicksTopic: Bool
    /// A tutor-mode lesson on the topic whatever the Call setting says —
    /// the tutor bot's goal drill.
    private let forceTutor: Bool
    /// Ties the lesson to one question of a goal (`GoalPrep.topicId`).
    private let lessonTopicId: String?
    /// The screen this call was started from — `conversation_started` only.
    private let entry: TalkEntry

    /// Presented as the immersive "talk seat" from ConversationHome. An initial
    /// topic launches a scenario; empty = free talk. Pass `resumeSession` to
    /// pick up a past conversation where it left off (same session id, prior
    /// turns preloaded as context). The call auto-starts on appear so it feels
    /// like placing a phone call.
    init(initialTopic: String = "", initialBlurb: String = "",
         initialIsNews: Bool = false, initialOrigin: SessionOrigin = .free,
         initialScenarioId: UUID? = nil, initialNewsFacts: [String] = [],
         initialCounterpart: Counterpart? = nil,
         initialOpener: String? = nil,
         pickUpLastTalk: Bool = false,
         learnerPicksTopic: Bool = false,
         tutor: Bool = false,
         lessonTopicId: String? = nil,
         resumeSession: Session? = nil,
         entry: TalkEntry = .other,
         onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        self.initialOpener = initialOpener
        self.pickUpLastTalk = pickUpLastTalk && resumeSession == nil
        self.learnerPicksTopic = learnerPicksTopic && resumeSession == nil
        self.forceTutor = tutor && resumeSession == nil
        self.lessonTopicId = lessonTopicId
        // Only the ring's own page opens one: the key stays set while that
        // page shows, and a daily call or a topic must never become a
        // reading drill because of it.
        let pron = entry == .talkRing && resumeSession == nil && !tutor
            && initialTopic.isEmpty && initialCounterpart == nil && PronunciationCall.isOn
        if pron {
            _pronThisCall = State(initialValue: true)
            _tutorThisCall = State(initialValue: false)
            _tutorWasOn = State(initialValue: false)
        } else if self.forceTutor {
            _tutorThisCall = State(initialValue: true)
            _tutorWasOn = State(initialValue: true)
        } else if (resumeSession?.counterpartId ?? initialCounterpart?.id) != nil {
            // A call WITH someone (a person on the map, a stranger, someone
            // bumped into) is that person talking, never the tutor: tutor
            // mode is the fluent self's (2026-11-04, founder — a call with a
            // stranger came up as a lesson). Turning it on mid-call still works.
            _tutorThisCall = State(initialValue: false)
            _tutorWasOn = State(initialValue: false)
        }
        self.entry = resumeSession != nil ? .resume : entry
        if let s = resumeSession {
            _topic = State(initialValue: s.topic ?? "")
            _topicBlurb = State(initialValue: "")
            _turns = State(initialValue: s.turns)
            _sessionId = State(initialValue: s.id)
            _sessionStartedAt = State(initialValue: s.startedAt)
            _didSaveCurrentSession = State(initialValue: true)
            _isResuming = State(initialValue: true)
            // Carry the original origin so a resumed talk keeps its badge.
            _sessionOrigin = State(initialValue: s.origin ?? (s.topic?.isEmpty == false ? .news : .free))
            _sessionScenarioId = State(initialValue: s.originScenarioId)
            _sessionCounterpartId = State(initialValue: s.counterpartId)
        } else {
            _topic = State(initialValue: initialTopic)
            _topicBlurb = State(initialValue: initialBlurb)
            _topicIsNews = State(initialValue: initialIsNews)
            _sessionOrigin = State(initialValue: initialOrigin)
            _sessionScenarioId = State(initialValue: initialScenarioId)
            _sessionCounterpartId = State(initialValue: initialCounterpart?.id)
            _newsFacts = State(initialValue: initialNewsFacts)
        }
    }

    /// Three-tier end-of-turn threshold, measured against TRUE AUDIO SILENCE
    /// (`LiveTranscriber.lastVoicedAt` from the mic energy meter) — the same
    /// hybrid used by modern realtime voice stacks: acoustic VAD picks the
    /// endpoint, text completeness modulates how long to wait.
    ///   • `short`   — explicit end-of-sentence punctuation. They wrapped up.
    ///   • `default` — no clear signal either way.
    ///   • `long`    — trailing filler / hanging conjunction / stub
    ///     article/preposition. They're clearly still composing.
    // History: 2026-06 users reported the avatar cutting in during natural
    // mid-thought breaths. That was under TRANSCRIPT-quiet timing — STT
    // partials stall unpredictably while the user is still talking, so the
    // timer measured the recognizer, not the speaker, and the only fix was a
    // padded 5s default. Energy-based silence can't misfire on a breath
    // (breaths are ~0.5–1.5s and unvoiced), so the default drops back to 3s
    // without recreating that bug. `sttSettleSeconds` additionally holds fire
    // while the partial transcript is still moving, so a lagging recognizer
    // never gets its tail truncated.
    // 2026-08 retune: `talk_turn_timing` says the DEFAULT tier fires 53% of
    // turns (95/179) and the short tier 27%, i.e. this wait is the single
    // biggest slice of the silence between "user stops" and "fluent self
    // speaks" — bigger than the whole Gemini call. Every `final_timeout` seen
    // so far is 0 (the rescored FINAL pass always landed with room to spare),
    // so the padding buys nothing. Default 3.0 → 2.2, short 1.5 → 1.2. The
    // LONG tier stays at 5s: it only fires on a hanging conjunction or filler,
    // where cutting in is exactly the failure mode this whole scheme exists to
    // avoid. Roll back if `final_timeout=1` starts appearing in telemetry.
    // 2026-08 second retune: measured `vad_wait_ms` averages 1.97s, the second
    // biggest slice of the wait after Gemini itself, and `final_timeout` is
    // still 0 across every logged turn — the recognizer is never the binding
    // constraint. Default 2.2 → 1.6, short 1.2 → 0.8. The LONG tier stays at
    // 5s for the same reason as before: it only fires on a hanging conjunction
    // or filler, where cutting the learner off is the failure this whole
    // scheme exists to prevent.
    // 2026-09-04, REVERTING the second retune: the learner reports being cut
    // off mid-sentence, which is the failure that telemetry structurally
    // cannot see — a turn ended early looks like a fast turn, and the words
    // that never got said look like the start of the next one. Both retunes
    // above were driven entirely by that blind number. Short 0.8 → 1.2,
    // default 1.6 → 2.2 (still under `quietCommitThreshold` = 2.6, so the
    // recognizer's own rotation still comes second).
    //
    // Two things make the wait cost far less than it did when it was cut:
    //   • `SpeculativeReply` fires at 0.6 s of silence, so the extra
    //     confirmation time is spent INSIDE Gemini's ~2.4 s of thinking
    //     rather than in front of it (adopted on ~half of turns, and a
    //     longer, calmer wait raises that rate);
    //   • the chunk pipeline cuts a piece at 0.5 s of silence and its round
    //     trip runs ~1.3 s — under an 0.8 s tier the assembly was ALWAYS
    //     late (`chunk_path=late` on ~87% of turns, `asr=fixed` on 73%), so
    //     the reply was written from the on-device guess. At 2.2 s the tail
    //     lands before the turn ships, and the fluent self answers what was
    //     actually said instead of what the phone guessed.
    private static let vadShortSeconds: Double   = 1.2
    private static let vadDefaultSeconds: Double = 2.2
    private static let vadLongSeconds: Double    = 5.0
    /// Headroom over a pause the learner has already taken and come back from.
    /// Matching it exactly would end the turn on the very gap they proved they
    /// speak through; 0.4s is one tick of hesitation more than that.
    private static let pauseFloorMargin: Double = 0.4
    /// How much of the evidence survives into the next turn. Pausing habits
    /// carry across a call — the learner composing in 3s gaps in turn two is
    /// the same person in turn three — but a single freak gap must not make
    /// the whole call sluggish, so each turn starts from 70% of the last.
    /// Three ordinary turns wash a 4s outlier back down to ~1.4s.
    private static let pauseFloorDecay: Double = 0.7
    /// The longest mid-speech pause seen SO FAR IN THIS CALL, decayed per turn.
    /// Exists because `LiveTranscriber`'s meter resets every turn, which left
    /// the first pause of every turn judged with no evidence at all — and the
    /// first pause is exactly where a learner gets cut off.
    ///
    /// Seeded from the LAST call (2026-09-04): how long someone goes quiet
    /// while composing is a property of the person, not of the call, and
    /// starting every call at zero meant the first pause of every call was
    /// judged by the fixed tiers alone — the one moment with no evidence at
    /// all, and the moment the learner remembers being cut off. It decays per
    /// turn exactly as before, so a call that never needs it forgets it
    /// within three turns.
    @State private var sessionPauseFloor: Double = 0
    private static let pauseFloorDefaultsKey = "futurevoice.talk.pauseFloor"
    private static func rememberedPauseFloor() -> Double {
        min(UserDefaults.standard.double(forKey: pauseFloorDefaultsKey), vadLongSeconds)
    }
    /// Don't send while the STT partial is still changing — recognition lag
    /// after the last spoken word is typically 0.3–0.5s.
    private static let sttSettleSeconds: Double  = 0.7
    /// Endpoint monitor tick. 0.2s keeps worst-case added latency ≤ one tick.
    private static let endpointTickSeconds: Double = 0.2
    /// Noisy-room fallback: constant background noise can keep the energy
    /// meter reading "voiced" forever. If the TRANSCRIPT has been still this
    /// long (the old conservative signal), send regardless of energy.
    private static let noisyRoomFallbackSeconds: Double = 6.0
    /// Ceiling on one listening turn, for when the ROOM is doing the talking.
    /// A café defeats BOTH endpointing signals at once — the room never falls
    /// silent and the recognizer keeps turning other people's voices into
    /// fresh partials — and the turn then never ends at all. Gated on
    /// `someoneIsTalkingHere()` being false: the clock alone cut real
    /// monologues mid-sentence (reported 2026-08-18 — a learner who never
    /// pauses reaches 30s in a perfectly quiet room), and a person's own
    /// voice clears the voiced threshold where a room's babble doesn't, so
    /// the same witness that separates them for billing separates them here.
    private static let maxListenSeconds: Double = 30
    /// Absolute cap, whoever is talking. Bounds how large one turn's
    /// recording can grow (the whole utterance is uploaded for transcription)
    /// and how stale the on-device partial gets. By the time this fires the
    /// segment carries minutes of close-mic evidence, so the cut SENDS —
    /// nothing is lost but the tail.
    private static let maxListenSecondsHard: Double = 120
    /// How much close-mic speech a segment must contain before we believe a
    /// PERSON produced it. Used twice: whether a ceiling'd turn is worth
    /// sending, and whether the call counts as occupied at all.
    ///
    /// 1.5s is about the shortest real answer ("Yeah, I think so"). Below it,
    /// in a room loud enough to reach the ceiling, we are guessing — and the
    /// cost of guessing wrong is a paid Gemini turn answering a stranger's
    /// sentence.
    private static let minVoicedSecondsPerTurn: Double = 1.5
    /// How much true silence before warming the network path. Must stay well
    /// under the SHORTEST VAD tier (now 0.8s) so the TLS handshake + auth
    /// token are in place by the time the turn actually fires.
    private static let preconnectAfterSilenceSeconds: Double = 0.35
    /// One preconnect per listening phase — reset when the mic restarts.
    @State private var didPreconnectThisTurn = false
    /// Per-turn latency breadcrumbs, accumulated across the VAD → finalize →
    /// Gemini → first-TTS-chunk pipeline and logged once when the fluent
    /// self actually starts SPEAKING (the moment users experience as "the
    /// answer arrived"). Keys: vad_wait_ms, finalize_ms, gemini_ms,
    /// tts ("stream"/"buffered"/"cache"), tts_first_ms, total_ms. The audio
    /// path moved to `talk_asr_upgrade` when the transcription call was
    /// deferred past this row's ship time.
    @State private var turnTiming: [String: String] = [:]
    /// When the user finished speaking (endpoint fired) — anchor for total_ms.
    @State private var turnEndedSpeakingAt: Date?
    /// Per user turn, the last text the RECOGNIZER put in that bubble. The
    /// late rescored pass may only overwrite a line that still matches this,
    /// so it can never clobber Gemini's audio-grounded rewrite. Entries are
    /// dropped as soon as that rewrite resolves.
    @State private var lastRecognizerText: [UUID: String] = [:]
    /// The user's utterance being transcoded for the Gemini attachment, and
    /// the turn it belongs to. Kicked off the moment the recording lands so
    /// the encode runs CONCURRENTLY with everything else the turn has to do
    /// (append, prompt build, auth token, TLS warm-up) instead of sitting in
    /// front of the request on the main actor. Retry awaits the same task —
    /// one transcode per turn, however many attempts.
    @State private var turnAudioEncode: (turnId: UUID, task: Task<EncodedTurnAudio, Never>)?
    /// The in-flight verbatim-transcription call. One per turn; cancelled when
    /// the next turn starts or the call screen closes.
    @State private var transcribeTask: Task<Void, Never>?

    // MARK: Chunked transcription (2026-08-18, testing)

    /// Chunk-by-chunk audio transcription of the turn IN PROGRESS. The
    /// whole-turn Gemini transcription corrects the bubble ~3s AFTER the reply
    /// was already generated from the on-device guess — so the fluent self
    /// answers text the learner may never have said (`asr=fixed` on most
    /// turns). Cutting the capture at pause boundaries while the learner is
    /// still talking puts the audio-grounded text (mostly) IN HAND when the
    /// turn ends: chunks ride the idle network of the listening phase on
    /// `GeminiClient.background`, and the tail chunk's round trip overlaps the
    /// VAD confirmation wait. When every chunk resolves in time, the REPLY is
    /// generated from that text; when any is missing, the turn ships exactly
    /// as before (on-device guess now, whole-turn correction later) — never
    /// worse than today, sometimes right where today is wrong.
    private static let chunkedASREnabled = true
    /// True silence before the current chunk is cut. Below every VAD tier
    /// (0.8s shortest), so on a turn that is actually ending this doubles as
    /// the SPECULATIVE TAIL send; above the intra-phrase word gaps, so cuts
    /// land between phrases, not inside words.
    private static let chunkRotateSilenceSeconds: Double = 0.5
    /// Close-mic speech a piece must hold to be worth its own call.
    private static let chunkMinVoicedSeconds: Double = 1.5
    /// Voiced seconds below which the tail is just the trailing quiet after
    /// the last cut — deleted, not transcribed.
    private static let chunkTailMinVoicedSeconds: Double = 0.3
    // `stopAndSend` no longer WAITS for outstanding chunk transcripts at all —
    // it harvests an assembly that is already settled and moves on.
    //
    // The wait shrank 1.5 → 0.35 → 0.1 s across 2026-08-21 (each step
    // measured: the tail chunk's RTT runs ~1.3 s past turn end, so every
    // window mostly expired unfilled), and prod telemetry through 2026-08-31
    // closed the argument: ~87% of turns logged `chunk_path=late` with
    // `chunk_wait_ms` ~125–137 — the 0.1 s deadline plus the 60 ms poll tick,
    // paid on nearly every turn for nothing. The assemblies that DO land in
    // time (`chunk_path=full`, 10–15%) were overwhelmingly settled at entry
    // (`chunk_wait_ms` 0), so a zero-length harvest keeps most of them. A
    // missed assembly costs only reply-from-on-device-guess — the accepted
    // trade since the 1.5 s cut — and the transcript is still corrected
    // post-voice (chunk flush or whole-turn ASR).

    /// True silence before the reply is generated SPECULATIVELY, while the
    /// VAD is still deciding whether the turn is over. Measured 2026-08-21:
    /// the model burst-writes (~2 s thinking, then everything at once), so
    /// the only way to shorten the visible Gemini wait is to start it under
    /// the VAD confirmation instead of after it. Sits above the chunk-rotate
    /// cut (0.5 s) and below the shortest VAD tier (0.8 s); combined with the
    /// `sttSettleSeconds` guard the request fires ~0.7–0.9 s into a pause,
    /// buying back the rest of the 1.2–1.7 s confirmation wait. A resumed
    /// voice cancels the task — Gemini is free and rate-capped (the edge
    /// function charges no credits for `purpose: "turn"`), so a discarded
    /// speculation costs the learner nothing.
    private static let speculateAfterSilenceSeconds: Double = 0.6
    /// Partial-settle bar for FIRING a speculation — deliberately looser than
    /// `sttSettleSeconds` (0.7), which gates the real send. Measured
    /// 2026-08-21: with both at 0.7 the recognizer's trailing partials pushed
    /// the fire to ~0.3 s before the VAD confirmed (spec_lead_ms 318–341),
    /// wasting most of the head start. A snapshot taken mid-rescore just
    /// mismatches at adoption and refires — free, and capped per turn — so
    /// the speculation can afford to guess earlier than the send can.
    private static let speculateSettleSeconds: Double = 0.4

    /// A reply generation already in flight for a turn the VAD hasn't
    /// confirmed yet. `text` is the recognizer partial it answered; adoption
    /// requires the committed turn to still say the same thing
    /// (`ConversationEngine.saysTheSameThing` — rescoring may shuffle
    /// punctuation, which must not throw the head start away).
    private struct SpeculativeReply {
        let text: String
        let firedAt: Date
        let task: Task<ConversationTurnPayload, Error>
    }
    @State private var speculativeReply: SpeculativeReply?
    /// Speculations fired within the current listening turn. Capped: in a
    /// noisy room the recognizer keeps minting fresh partials out of the
    /// room's voices, and an uncapped cancel→refire loop would burn the
    /// day's rate cap on a turn nobody is speaking.
    private static let maxSpecFiresPerTurn = 3
    @State private var specFiresThisTurn = 0

    /// Per-listening-run state of the chunk pipeline — a class so the send
    /// tasks and the endpoint monitor share one mutable record.
    @MainActor
    private final class ChunkASRState {
        let runId = UUID()
        /// Pieces cut so far; piece n's transcript lands in `resolved[n]`.
        var nextIndex = 0
        /// Piece index → verbatim text ("" = no speech in that piece).
        var resolved: [Int: String] = [:]
        /// Pieces whose call failed — any one of them sinks the assembly.
        var failedCount = 0
        /// `FluencyMeter.speakingSeconds` at the last cut, so "voiced seconds
        /// since the last rotation" is computable against the running meter.
        var voicedMark: Double = 0
        var tasks: [Task<Void, Never>] = []

        var isSettled: Bool { resolved.count + failedCount >= nextIndex }
        var hasFailure: Bool { failedCount > 0 }
        /// Words the last assembly dropped as echo — logged, so how often the
        /// model writes its own context back out stays visible.
        private(set) var echoWords = 0
        /// In-order text of everything resolved so far — the continuity
        /// context for the next piece's call, and the assembled turn text.
        /// Pieces are STITCHED, not concatenated: see `ConversationView.stitch`.
        func textSoFar() -> String {
            var text = ""
            var echo = 0
            for index in 0..<nextIndex {
                guard let piece = resolved[index], !piece.isEmpty else { continue }
                let (joined, dropped) = ConversationView.stitch(text, piece)
                text = joined
                echo += dropped
            }
            echoWords = echo
            return text
        }
    }
    @State private var chunkASR: ChunkASRState?
    /// Turns whose transcript was assembled from chunks BEFORE the reply —
    /// already ground truth, so the whole-turn transcription call is skipped.
    @State private var chunkResolvedTurns: Set<UUID> = []
    /// Assembled chunk text the MODEL is answering, for turns whose bubble is
    /// still showing the on-device line. The reply must be generated from the
    /// audio-grounded text — that is the whole point of the chunk pipeline —
    /// but the learner must not SEE the correction before they hear the
    /// answer, so the two texts diverge for exactly the length of that wait.
    /// Cleared the moment `flushDeferredTurnWork` puts it on screen.
    @State private var chunkModelText: [UUID: String] = [:]

    /// Turn work that is deliberately held until the fluent self is AUDIBLE.
    ///
    /// All three pieces used to run in the gap between "learner stops talking"
    /// and "fluent self starts talking", and all three made that gap worse:
    ///   • the transcription upload shared one connection with the reply call
    ///     and the TTS stream (all three are the same host + session), so the
    ///     reply's first sentence measured 0.8–2.2 s later on turns that
    ///     carried it — the learner waited on their own correction;
    ///   • the recognizer's rescored line rewrote the bubble mid-wait, which
    ///     reads as "it corrects me FIRST, then answers" even though nothing
    ///     was ever waiting on it;
    ///   • the chunk assembly did the same, and worse: it landed BEFORE the
    ///     reply was even requested, so the corrected line was guaranteed to
    ///     be on screen a full Gemini + TTS round trip before the voice.
    /// None is time-critical. Held here and flushed by `voiceDidStart()`,
    /// they become what they were always meant to be: background work.
    private struct DeferredTurnWork {
        let turnId: UUID
        /// The recognizer's late rescored line, if it landed during the wait.
        var recognizerUpgrade: String?
        /// The chunk pipeline's assembled line — already answered by the
        /// model, still unseen by the learner. Outranks `recognizerUpgrade`.
        var chunkTranscript: String?
        /// The turn's correction card, parked. The payload usually closes
        /// while the TTS is still loading, so an unheld card is VISIBLE
        /// before the voice — the most legible form of "it corrects me,
        /// then answers". Held here it appears WITH the voice: display
        /// timing only, nothing ever waits on it.
        var suggestion: TurnSuggestion?
    }
    @State private var deferredTurnWork: DeferredTurnWork?

    /// A reply whose OPENING SENTENCE is already playing on an open PCM stream
    /// while the model finishes writing the rest. Non-nil only between
    /// `beginSplitSpeech` and `finishSplitSpeech`.
    struct SplitSpeech {
        var fluentTurnId: UUID
        var sampleRate: Double
        /// PCM of the opening sentence, kept so the finished turn caches the
        /// WHOLE line as one file.
        var pcm: Data
        var prefix: String
    }
    @State private var splitSpeech: SplitSpeech?

    /// A turn's audio, ready to attach — or the reason there is none.
    struct EncodedTurnAudio: Sendable {
        var inline: GeminiClient.Message.InlineAudio?
        /// "none" · "too_big" · "decode_fail" · "no_file"
        var skip: String
    }
    @State private var dashboard: PracticeStats.Snapshot = PracticeStats.Snapshot(
        streakDays: 0, totalSessions: 0, lastScorecard: nil,
        lastSessionEndedAt: nil, lastSevenDayScores: Array(repeating: 0, count: 7),
        shadowableLineCount: 0
    )
    @State private var sessionId = UUID()
    @State private var sessionStartedAt = Date()
    @State private var didSaveCurrentSession = false
    /// ✕ tapped with unsaved turns — asks save vs. discard before leaving.
    @State private var confirmingDiscard = false
    /// When the mic OPENED for the current listening turn — not when the
    /// learner started talking. The gap between the two is thinking time; the
    /// clock that matters (`speechStartedAt`) skips it.
    @State private var micOpenedAt: Date?
    /// True when the topic is a news story ("In the news" picker). The opener
    /// call then runs search-grounded and collects `newsFacts`.
    @State private var topicIsNews = false
    /// Where this talk started from — stamped onto the saved `Session` so
    /// Practice can badge the book (free / news / scenario).
    @State private var sessionOrigin: SessionOrigin = .free
    /// The scenario this talk launched from, carried onto the saved session.
    @State private var sessionScenarioId: UUID? = nil
    /// The person this talk is WITH (Find people / personas) — carried onto
    /// the saved session so their card can list every talk you've had.
    @State private var sessionCounterpartId: UUID? = nil
    /// Real facts from the grounded news lookup — injected into every turn's
    /// system prompt so the future self actually knows the story.
    @State private var newsFacts: [String] = []
    /// Raw 0…1 voice energy target for the mic pill's glow (mic RMS while
    /// listening, playback RMS while speaking). Futureself interpolates it
    /// per frame, so no smoothing here.
    @State private var voiceLevel: Float = 0

    /// What the learner is studying, offered as something to actually SAY in
    /// this call. Picked once when the call opens (a row that re-shuffled
    /// mid-conversation would be a different promise every turn) and ticked by
    /// `CarryoverDetector` — see `TalkGoalChips.swift`.
    @State private var goalItems: [TalkGoalItem] = []
    @State private var usedGoalKeys: Set<String> = []
    /// The chip the learner tapped — its meaning + an example to say. The call
    /// keeps running underneath; this never pauses anything.
    @State private var goalDetail: TalkGoalItem?
    /// Coach mode's ration for this call, and the hint on screen while the
    /// learner answers the question it was built for (`CoachMode.swift`).
    @State private var coach = CoachPlan()
    /// The steer last sent to the gateway ("" = none).
    @State private var coachSteerSent = ""
    /// Words coach mode may steer toward beyond the chip row — see
    /// `TalkGoalPicker.coachExtras`. Picked with the row, once per call.
    @State private var coachExtras: [TalkGoalItem] = []
    @State private var coachHint: TalkGoalItem?
    /// Coach mode's "try saying" for the line just spoken (`CoachSuggester`).
    @State private var coachReply: CoachReply?
    /// The coach's line belongs to the question just answered, so it goes
    /// when the reply begins — but only from SIGHT. Removing it shrank the
    /// bar at the very moment the reply's bubble pushed the feed up, and the
    /// two together read as the list jumping up and back down (2026-10-05).
    /// The slot keeps its height until the next suggestion replaces it.
    @State private var coachStale = false
    /// The last fluent-self line the gateway finished, so coach mode switched
    /// on mid-call can answer the question already on screen instead of
    /// waiting for the next line (`advanceCoach` only runs as a line ends).
    @State private var lastFinishedReply: (id: UUID, text: String)?
    /// Tutor mode as the conversation prompt has it right now (`TutorMode`).
    /// It lives in the system prompt, so a flip mid-call sends the gateway a
    /// new one (`RealtimeTalkClient.setSystem`, 2026-10-14 — it used to wait
    /// for the next call); the classic path rebuilds the prompt every turn.
    @State private var tutorThisCall = TutorMode.isOn
    /// The pronunciation call (`PronunciationCall`): opened from the Talk
    /// ring's third page, fixed for the whole call.
    @State private var pronThisCall = false
    /// The round on screen: five sentences for one sound.
    @State private var pronRound: PronunciationRound?
    /// The sound being practiced (set before its round is written).
    @State private var pronTopic: PronunciationCourse.Topic?
    /// A round is being written.
    @State private var pronPlanning = false
    /// Takes in a row that came back with nothing usable on this sentence.
    @State private var pronUnheard = 0
    /// How long the last take's assessment took (`assess_ms` on its event).
    @State private var pronAssessMs = 0
    /// The take read by Azure from the moment it was SENT (2026-11-12,
    /// founder: "the answer takes forever"). The read used to start only when
    /// the gateway's `user_turn` arrived — after its wait for the final
    /// transcript (up to 2.5 s) — and Azure alone is ~2.5 s, so the two
    /// waits ran end to end. The verdict needs the audio and the line on
    /// screen, never the transcript, so it starts at Send; `pronTurn` uses
    /// it when the turn's audio is the same take.
    @State private var pronEarly: PronEarlyRead?
    /// Each finished fluent-self line's text, by turn id: the app reads what
    /// the tutor said about a try it judged itself (`tutorReconcile`).
    @State private var finishedReplies: [UUID: String] = [:]
    /// The last take's verdict came from the early read (`early` on its event).
    @State private var pronEarlyUsed = false
    /// What each pronunciation take was a reading OF (the word or sentence
    /// on screen), shown in the learner's bubble instead of the live
    /// transcript. The verdict is the audio's; a transcript beside it said
    /// "기수전" or "think" next to a "Good" for "thank" (2026-11-06), so the
    /// bubble contradicted the card it sat under.
    @State private var pronReadTexts: [UUID: String] = [:]
    @State private var showingPronTopics = false
    /// The learner's turn to read: opened the moment the fluent self stops
    /// speaking, closed when the take is sent (`pronHeard`).
    @State private var pronWindowOpen = false
    @State private var pronSendTask: Task<Void, Never>?
    /// When the words now held started — to tell reading along (started
    /// early in the fluent self's line) from answering at its end.
    @State private var pronHeardSince: Date?
    /// Tutor mode was on at some point in this call — the whole call is then
    /// a practice call (`Session.coached`).
    @State private var tutorWasOn = TutorMode.isOn
    /// Learner turns the final check judged as a try at the whole thing — the
    /// only tutor lines saved as evidence (`Turn.tutorRole`).
    @State private var tutorCheckTurnIds: Set<UUID> = []
    /// Watched only to tell a live call when the sheet flips tutor mode.
    @AppStorage(TutorMode.key) private var tutorModeChoice = false
    /// Tutor mode's lesson (`TutorLesson`): nil until a topic is set.
    @State private var tutorLesson: TutorLesson?
    /// A curriculum is being written.
    @State private var tutorPlanning = false
    /// A challenge was ticked since the prompt was last sent — the block
    /// tells the tutor to move on.
    @State private var tutorJustTicked = false
    /// What the correction found on the learner's last try, for the block.
    @State private var tutorLastFixes: [String] = []
    /// The learner's last try on the current challenge — the line kept on
    /// the checklist when the tutor moves on by itself.
    @State private var tutorLastTry = ""
    /// The current challenge had a try that wasn't right: a right one then
    /// gets "once more" before it is ticked.
    @State private var tutorMissedThisChallenge = false
    /// The "once more" after a miss was asked for.
    @State private var tutorCleanOnce = false
    /// After a pass the learner asked to say it once more: their next line
    /// is that try.
    @State private var tutorRepeatAsked = false
    /// The lesson finished; the call ends after the tutor's goodbye.
    @State private var tutorStripExpanded = true
    @State private var showingTutorTopics = false
    /// Coach mode's grammar focus for this call (`GrammarFocus`): picked from
    /// the learner's recurring mistakes on appear, named in their language,
    /// and watched on every correction. nil = none this call.
    @State private var grammarFocus: GrammarFocus?
    /// Learner turns whose correction was the focus coming back — their card
    /// wears the badge. The count on the strip is this set's size.
    @State private var focusRepeatTurns: Set<UUID> = []
    @State private var showingFocusSheet = false

    /// Live lookup, not a copy — resolves through appState so edits to the
    /// person elsewhere are picked up, and resume restores it from the saved
    /// session's counterpartId with no extra plumbing.
    private var counterpart: Counterpart? {
        sessionCounterpartId.flatMap { id in appState.counterparts.first { $0.id == id } }
    }

    /// Who the other side's lines are labelled as. A person-talk is that
    /// person; a scenario call is its linked person, else the role the
    /// scenario names ("Interviewer"); everything else is the fluent self.
    /// A scenario with no role leaves the counterpart to the scene, and
    /// there is no name to show for that, so it stays the fluent self.
    private var otherSideName: String {
        if let counterpart { return counterpart.name }
        if let sid = sessionScenarioId,
           let s = appState.scenarios.first(where: { $0.id == sid }) {
            if let person = s.counterpartId.flatMap({ id in appState.counterparts.first { $0.id == id } }) {
                return person.name
            }
            let role = s.role.trimmingCharacters(in: .whitespacesAndNewlines)
            if !role.isEmpty { return chrome(String.LocalizationValue(role)) }
        }
        return chrome("Future self")
    }

    /// Who speaks the reply audio. A person-talk uses THAT person's preset
    /// voice — the partner is the stranger, not the fluent self. Everything
    /// else keeps the user's clone.
    private var activeVoiceId: String? {
        counterpart?.voicePresetId ?? appState.speakingVoiceId
    }

    private let userId = ProfileStore.localUserId

    enum Phase: Equatable {
        case idle
        case listening      // mic open, partial STT streaming
        case thinking       // Gemini reply in flight
        case speaking       // the fluent self's voice playing
    }

    /// Is this second of the open call actually a second of TALKING? The
    /// meter polls this once a second and charges nothing for the seconds it
    /// says no to (`TalkMeter.isBillable`), and the idle watchdog measures the
    /// same thing to decide when nobody is there.
    ///
    /// A call screen left open is not a call. The mic being hot costs the
    /// learner nothing and costs us nothing — what costs is the model writing
    /// and the voice speaking — so the yes cases are exactly the places where
    /// work is happening or has just happened:
    ///   • the fluent self is speaking (or a turn's audio is playing);
    ///   • a reply is being generated;
    ///   • the learner is talking.
    ///
    /// The learner half of that is `someoneIsTalkingHere`, which is where the
    /// café problem lives — see below.
    /// Has the learner spoken since this call started? Set where a user turn
    /// is made (both paths), cleared with the session. No longer a billing
    /// gate (see `isBillableMoment`).
    @State private var learnerSpokeThisCall = false
    /// The fluent self's spoken goodbye after End (`CallGoodbye`): the words,
    /// whether the voice is still saying them, and the task making them.
    @State private var goodbye: CallGoodbye.Line?
    @State private var goodbyePlaying = false
    @State private var goodbyeTask: Task<Void, Never>?
    @State private var goodbyeVoice: CallGoodbyeVoice?
    /// The live call died under the learner — socket gone, reply failed
    /// past its retry, mic lost after a route change. Set from the realtime
    /// state observer; presented as the one alert that offers a way BACK.
    /// Until 2026-09-12 this case had no message at all: the screen went
    /// quiet and the only move was to hang up.
    @State private var callDropped: String?
    /// Whether this call ever reached a live state — a failure before that
    /// is a connect failure and keeps its own (existing) alert.
    @State private var realtimeWasLive = false
    /// When the call last put ITSELF back together after a transport drop.
    /// The gateway's Durable Object can be reset under a live call — a deploy,
    /// or Cloudflare moving the object (prod 2026-09-15: "object was reset",
    /// no exception of ours) — and a reconnect carries the whole talk. One
    /// learner tapped Reconnect and was back in 3 s; the next hung up at the
    /// alert. So a socket drop reconnects without asking, at most once a
    /// minute: a second drop inside that is no longer a blip, and gets the
    /// alert.
    @State private var lastAutoReconnectAt: Date?
    private static let autoReconnectSpacing: TimeInterval = 60

    /// The call is billed from the moment it starts (founder, 2026-10-27):
    /// the opener and the fluent self's first lines count like every other
    /// line. Until then nothing counted before the learner's first turn
    /// (2026-09-07), with tutor mode the one exception (2026-10-25). Silence
    /// is still free: only seconds where something is happening count.
    private func isBillableMoment() -> Bool {
        // Every call counts from its start without stopping (founder,
        // 2026-11-04) until 30 s of nothing, when it puts itself down — the
        // gateway's rule too (`idleBillMs`), whose count replaces this one
        // once it reports.
        if RealtimeMode.isEnabled && phoneCallActive {
            return somethingIsHappening() || Date().timeIntervalSince(lastActivityAt) < Self.idlePauseSeconds
        }
        return somethingIsHappening()
    }

    /// Is anyone in this call right now — the fluent self speaking, a reply
    /// being written, or the learner audibly talking? The billing predicate
    /// minus its "not until their first turn" gate. The idle watch asks THIS,
    /// never `isBillableMoment`: that gate only lifts once a turn is
    /// COMMITTED, so a first answer longer than the idle bar was paused
    /// mid-sentence (2026-09-27, founder's call: 23 s of speech, 0 turns,
    /// paused at 29 s — three times in a row).
    private func somethingIsHappening() -> Bool {
        if RealtimeMode.isEnabled {
            // Same rule, read off the gateway's state instead of the local
            // VAD: the fluent self speaking, a reply being written, or the
            // learner audibly mid-utterance. An open screen in a quiet room
            // still bills nothing.
            switch realtime.state {
            case .speaking, .thinkingReply: return true
            // Send-to-answer holds words on screen while the learner thinks;
            // holding them is not someone talking — their voice is.
            case .hearing where sendToAnswer:   return realtime.level > 0.25
            case .hearing:                      return true
            case .listening:                    return realtime.level > 0.25
            default:                            return false
            }
        }
        if phase == .thinking || phase == .speaking { return true }
        if player.isPlaying { return true }
        return someoneIsTalkingHere()
    }

    /// Is the person HOLDING THE PHONE talking — as opposed to a room that is?
    ///
    /// Mic energy alone answered this until 2026-08-18, and in a café it is
    /// permanently yes: other people's voices read as the learner's, so a call
    /// nobody was speaking into never went idle (measured: >3 minutes against
    /// a 60-second bar, every second of it billed) and no turn ever ended.
    ///
    /// Three witnesses now, and the third is the one that separates a person
    /// from a room:
    ///   • the mic heard energy recently, and
    ///   • the recognizer is still making WORDS of it — room babble yields
    ///     sporadic hypotheses, a person speaking into a phone a steady
    ///     stream — and
    ///   • at least `minVoicedSecondsPerTurn` of THIS segment cleared the
    ///     voiced threshold, which after the `noiseMargin` raise means ~11 dB
    ///     over the room's own floor. A mouth 20 cm from the mic clears that;
    ///     a table two metres away mostly doesn't.
    ///
    /// Being wrong in the cautious direction is free — an unbilled second and
    /// a call that pauses a minute early. Being wrong the other way is what
    /// the learner just paid three minutes for.
    private func someoneIsTalkingHere() -> Bool {
        guard let voiced = live.lastVoicedAt,
              Date().timeIntervalSince(voiced) < TalkMeter.voiceGraceSeconds,
              let heard = live.lastLivePartialAt,
              Date().timeIntervalSince(heard) < TalkMeter.voiceGraceSeconds,
              voicedSecondsThisTurn() >= Self.minVoicedSecondsPerTurn
        else { return false }
        return true
    }

    /// When the learner actually started TALKING this turn — the mic's own
    /// open time only until the first voiced frame lands.
    ///
    /// Everything timed against it is about the person, not the microphone:
    /// how long this turn's speech ran (`Turn.durationMs`, which feeds the
    /// profile's speaking-seconds) and the 30 s listening ceiling, which used
    /// to count a long think toward a limit that exists for rooms talking
    /// into an open mic.
    private func speechStartedAt() -> Date? {
        live.firstVoicedAt ?? micOpenedAt
    }

    /// How much of the CURRENT mic run cleared the voiced threshold. The meter
    /// resets on every `live.start()`, so this is per turn by construction.
    private func voicedSecondsThisTurn() -> Double {
        live.fluencyStats().speakingSeconds
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pinned, not part of the feed: material the learner is meant
                // to reach for has to still be there at minute six, and
                // anything inside the transcript is gone after two turns.
                // The grammar focus sits above the chips: it is the one thing
                // this call is about, and the chips are the things to spend.
                if pronThisCall {
                    PronunciationCard(round: pronRound, topic: pronTopic, planning: pronPlanning,
                                      onSkip: pronSkipSentence, onLeaveWord: pronLeaveWord)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    Divider().opacity(0.15)
                }
                if tutorThisCall, tutorLesson != nil || tutorPlanning {
                    TutorLessonStrip(lesson: tutorLesson, planning: tutorPlanning,
                                     expanded: $tutorStripExpanded) {
                        dropTutorLesson(said: nil)
                    }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    Divider().opacity(0.15)
                }
                // Drawn only once the slip CAME BACK in this call (2026-10-30,
                // founder): pinned from the first second, the same focus sat
                // on top of every call for weeks and read as meaningless. The
                // focus is still picked up front and still steers questions.
                if coachMode, !tutorThisCall, let focus = grammarFocus,
                   !focusRepeatTurns.isEmpty {
                    GrammarFocusStrip(label: focus.label,
                                      mistake: focus.pattern.mistake,
                                      correction: focus.pattern.correction,
                                      talks: focus.talks,
                                      repeats: focusRepeatTurns.count) {
                        showingFocusSheet = true
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    Divider().opacity(0.15)
                }
                if !goalItems.isEmpty, showsGoalChips, !tutorInFinalCheck, !pronThisCall {
                    TalkGoalChipsRow(items: goalItems, used: usedGoalKeys) { item in
                        goalDetail = item
                    }
                    Divider().opacity(0.15)
                }
                // The transcript dissolves beneath the mic bar exactly the
                // way the Talk home dissolves beneath the tab bar — see
                // `fadingBottomBar` (2026-09-03).
                feed
                    .fadingBottomBar { bottomBar }
            }
            // The Mac: lines across a whole window are hard to read.
            .macReadingColumn()
            .background(Color(.systemBackground))
            .onChange(of: learnerSpokeThisCall) { _, spoke in
                guard spoke, islandExpanded else { return }
                withAnimation(CallIsland.motion) { islandExpanded = false }
            }
            .sheet(isPresented: $showingIslandTopics) {
                // The same ideas the home's "Find a topic" shows (2026-11-12,
                // founder): not the tutor's things to practise.
                CallTopicIdeasSheet { picked, blurb, isNews, facts in
                    islandPicked(picked, blurb: blurb, isNews: isNews, facts: facts)
                }
                .environmentObject(appState)
            }
            .overlay { endingOverlay }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                // A call screen must never auto-lock mid-sentence: a long
                // user turn has no touches, so the system idle timer fires
                // right through it. App-global UIKit flag — re-asserted on
                // every appear (a sheet on top can bounce this view's
                // appearance) and balanced in onDisappear below.
                UIApplication.shared.isIdleTimerDisabled = true
                // Place the "call" once when the seat opens.
                guard !didAutoStart else { return }
                didAutoStart = true
                phoneCallActive = true
                islandExpanded = !pronThisCall
                #if DEBUG
                if let seed = DebugCapture.callSeed {
                    applyCaptureSeed(seed)
                    return
                }
                // `-trialhandoff normal|close`: the free pool runs out and the
                // summary is closed with Done (`endAndClose`, what its
                // onDismiss runs); `close` also taps ✕ inside the account
                // lookup, which is where the report went missing in prod.
                if let mode = UserDefaults.standard.string(forKey: "trialhandoff"), !mode.isEmpty {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        print("[trialhandoff] pool spent, Done")
                        BillingGate.debugTrialSpent = true
                        freeCallSpent = true
                        endAndClose()
                        guard mode == "close" else { return }
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        print("[trialhandoff] ✕ tapped inside the lookup")
                        close()
                    }
                }
                // A beat, so the presentation isn't requested inside the
                // screen's own first appear — SwiftUI drops those.
                if DebugCapture.previewCallSettings {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        showingCallSettings = true
                    }
                }
                #endif
                // The in-call meter: wall-clock seconds tick to the server
                // for the whole life of the seat. When today's minutes run
                // out mid-call the mic closes; the line the fluent self is
                // currently speaking is allowed to finish. A FREE user's
                // spent pool leads to the paywall; a SUBSCRIBER's finished
                // day never does — they already paid, the allowance just
                // resets at midnight.
                meter.onWallHit = {
                    guard !isTornDown else { return }
                    cancelSilenceTimer()
                    if RealtimeMode.isEnabled {
                        // The gateway owns the mic on this path; hanging up is
                        // what stops it.
                        realtime.hangUp()
                    } else if phase == .listening {
                        stopListeningDiscardingChunks()
                    }
                    if phase == .listening || phase == .thinking { phase = .idle }
                    if meter.wallReason == .fairUseLimit {
                        fairUseHalted = true
                    } else if meter.wallReason == .dailyCapReached {
                        dailyCapReached = true
                    } else {
                        handleTalkPoolSpent()
                    }
                }
                // Silence isn't billed — see `isBillableMoment`. Set before
                // start(): the ticker polls it from its first second.
                meter.isBillable = { isBillableMoment() }
                // On the realtime path the GATEWAY is the meter
                // (gateway/src/billing.ts) — the local ticker only keeps the
                // ring's TalkTimeLog; charging twice would double-bill.
                meter.serverMetered = RealtimeMode.isEnabled
                meter.start(sessionId: sessionId)
                lastActivityAt = Date()   // the call starts occupied
                // Put the call on the lock screen. Play/pause there are the
                // same two things the mic button does, so a call that outlives
                // the screen can still be hung up without unlocking.
                DailyCallScheduler.holdForLiveCall()
                CallNowPlaying.begin(
                    title: callDisplayTitle,
                    onResume: { Task { if !phoneCallActive, !isTornDown { await handleMicTap() } } },
                    onPause: { Task { if phoneCallActive { await pauseCall() } } }
                )
                HapticEngine.phoneCallStarted()
                Analytics.capture("conversation_started", [
                    "origin": sessionOrigin.rawValue,
                    "entry": entry.rawValue,
                    "resumed": isResuming,
                    // This call, not the setting: the tutor bot opens a
                    // tutored call with the setting off.
                    "tutor": tutorThisCall ? "on" : "off"
                ])
                pinPromptClock()
                if isResuming {
                    // Continue from the loaded transcript — open the mic so the
                    // user picks up where they left off (Gemini already has the
                    // prior turns as context).
                    Task { await startRecording() }
                } else {
                    Task { await openConversation() }
                }
            }
            .onDisappear {
                // Balance the onAppear assert — leaving this true would keep
                // the WHOLE app from ever auto-locking.
                UIApplication.shared.isIdleTimerDisabled = false
            }
            // Drill / Shadow / History / Watch / Profile moved to dedicated
            // tabs in `RootTabView`. ConversationView now owns Talk only.
            // On the root, with the screen's other sheets — attached to the
            // bottom bar it never presented (the bar lives inside
            // `fadingBottomBar`'s overlay).
            .sheet(isPresented: $showingCallSettings) {
                // No parameters on purpose: this body re-runs on every mic
                // level tick while a call is live, and a sheet handed a fresh
                // closure each time re-rendered with it — often enough that
                // the speed menu couldn't open or take a tap until the call
                // was paused. With nothing to compare, SwiftUI leaves it alone.
                CallSettingsSheet()
            }
            .onChange(of: speechSpeedRaw) { _, new in
                // The rung is already stored (the sheet writes the same
                // defaults key Me → Voice does), so every later synthesis
                // reads it for free. Only a call ALREADY UP has to be told,
                // and only on the realtime path — the classic path asks
                // `SpeechSpeed.current` at each synthesis.
                guard RealtimeMode.isEnabled, phoneCallActive else { return }
                realtime.setSpeed(SpeechSpeed(rawValue: new) ?? .default)
            }
            .onChange(of: sendToAnswer) { _, on in
                guard RealtimeMode.isEnabled, phoneCallActive else { return }
                realtime.setManualTurns(on)
            }
            .onChange(of: tutorWasOn) { _, on in
                if on { realtime.tutorCall = true }
            }
            .onChange(of: tutorModeChoice) { _, on in applyTutorMode(on) }
            #if targetEnvironment(macCatalyst)
            // The Mac: the curriculum opens as a column beside the call, so
            // the topics and the talk are on screen together.
            .inspector(isPresented: $showingTutorTopics) {
                TutorTopicSheet(onPick: { picked, topicId in
                    startTutorLesson(request: picked, picked: true, topicId: topicId)
                }, onClose: { showingTutorTopics = false }, current: tutorLesson)
                    .environmentObject(appState)
                    .inspectorColumnWidth(min: 340, ideal: 400, max: 520)
            }
            #else
            .sheet(isPresented: $showingTutorTopics) {
                TutorTopicSheet(onPick: { picked, topicId in
                    startTutorLesson(request: picked, picked: true, topicId: topicId)
                }, current: tutorLesson)
                    .environmentObject(appState)
            }
            #endif
            .sheet(isPresented: $showingPronTopics) {
                PronunciationTopicSheet(currentId: pronTopic?.id) { topic in
                    startPronRound(topic: topic, note: PronunciationNotes.preparing(topic, picked: true))
                }
                    .environmentObject(appState)
            }
            .sheet(item: $goalDetail) { item in
                TalkGoalSheet(item: item, used: usedGoalKeys.contains(item.key))
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingFocusSheet) {
                if let focus = grammarFocus {
                    GrammarFocusSheet(label: focus.label, tip: focus.tip,
                                      mistake: focus.pattern.mistake,
                                      correction: focus.pattern.correction,
                                      talks: focus.talks,
                                      repeats: focusRepeatTurns.count)
                }
            }
            .sheet(item: summaryBinding, onDismiss: {
                let how = summaryClose
                summaryClose = .swipe
                // Closed by code (`startNewSession`) — nothing to log,
                // nothing to exit.
                guard how != .code else { return }
                // This closure has fired twice for one call (prod, d48b0216,
                // 2026-09-24): the second run logged a second close and
                // pitched the plans on top of the first.
                guard !postCallExitStarted else { return }
                postCallExitStarted = true
                let props = ["how": how.rawValue, "free_call_spent": freeCallSpent ? "1" : "0"]
                Telemetry.log("talk_summary_closed", props)
                Analytics.capture("talk_summary_closed", props)
                // BOTH exits go on from here, and only from here — after the
                // sheet is GONE. Done used to call `endAndClose()` directly,
                // which nil'd the summary and raced the plans pitch against
                // the sheet's own dismiss animation: whenever the billing
                // snapshot answered inside ~0.4 s, `showingPaywall` flipped
                // while the summary sheet was still sliding out, SwiftUI
                // presented the paywall, tore it down and presented it again,
                // and the torn-down copy's `.task` was cancelled mid
                // `Product.products(for:)` — which threw, was swallowed, and
                // left the paywall with no prices and a "Subscribe" button
                // that answered "not available on the App Store yet". Prod
                // 2026-09-24: four of the five accounts that met the free
                // pool's end saw exactly that screen; the one that didn't had
                // a 1.4 s snapshot. A swipe was already routed through this
                // closure, and it broke the same way once (d48b0216) because
                // the summary landed a second time — hence the guard above.
                if FirstCallCheckSheet.shouldShow(learnerSpoke: learnerSpokeThisCall) {
                    // Its own onDismiss continues the exit, so the plans
                    // pitch still comes — after it, never on top of it.
                    FirstCallCheckSheet.markShown()
                    firstCallCheckTrigger = .summary
                    showingFirstCallCheck = true
                } else {
                    endAndClose()
                }
            }) { s in
                SummarySheet(summary: s, sessionId: sessionId,
                             onDone: {
                                 summaryClose = .done
                                 summary = nil
                             })
                    .environmentObject(appState)
            }
            // The call dropped mid-talk. Two honest choices, and the
            // transcript stays on screen behind them.
            .alert(explain("The call dropped"), isPresented: callDroppedBinding) {
                Button(explain("Reconnect")) {
                    Telemetry.log("talk_rt_reconnect", ["turns": String(turns.count)])
                    Task { await reconnectRealtimeCall() }
                }
                Button(explain("End the call"), role: .cancel) {
                    Task { await endSession() }
                }
            } message: {
                Text(explain("Everything said so far is saved. Reconnect to carry on from where you were."))
            }
            // The title follows what happened. This alert is the call
            // screen's catch-all, so everything that lands in it inherits
            // "Something went wrong" — and a spent pool is not a fault, it is
            // the plan working as sold. Reported 2026-09-20, in those words.
            .alert(outOfCredits ? explain("Your talk time is used up")
                                : explain("Something went wrong"),
                   isPresented: errorBinding) {
                if outOfCredits {
                    Button("See plans") {
                        error = nil; paywallSource = "talk_out_of_time"; showingPaywall = true
                    }
                }
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            // A spent pool is its own SHEET. It was an alert until 2026-08-20,
            // which could state the rule but had nowhere to put the thing to
            // do next — so a month that ran out read as a dead end with an
            // upsell on it.
            .sheet(isPresented: $dailyCapReached, onDismiss: {
                switch capChoice {
                case .upgrade:
                    // The next tier up (`AccountStatus.upgradeTier`), as a tier id the
                    // paywall matches against its own — never the plan they hold.
                    paywallTier = upgradeTier ?? "plus"
                    paywallSource = "talk_spent_month"
                    showingPaywall = true
                case .review:  leaveForPractice()
                // The minutes are on the account and the gate is fresh; the
                // call is still on screen, and the next mic tap spends them.
                case .topUp:   break
                case nil:      break
                }
                capChoice = nil
            }) {
                DailyAllowanceSheet(
                    kind: .talk,
                    canUpgrade: canUpgradePlan,
                    upgradeName: AccountStatus.tierName(upgradeTier),
                    allowance: poolMinutes,
                    renewsOn: renewalLabel,
                    endsInstead: planEndsAtPeriodEnd,
                    isTrial: accountIsTrialing,
                    planMinutesAfterTrial: planMinutesAfterTrial,
                    canTopUp: canTopUpTalk,
                    invite: inviteOffer,
                    onReview: { capChoice = .review },
                    onUpgrade: { capChoice = .upgrade },
                    onTopUp: { capChoice = .topUp })
            }
            // Not a sheet and not an upsell: there is nothing to offer and
            // nothing to wait for. One line saying what happened and how to
            // reach us.
            .alert(explain("We've paused talking on this account"),
                   isPresented: $fairUseHalted) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(explain("Some unusual usage needs checking. Write to us and we'll sort it out — everything you've saved is untouched, and reviewing still works."))
            }
            .sheet(isPresented: $showingPaywall, onDismiss: {
                paywallTier = nil
                // The post-summary pitch holds the exit: the call's own
                // dismissal is what happens when the learner closes it,
                // whether they bought or not.
                if closeAfterPaywall { closeAfterPaywall = false; close() }
            }) {
                // Reached here from an out-of-credits failure → no trial pitch.
                // Opened FROM the spent-day sheet it carries the tier that
                // sheet named, so "Go Unlimited" doesn't land on Daily.
                PaywallView(source: paywallSource, preselectTier: paywallTier)
            }
            .sheet(isPresented: Binding(get: { trialReport != nil },
                                        set: { if !$0 { trialReport = nil } }),
                   onDismiss: { close() }) {
                if let trialReport {
                    WeekRecapSheet(trial: trialReport).environmentObject(appState)
                        .onAppear {
                            trialReportAppeared = true
                            #if DEBUG
                            print("[trialhandoff] report up on the call screen")
                            #endif
                        }
                }
            }
            .sheet(isPresented: $showingFirstCallCheck, onDismiss: {
                if closeAfterFirstCallCheck {
                    closeAfterFirstCallCheck = false
                    close()
                } else {
                    endAndClose()
                }
            }) {
                FirstCallCheckSheet(trigger: firstCallCheckTrigger).environmentObject(appState)
            }
            .sheet(item: $feedbackContext, onDismiss: {
                if dismissAfterFeedback { dismissAfterFeedback = false; close() }
            }) { ctx in
                FeedbackSheet(context: ctx)
            }
            .sheet(isPresented: $askingMicChoice, onDismiss: resumeAfterMicChoice) {
                MicChoiceSheet { _ in }
            }
            .sheet(isPresented: $askingFirstCallSetup, onDismiss: resumeAfterFirstCallSetup) {
                FirstCallSetupSheet().environmentObject(appState)
            }
            // Hitting the credit wall now routes to the paywall's preference
            // survey (see the "See plans" alert button) — no separate feedback
            // sheet at depletion.
            .alert("Microphone access needed", isPresented: $showMicPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not now", role: .cancel) { }
            } message: {
                Text(explain("nawana needs the microphone and speech recognition to hear you speak. Turn them on in Settings → nawana."))
            }
            .task { refreshDashboard() }
            .task {
                #if DEBUG
                if DebugCapture.callSeed != nil { return }
                #endif
                goalItems = pickGoalItems()
                coachExtras = TalkGoalPicker.coachExtras(excluding: Set(goalItems.map(\.key)))
                await loadGrammarFocus()
            }
            .onChange(of: coachMode) { _, on in
                if on, grammarFocus == nil { Task { await loadGrammarFocus() } }
                syncCoachSteer()
                // Switched on while a finished question waits for an answer:
                // suggest for it now. A line still being spoken gets its turn
                // from `onReplyFinished`; one already answered needs nothing.
                if on, coachReply == nil, let last = lastFinishedReply,
                   turns.last?.id == last.id {
                    advanceCoach(afterReply: last.text, turnId: last.id)
                }
                if !on { coachHint = nil; coachReply = nil; coachStale = false }
            }
            .task {
                let account = await AccountStatus.fetch()
                upgradeTier = account.upgradeTier
                canUpgradePlan = account.upgradeTier != nil
                canTopUpTalk = account.isEntitled && !account.isUncappedTalk && !account.isTrialing
                poolMinutes = account.monthlyCapSeconds.map { $0 / 60 }
                renewalLabel = account.renewalLabel
                planEndsAtPeriodEnd = account.cancelAtPeriodEnd
                accountIsTrialing = account.isTrialing
                planMinutesAfterTrial = account.planMonthlySeconds.map { $0 / 60 }
                inviteOffer = await InviteOffer.load(for: account)
            }
            // A real phone call, Siri, or an alarm takes the audio session
            // away and stops the engine WITHOUT going through `live.stop()`.
            // Nothing used to notice: the call stayed on screen, deaf, until
            // the learner tapped the mic twice.
            .onReceive(NotificationCenter.default.publisher(
                for: AVAudioSession.interruptionNotification)) { note in
                handleAudioInterruption(note)
            }
            // `phase` is what the rest of this screen reads: the mic hint,
            // the End button's enabled state, the thinking indicator. On the
            // realtime path nothing was setting it, so it stayed `.thinking`
            // for the whole call — and End is `.disabled(phase != .idle)`,
            // which meant a learner could not finish a talk at all, and no
            // summary, drills or book were ever produced (2026-09-01).
            .onChange(of: realtime.state) { _, state in
                guard RealtimeMode.isEnabled, phoneCallActive else { return }
                switch state {
                case .listening, .hearing: phase = .listening; realtimeWasLive = true
                case .thinkingReply:       phase = .thinking;  realtimeWasLive = true
                case .speaking:            phase = .speaking;  realtimeWasLive = true
                case .idle, .connecting, .failed: phase = .idle
                }
                // The gateway meters the call server-side and hangs up with a
                // wall code when the allowance is spent — the same two 402s
                // the classic meter's tick returns, so they land on the same
                // sheets: a subscriber's finished day is never a paywall.
                if case .failed(let message) = state {
                    if realtime.wallCode == "fair_use_limit" {
                        fairUseHalted = true
                    } else if realtime.wallCode == "daily_cap_reached" {
                        dailyCapReached = true
                    } else if realtime.wallCode == "insufficient_credits" {
                        handleTalkPoolSpent()
                    } else if realtimeWasLive {
                        // A LIVE call that failed — not a connect failure
                        // (that one is reported where the connect happens).
                        // The idle hang-up is the gateway's judgement that
                        // nobody was talking, and it says so in its message;
                        // everything else deserves the way back.
                        if realtime.lastFailureCode == "idle" {
                            error = message
                        } else if realtime.lastFailureCode == "socket", !isTornDown,
                                  lastAutoReconnectAt.map({ Date().timeIntervalSince($0)
                                      > Self.autoReconnectSpacing }) ?? true {
                            lastAutoReconnectAt = Date()
                            Telemetry.log("talk_rt_reconnect", ["turns": String(turns.count),
                                                                "auto": "1"])
                            Task { await reconnectRealtimeCall() }
                        } else {
                            callDropped = message
                        }
                        realtimeWasLive = false
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Coming back to a call that should be listening but isn't.
                guard newPhase == .active else { return }
                Task { await resumeCallIfStalled() }
            }
            .onChange(of: topic) { _, newTopic in
                CallNowPlaying.update(title: callDisplayTitle, isPlaying: phoneCallActive)
                // Topic just got picked → opener appears AND we auto-enter
                // phone-call mode. Zero-tap start: the user's scenario pick
                // IS the "I want to talk now" signal. They can hang up via
                // the End button (or by tapping mic again) when they're done.
                guard !newTopic.isEmpty, turns.isEmpty, phase == .idle else { return }
                phoneCallActive = true
                HapticEngine.phoneCallStarted()
                Task { await openConversation() }
            }
        }
        .overlay(alignment: .top) {
            if let barY = islandBarY {
                GeometryReader { geo in
                    CallIsland(title: islandTitle, level: appState.proficiency,
                               minutesLeft: meter.minutesRemaining.flatMap { $0 <= 10 ? $0 : nil },
                               callClock: (phoneCallActive || !didSaveCurrentSession) ? meter.clock : nil,
                               halfRate: pronThisCall,
                               guidance: islandCanChange ? islandGuidance : nil,
                               guidanceChoices: PronunciationCall.isOffered(for: appState.targetLanguage)
                                   ? [.free, .tutor, .pronunciation] : [.free, .tutor],
                               onChangeTopic: islandCanChange ? { islandChangeTopic() } : nil,
                               onSettings: { showingCallSettings = true },
                               expanded: $islandExpanded)
                        .frame(maxWidth: .infinity)
                        .padding(.top, max(0, barY - geo.frame(in: .global).minY))
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Two-line title: the topic, and the level the fluent self is speaking
        // at. Replaces `.navigationTitle` — a principal item is the only way
        // to get a second line into an inline bar.
        ToolbarItem(placement: .principal) {
            // `minutesLeft` stays nil (hidden) while there's plenty of talk
            // time — a visible meter is exactly the anxiety the minutes model
            // removed. The clock joins the subtitle for the last stretch so
            // the wall never lands as a surprise.
            // A news call is titled "News": its topic is a whole spoken line
            // ("Did you see the news about…?"), which only ever fit the bar
            // cut off with an ellipsis.
            // The island is drawn over the whole stack (it grows past the
            // bar), so the title slot only says where the bar puts it. A
            // pronunciation call has it too (2026-11-12): it is one of the
            // island's three modes, and the island is the way back out.
            Color.clear
                .frame(width: 1, height: CallIsland.pillHeight)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { islandBarY = $0 }
        }
        // The open island lies over the bar; its buttons would show through
        // the glass at both ends, so they step out while it is open.
        if !islandExpanded {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                // A talk with unsaved turns doesn't just vanish on a stray ✕
                // tap — closing is gated behind an explicit choice between
                // saving (the End flow: summary + drills) and discarding.
                // Only the USER's turns count: if all that happened is the
                // fluent self's opener, there's nothing worth saving.
                if turns.contains(where: { $0.role == .user }) && !didSaveCurrentSession
                    && !pronThisCall {
                    confirmingDiscard = true
                } else {
                    close()
                }
            } label: {
                Label("Close", systemImage: "xmark")
            }
            // The Mac's bar draws a Label's title beside its icon ("✕ Cl…").
            .labelStyle(.iconOnly)
            // Anchored on the ✕ itself, not on the screen: iOS presents a
            // confirmation dialog as a popover that emerges from the view the
            // modifier hangs off. Attached to the root container it pointed at
            // the bottom-center mic pill — the one control it has nothing to
            // do with. Keep it here so the sheet grows out of the button the
            // user actually tapped.
            .confirmationDialog("This conversation isn't saved yet",
                                isPresented: $confirmingDiscard,
                                titleVisibility: .visible) {
                Button("Save conversation") {
                    Task { await endSession() }
                }
                Button("Close without saving", role: .destructive) {
                    close()
                }
            } message: {
                Text(explain("Saving wraps up the talk and keeps the transcript, feedback, and drills."))
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !turns.isEmpty {
                Button(role: .destructive) {
                    Task { await endSession() }
                } label: {
                    Text("End")
                        .fontWeight(.semibold)
                }
                // Always tappable. It used to wait for `.idle`, which meant
                // hanging up was a two-step: pause the call, THEN end it —
                // and nobody expects a phone to work that way (requested
                // 2026-09-01). `endSession` already stops the mic, the
                // player and the realtime socket from any phase.
            }
        }
        }
    }

    // MARK: - Ending overlay

    /// Shown while `endSession` generates the summary. Covers the screen with
    /// a translucent veil + spinner so tapping End reads as "working on it",
    /// not a frozen, silent pause before the summary sheet appears.
    @ViewBuilder
    private var endingOverlay: some View {
        if isEnding {
            ZStack {
                Color(.systemBackground).opacity(0.95).ignoresSafeArea()
                VStack(spacing: 8) {
                    SummaryProgressView(progress: summaryProgress, facts: talkFacts,
                                        banner: freeCallSpent
                                            ? explain("Your free talk time is used up")
                                            : nil)
                    if let goodbye {
                        CallGoodbyeCard(line: goodbye, isPlaying: goodbyePlaying, onStop: stopGoodbye)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: goodbye)
            }
            .transition(.opacity)
        }
    }

    /// What we already know about the talk the moment it ends — turns spoken
    /// and how long it ran. Shown under the analysis step so the longest wait
    /// says something true instead of nothing.
    private var talkFacts: String {
        let spoken = turns.filter { $0.role == .user }.count
        let minutes = max(1, Int(Date().timeIntervalSince(sessionStartedAt) / 60))
        return explain("\(spoken) of your turns · \(minutes) min")
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if turns.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(topic.isEmpty ? "Starting your conversation…" : "Setting the scene…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                    }
                    // Subtitles off: no words on the screen at all, which is
                    // what a phone call looks like. The Futureself pill is the
                    // state display (it ignites with the learner's voice,
                    // scans while thinking, blooms while speaking) and the
                    // hint under it names the state in words, so nothing is
                    // lost but the reading.
                    if !showsTranscript, !turns.isEmpty {
                        Text(explain("Subtitles are off"))
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                    }
                    if showsTranscript {
                        ForEach(visibleTurns) { turn in
                            // No implicit morph between adjacent turns — each
                            // bubble fades in / out cleanly. Prevents the
                            // previous bubble's text from being visible inside
                            // the next one during insertion animation.
                            TurnView(turn: turn, nativeLanguage: appState.nativeLanguage,
                                     focusRepeatLabel: focusRepeatTurns.contains(turn.id)
                                        ? grammarFocus?.label : nil,
                                     translates: !LanguageCatalog.sameLanguage(appState.targetLanguage,
                                                                               appState.nativeLanguage),
                                     showsCorrections: showsCorrections,
                                     otherName: otherSideName,
                                     readText: turn.role == .user ? pronReadTexts[turn.id] : nil)
                                .id(turn.id)
                                // A reply arrives already growing; sliding it
                                // up from below on top of that read as a jolt.
                                // Nor does it fade in as a whole: it replaces
                                // the thinking line, which leaves at once, and
                                // a fade from clear left an empty beat between
                                // the two — a blink every reply (2026-10-15).
                                // Its words already fade in one by one.
                                // The learner's line is the same case: it
                                // replaces the live bubble that was showing
                                // those words, which leaves at once, so a
                                // fade + slide in made the sentence vanish
                                // and come back on every turn (2026-10-24).
                                .transition(.identity)
                        }
                    }
                    if RealtimeMode.isEnabled {
                        // Same rule as the classic path below: the listening
                        // bubble appears the moment it is the learner's turn,
                        // EMPTY, and fills as they speak. Gating it on text
                        // was tried and read as the app not listening — the
                        // empty bubble IS the "your turn" signal
                        // (2026-09-01).
                        switch realtime.state {
                        case .listening, .hearing:
                            // ...except before the FIRST turn exists: the call
                            // always opens with the fluent self, and the beat
                            // between "gateway ready" and the opener's first
                            // delta flashed an empty You bubble that blinked
                            // away as the voice began (reported 2026-09-03).
                            // A learner actually speaking first still shows —
                            // their partial has text.
                            if showsTranscript,
                               !turns.isEmpty || !realtime.partial.isEmpty {
                                PartialTurnView(text: realtime.partial)
                                    .id("partial-listening")
                                    .transition(Self.placeholderTransition)
                            }
                        default:
                            // No "… is thinking" line in the feed (founder,
                            // 2026-10-20): the pill and the hint under it
                            // already say so, and the beat before the voice
                            // is about a second — a line that appears and
                            // goes in that second read as a flicker.
                            EmptyView()
                        }
                    } else if phase == .listening, showsTranscript {
                        // Its own id + an explicit opacity transition, so
                        // SwiftUI never morphs one row's text into another's.
                        PartialTurnView(text: live.transcript)
                            .id("partial-listening")
                            .transition(Self.placeholderTransition)
                    } else if phase == .thinking && (turns.last?.role == .user) {
                        // The pill says it (see above); nothing in the feed.
                        EmptyView()
                    } else if let fid = failedTurnId, turns.last?.id == fid {
                        RetryReplyRow(outOfCredits: outOfCredits,
                                      onRetry: retryReply,
                                      onGetCredits: {
                                          paywallSource = "talk_retry_row"
                                          showingPaywall = true
                                      })
                            .id("retry-row")
                            .transition(.opacity)
                    }
                    // Bottom spacer so the last line isn't hidden behind controls
                    Color.clear.frame(height: 8).id(Self.bottomId)
                        .background(GeometryReader { g in
                            Color.clear.preference(
                                key: FeedTailOffsetKey.self,
                                value: g.frame(in: .named(Self.feedSpace)).minY)
                        })
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
                // Everything that changes the feed's height lands on its own
                // clock — a correction card a second after the line, the
                // reply's bubble, the thinking line going. Applied bare, each
                // one jumped the content and the scroll then chased it, which
                // read as the new bubble arriving with a jolt (2026-10-05).
                // Animated, the growth and the scroll move together.
                .animation(.easeOut(duration: 0.25), value: visibleTurns.count)
                .animation(.easeOut(duration: 0.25), value: suggestionsShown)
                .animation(.easeOut(duration: 0.25), value: realtime.state)
                .animation(.easeOut(duration: 0.25), value: replyHasNoWordsYet)
            }
            .coordinateSpace(name: Self.feedSpace)
            // While following, the bottom is the anchor: when the feed grows
            // or shrinks the scroll view keeps its END in place itself, in
            // the same frame, instead of the content moving first and a
            // scrollTo chasing it. Off while the learner reads back, so the
            // lines they are reading don't move under them.
            .defaultScrollAnchor(followTail ? .bottom : nil)
            // Background, so measuring the viewport can't affect the layout
            // it is measuring.
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { feedViewportHeight = g.size.height }
                    .onChange(of: g.size.height) { _, h in feedViewportHeight = h }
            })
            // Scrolling back to the end opts back in — the same gesture that
            // opted out, in reverse. Only ever turns following ON: see
            // `followTail`.
            .onPreferenceChange(FeedTailOffsetKey.self) { minY in
                guard minY <= feedViewportHeight + Self.tailSlack else { return }
                if !followTail { followTail = true }
            }
            // The learner's hand outranks the transcript. `simultaneous` so
            // the scroll view still scrolls normally; the minimum distance
            // keeps a tap on a bubble from counting.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { _ in
                    if followTail { followTail = false }
                }
            )
            .onChange(of: visibleTurns.count) { _, _ in scroll(proxy) }
            .onChange(of: phase)       { _, _ in scroll(proxy) }
            .onChange(of: live.transcript) { _, _ in scroll(proxy) }
            .onChange(of: realtime.partial) { _, p in
                scroll(proxy)
                armEarlyCorrection(p)
            }
            // A correction card grows the LEARNER's bubble, mid-list, often
            // while the reply below it is still being revealed. The bottom
            // anchor already moves the end with it in the same animation; a
            // second scrollTo on its own curve on top of that is what made
            // the whole list sway (2026-10-11).
            .onChange(of: suggestionsShown) { _, _ in scroll(proxy, immediate: false) }
            // A streaming reply changes this on every delta. While following,
            // the bottom anchor already keeps the end in place in the same
            // frame; an animated scrollTo restarted per delta was a second
            // motion on another curve (2026-10-08). Only the settle pass runs.
            .onChange(of: turns.last?.transcript) { _, _ in
                scroll(proxy, immediate: turns.last?.role != .fluentSelf)
            }
        }
    }

    /// The live line ("listening", "thinking") is REPLACED by the bubble
    /// that follows it, so it leaves at once. Faded out, it kept its height
    /// while the new bubble came in, the feed was briefly taller by one
    /// line, the scroll went to that bottom and then settled back — the list
    /// rising and dropping a little every turn (2026-10-05).
    static let placeholderTransition = AnyTransition.asymmetric(insertion: .opacity,
                                                                removal: .identity)

    private static let partialId = "partial-indicator"
    private static let bottomId  = "feed-bottom"
    private static let feedSpace = "conversation-feed"
    /// How near the end still counts as being at the end. A live partial
    /// bubble grows a line at a time, so an exact test would drop following
    /// on the learner's own next word.
    private static let tailSlack: CGFloat = 64

    /// A fluent-self bubble is appended the moment its reply begins
    /// (`onReplyBegan`), before the first word. Drawn then, it appeared as an
    /// empty bubble and grew twice — its first line, then the Meaning row —
    /// each a step the scroll had to catch up with.
    private var replyHasNoWordsYet: Bool {
        guard let last = turns.last else { return false }
        return last.role == .fluentSelf && last.transcript.isEmpty
    }

    private var visibleTurns: [Turn] {
        replyHasNoWordsYet ? Array(turns.dropLast()) : turns
    }

    private func scroll(_ proxy: ScrollViewProxy, immediate: Bool = true) {
        guard followTail else { return }
        if immediate {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(Self.bottomId, anchor: .bottom)
            }
        }
        // One settle pass, not one per change: a streaming reply calls this
        // on every delta, and a stack of late passes each re-aiming the
        // scroll was a stutter of its own.
        settleScroll?.cancel()
        // A bubble grows AFTER the state that produced it: a correction card
        // appearing, a reply's text filling in. Scrolling once aims at the
        // layout as it was, and the content that arrives a frame later ends up
        // below the fold. A second pass, once it has settled, is what keeps
        // the newest line on screen.
        // It waits out the feed's own 0.25 s height animation: fired inside
        // it, the pass aimed at a layout still moving and corrected again
        // once it stopped — a sway on every card.
        settleScroll = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, followTail, !isTornDown else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(Self.bottomId, anchor: .bottom)
            }
        }
    }

    // MARK: - Bottom bar (mic + level)

    private var bottomBar: some View {
        VStack(spacing: 10) {
            // Coach mode's help sits HERE, right above the pill, and never in
            // the learner's listening bubble (2026-10-01, device test): the
            // suggestion lands a beat after the bubble is drawn, the bubble
            // grew under the bar with nothing scrolling it back into view,
            // and "Listening…" beside a bold sentence read as two voices in
            // one shape. A fixed spot can't be scrolled away.
            // `geometryGroup` on both: they are inserted or re-filled inside
            // an animation while the bar above the pill changes height, and
            // without it their text is laid out from the slot's origin and
            // animated into place — the whole block dropped in from the
            // upper left instead of fading where it sits.
            if let reply = coachReply, !tutorInFinalCheck {
                CoachReplyLabel(reply: reply)
                    .padding(.horizontal, 32)
                    .geometryGroup()
                    .opacity(coachStale ? 0 : 1)
                    .accessibilityHidden(coachStale)
                    .transition(.opacity)
            }
            if let item = coachHint, !tutorInFinalCheck {
                CoachHintLine(item: item, used: usedGoalKeys.contains(item.key)) {
                    goalDetail = item
                }
                .geometryGroup()
                .opacity(coachStale ? 0 : 1)
                .allowsHitTesting(!coachStale)
                .accessibilityHidden(coachStale)
                .transition(.opacity)
            }
            // A ZStack, not an HStack: the pill is centred by
            // `frame(maxWidth: .infinity)` on the bar, and a sibling in a row
            // would push it off centre. The settings button is laid OVER the
            // pill's row and pinned left, so the pill stays exactly where it
            // has always been.
            //
            // Bottom-left is the only empty corner on this screen: the toolbar
            // is full (✕ · topic + clock · End) and the bar below held one
            // control. Nothing is put on the right — a second button invented
            // for symmetry is what the UI rules exist to prevent.
            ZStack {
            // The pixel grid lives INSIDE the pill, not across the screen.
            // The shader paints the whole surface theme-aware in a pure-blue
            // mosaic: airy white with blue pixels in light mode, near-black
            // with sky pixels in dark.
            Button {
                // Send-to-answer: while it is the learner's turn the pill IS
                // Send. Outside the turn it is the pill it always was.
                if sendReady {
                    guard !realtime.sendPending else { return }
                    HapticEngine.selection()
                    if pronThisCall { pronStartEarlyRead() }
                    realtime.sendTurn()
                    return
                }
                Task { await handleMicTap() }
            } label: {
                ZStack {
                    Futureself(mode: glowMode, level: voiceLevel)
                    if sendReady {
                        Group {
                            if realtime.sendPending {
                                ProgressView()
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .transition(.opacity)
                    }
                    // Glyph ONLY while the conversation is stopped — an
                    // invitation to talk. During the call the living surface
                    // itself is the state display (ignites with your voice,
                    // scans while thinking, blooms while speaking); an icon on
                    // top just fights the pixels and reads poorly.
                    if let symbol = micSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                            .transition(.opacity)
                    }
                }
                .frame(width: 156, height: 64)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
                // The shader is `.allowsHitTesting(false)`, so with the glyph
                // gone (on call) the label had NO tappable content and the
                // hang-up tap silently died. Make the whole capsule the target.
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(micA11yLabel))

            HStack {
                callSettingsButton
                Spacer(minLength: 0)
                // Send-to-answer's reset, mirroring the settings button, and
                // only once there are words to send (founder, 2026-10-26: on
                // an empty turn it covered the topic button). Held in place
                // (hidden, not removed) for the whole call so nothing shifts.
                // Tutor mode's topic button holds this spot the rest of the
                // time.
                if sendReady {
                    clearTurnButton
                } else if pronThisCall && RealtimeMode.isEnabled && phoneCallActive {
                    pronTopicButton
                } else if tutorThisCall && RealtimeMode.isEnabled && phoneCallActive {
                    tutorTopicButton
                } else if sendToAnswer && RealtimeMode.isEnabled && phoneCallActive {
                    clearTurnButton
                        .opacity(0)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 24)
            }

            Text(micHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: 16)
                .animation(nil, value: phase)
                // The pronunciation call's and a tutor lesson's turn-taking
                // (`appSendsTurns`) rides on the pill's caption, which is
                // there for the whole call.
                .onChange(of: realtime.state) { old, new in pronStateChanged(from: old, to: new) }
                .onChange(of: realtime.partial) { _, p in pronHeard(p) }
                .onChange(of: realtime.sendPending) { _, pending in pronSendSettled(pending) }
        }
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        // No background of its own — the feed's edge treatment beneath it
        // comes from `fadingBottomBar`.
        .onChange(of: live.level) { _, new in
            guard phase == .listening else { return }
            voiceLevel = new
        }
        .onChange(of: player.level) { _, new in
            guard phase == .speaking else { return }
            voiceLevel = new
        }
        // The gateway's own meter drives the pill: `live` and `player` are
        // both idle on this path, so without this the grid sat dead while the
        // learner talked (2026-09-01).
        .onChange(of: realtime.level) { _, new in
            guard RealtimeMode.isEnabled else { return }
            voiceLevel = new
        }
        .onChange(of: phase) { _, _ in voiceLevel = 0 }
    }

    /// Send-to-answer and it is the learner's turn: the pill sends.
    private var sendModeActive: Bool {
        guard sendToAnswer, RealtimeMode.isEnabled, phoneCallActive else { return false }
        switch realtime.state {
        case .listening, .hearing: return true
        default:                   return realtime.sendPending
        }
    }

    /// Send-to-answer once the learner has started: the pill is Send and
    /// reset sits beside it. Before the first word the turn looks like any
    /// other — the pill stops the call, the topic button stays.
    private var sendReady: Bool {
        sendModeActive && (hasHeldWords || realtime.sendPending)
    }

    private var hasHeldWords: Bool {
        !realtime.partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The pronunciation call: the course of sounds.
    private var pronTopicButton: some View {
        Button {
            showingPronTopics = true
        } label: {
            Image(systemName: "character.book.closed")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(pronPlanning)
        .accessibilityLabel(Text(explain("Sounds to practice")))
    }

    /// Tutor mode: topics to practice, for a learner with no idea. Same
    /// shape as the settings button on the other side of the pill.
    private var tutorTopicButton: some View {
        Button {
            showingTutorTopics = true
        } label: {
            Image(systemName: "lightbulb")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(tutorPlanning || tutorInFinalCheck)
        .opacity(tutorInFinalCheck ? 0.3 : 1)
        .accessibilityLabel(Text(explain("What to practice")))
    }

    /// Throw this turn away and say it again. Same shape as the settings
    /// button on the other side of the pill.
    private var clearTurnButton: some View {
        Button {
            realtime.discardTurn()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!hasHeldWords || realtime.sendPending)
        .opacity(hasHeldWords && !realtime.sendPending ? 1 : 0.4)
        .accessibilityLabel(Text(explain("Clear")))
    }

    /// Adjust the call while it runs — speed, subtitles, corrections, chips.
    /// Deliberately quiet: a bordered accent button next to the pill read as
    /// a second primary action, and the one primary action on a call screen
    /// is the pill.
    private var callSettingsButton: some View {
        Button {
            showingCallSettings = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(explain("Call settings")))
    }

    private var glowMode: Futureself.Mode {
        if RealtimeMode.isEnabled {
            switch realtime.state {
            case .speaking:                 return .speaking
            case .hearing, .listening:      return .listening
            case .connecting, .thinkingReply: return .thinking
            default:                        return .idle
            }
        }
        switch phase {
        case .idle:      return .idle
        case .listening: return .listening
        case .thinking:  return .thinking
        case .speaking:  return .speaking
        }
    }


    /// nil while on call — the Futureself surface carries the state; the mic
    /// glyph appears only when the conversation is stopped (tap to start).
    private var micSymbol: String? {
        phoneCallActive ? nil : "mic.fill"
    }

    private var micA11yLabel: String {
        if sendReady { return explain("Send") }
        if phoneCallActive {
            switch phase {
            case .listening: return explain("Listening — tap to hang up")
            case .thinking:  return explain("Thinking")
            case .speaking:  return explain("Future self speaking — tap to hang up")
            case .idle:      return explain("Hang up")
            }
        }
        if isPausedForIdle { return explain("Call paused — tap to pick it back up") }
        return turns.isEmpty ? explain("Start phone-call mode") : explain("Resume phone-call mode")
    }

    /// Where a scenario call takes place and who the other side is, for the
    /// "try saying" coach — "What can I get you?" only has one natural
    /// answer once it knows it is a café. nil on every other call.
    private var coachSituation: String? {
        guard let sid = sessionScenarioId,
              let s = appState.scenarios.first(where: { $0.id == sid }) else { return nil }
        let role = s.role.trimmingCharacters(in: .whitespaces)
        let place = role.isEmpty ? s.environment : "\(s.environment) — talking with \(role)"
        guard let side = StarterSituation.of(s)?.learnerSide else { return place }
        return "\(place). \(side)"
    }

    /// Who the "try saying" coach is answering, so a best friend, a stranger
    /// and a singer don't all get the same line. The fluent self on a call
    /// with no person and no scene; nil in a scene with no person (its
    /// situation already names the role) and on a tutor call.
    private var coachOtherSpeaker: String? {
        let scenario = sessionScenarioId.flatMap { sid in appState.scenarios.first { $0.id == sid } }
        let person = counterpart ?? scenario?.counterpartId.flatMap { id in
            appState.counterparts.first { $0.id == id }
        }
        guard let person else {
            if scenario != nil || tutorThisCall { return nil }
            return "the learner's own future self, a few years on and fluent. They talk like one person talking to themselves: casual, close, nothing to introduce."
        }
        let name = person.name.trimmingCharacters(in: .whitespaces)
        switch person.cast {
        case .publicFigure:
            let identity = person.publicIdentity?.trimmingCharacters(in: .whitespaces) ?? ""
            return "\(identity.isEmpty ? name : identity), a public figure. The learner knows of them; they don't know the learner."
        case .stranger:
            return "\(name), someone the learner has just met. New acquaintances, no shared history."
        case .ownPerson:
            let relation = person.relationship.trimmingCharacters(in: .whitespaces)
            let who = relation.isEmpty ? name : "\(name) (\(relation))"
            return "\(who), someone from the learner's own life. They already know each other\(person.isClose ? " well" : "")."
        }
    }

    /// What the "try saying" coach may fill a bracket with: the learner's own
    /// facts. On a call with a stranger or a public figure, only what the
    /// learner lets strangers hear — the suggestion is said TO them.
    private var coachAboutLearner: [String] {
        guard let p = appState.persona else { return [] }
        var lines: [String] = []
        if !p.displayName.isEmpty { lines.append("Name: \(p.displayName)") }
        let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty { lines.append("Lives in: \(place)") }
        if !p.occupation.isEmpty { lines.append("Does: \(p.occupation)") }
        if !p.interests.isEmpty { lines.append("Into: \(p.interests.joined(separator: ", "))") }
        if let cast = counterpart?.cast, cast != .ownPerson {
            return lines + p.strangerLines.suffix(CoachSuggester.maxFacts)
        }
        if !p.household.isEmpty { lines.append("Household: \(p.household)") }
        return lines + p.currentNotes().suffix(CoachSuggester.maxFacts).map(\.text)
    }

    /// How the learner speaks on this call, for the "try saying" coach — the
    /// same level the call prompt gives the other side. With the fluent self
    /// it is 반말 / du / tu (they are talking to themselves); with a person,
    /// what the learner set for them, else what the relationship implies. nil
    /// in a scene with no person: the scene decides, and the coach keeps the
    /// level of its previous suggestion.
    private var coachRegister: SpeechRegister? {
        let scenario = sessionScenarioId.flatMap { sid in appState.scenarios.first { $0.id == sid } }
        let person = counterpart ?? scenario?.counterpartId.flatMap { id in
            appState.counterparts.first { $0.id == id }
        }
        if let person { return person.effectiveMyRegister ?? (person.isClose ? .casual : .polite) }
        return scenario == nil ? .casual : nil
    }

    /// The example first line when this call's situation is one the learner
    /// opens (`StarterSituation.learnerFirst`); nil for every other call.
    private var learnerOpensLine: (say: String, meaning: String)? {
        guard let sid = sessionScenarioId,
              let starter = StarterSituation.of(appState.scenarios.first { $0.id == sid }),
              let say = starter.learnerFirstLine(language: appState.targetLanguage) else { return nil }
        return (say, starter.learnerFirstMeaning ?? "")
    }

    /// With the pill glyph-free while on call, this line is the ONE place
    /// that says tapping hangs up — every in-call state must name it.
    private var micHint: String {
        if phoneCallActive {
            // The written greeting is late and the line is open: say so, or
            // the call reads as dead (2026-09-13 — a scenario opener that
            // never came back left 37 seconds of unexplained silence).
            if openerIsLate, turns.isEmpty, phase == .listening {
                return explain("You can start — go ahead")
            }
            switch phase {
            case .listening where sendModeActive:
                return hasHeldWords
                    ? explain("Take your time · tap to send")
                    : explain("Speak, then tap to send")
            case .listening: return explain("Listening · pause to send · tap to stop")
            case .thinking:  return explain("Thinking… · tap to stop")
            case .speaking:
                // On the realtime path the learner CAN cut in, and the
                // hint is the only place that says so.
                return RealtimeMode.isEnabled
                    ? explain("Speaking… · talk over it · tap to stop")
                    : explain("Speaking… · tap to stop")
            case .idle:      return explain("On call · tap to stop")
            }
        }
        // A call that put itself down says so. Without this the screen looks
        // identical to one the learner stopped on purpose, and the only clue
        // that three minutes passed is that nothing is happening.
        if isPausedForIdle { return explain("Paused — tap to pick it back up") }
        return turns.isEmpty ? explain("Tap to start a phone-call") : explain("Tap to continue")
    }

    // MARK: - Bindings

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    private var callDroppedBinding: Binding<Bool> {
        Binding(get: { callDropped != nil }, set: { if !$0 { callDropped = nil } })
    }

    private var summaryBinding: Binding<SessionSummary?> {
        Binding(get: { summary }, set: { summary = $0 })
    }

    // MARK: - Flow

    private func handleMicTap() async {
        if phoneCallActive {
            // Tap during an active phone call = put it down.
            await pauseCall()
            return
        }
        // Start a phone call. Avatar's reply will auto-restart listening.
        phoneCallActive = true
        HapticEngine.phoneCallStarted()
        CallNowPlaying.update(title: callDisplayTitle, isPlaying: true)
        lastActivityAt = Date()   // a tap is someone being here
        if RealtimeMode.isEnabled {
            // Picking a paused call back up: reconnect with the transcript so
            // far as context, and no opener — the fluent self already spoke.
            await startRealtimeCall(opener: nil)
            return
        }
        await startRecording()
    }

    /// Put the call DOWN — not away. The mic closes and the meter goes quiet,
    /// but the transcript stays on screen and tapping the pill picks the same
    /// session up where it stopped. Nothing is saved, summarized or discarded
    /// here; that only happens on End (`endSession`) and on discard.
    ///
    /// Every "stop" in this screen lands here: the mic tap, the lock screen's
    /// pause, and the idle watchdog. It used to be called `endPhoneCall`, which
    /// described none of that.
    private func pauseCall() async {
        phoneCallActive = false
        cancelSilenceTimer()
        cancelIdleWatch()
        if RealtimeMode.isEnabled {
            // The gateway holds the mic and the sockets; putting the call
            // down has to reach it, or the room keeps streaming.
            realtime.hangUp()
            phase = .idle
            CallNowPlaying.update(title: callDisplayTitle, isPlaying: false)
            HapticEngine.phoneCallEnded()
            return
        }
        if phase == .listening {
            stopListeningDiscardingChunks()
        }
        if phase == .speaking {
            player.stop()
        }
        phase = .idle
        CallNowPlaying.update(title: callDisplayTitle, isPlaying: false)
        HapticEngine.phoneCallEnded()
    }

    // MARK: - Nobody's there

    /// How long a call may hear nothing at all before it puts itself down.
    ///
    /// Not a billing rule — idle seconds already cost nothing (`TalkMeter`).
    /// This is about the open mic: a call the learner walked away from, or one
    /// riding in a pocket, keeps the microphone live indefinitely, and the
    /// first voice it hears — a TV, someone else in the room — reads as the
    /// learner talking and gets both billed and answered.
    ///
    /// How long a call may go without anyone in it before it puts itself down.
    ///
    /// 30s of nothing — no close-mic voice, no reply in flight, no line being
    /// spoken — is already a long silence in a conversation. Started at three
    /// minutes, then a minute; both were a long time to sit with an open mic.
    ///
    /// The floor on this number is the learner who thinks for a long while and
    /// then speaks: once the mic closes we can't hear them start again, so
    /// they talk into nothing until they look at the screen. At 30s that is
    /// still an unusual pause, and the recovery is one tap on a screen that
    /// never lost the conversation.
    private static let idlePauseSeconds: Double = 30
    private static let idlePauseHoldingSeconds: Double = 120
    /// Coarse on purpose: nothing here needs to be precise to the second. It
    /// also bounds the overshoot — the pause lands within a tick of the bar.
    private static let idleWatchTickSeconds: Double = 5

    /// True when the watchdog was the one that stopped the call — the only
    /// difference it makes is the hint under the pill, so a learner coming
    /// back to a quiet screen reads "paused" instead of wondering what broke.
    @State private var isPausedForIdle = false
    /// A tutor note written while the call was paused (`tutorNudge`).
    @State private var pendingTutorNudge: String?
    /// How long a held tutor turn waits (2026-11-06): when the learner's
    /// turn reached the app, when the app's note went out, and what the note
    /// was. Reported once the reply begins (`tutor_turn_wait`).
    @State private var tutorWaitTurnAt: Date?
    @State private var tutorWaitNoteAt: Date?
    @State private var tutorWaitKind = ""
    /// The correction asked for before Send (`armEarlyCorrection`).
    @State private var earlyCorrection: (said: String, task: Task<ConversationTurnPayload?, Never>)?
    @State private var earlyCorrectionTimer: Task<Void, Never>?
    @State private var earlyCorrectionFires = 0
    /// For `tutor_turn_wait`: was the turn's correction the early one, and
    /// how many early ones were asked for it.
    @State private var earlyCorrectionUsed = false
    @State private var earlyCorrectionFired = 0
    /// Corrections of held tutor turns, shown when the tutor's reply begins.
    @State private var heldSuggestions: [UUID: TurnSuggestion] = [:]
    @State private var idleWatchTask: Task<Void, Never>?
    /// The last moment anything real happened. Deliberately OUTSIDE the watch
    /// task: the task is re-armed every time the mic opens, and a noisy room
    /// reopens it every 30s (`restartListeningQuietly`). A clock living inside
    /// the task would be reset by each of those restarts and the call would
    /// never pause — which is exactly the bug the restart was introduced to
    /// solve. Only real activity moves this.
    @State private var lastActivityAt = Date()

    /// Watch for a call with nobody in it.
    private func startIdleWatch() {
        cancelIdleWatch()
        idleWatchTask = Task { @MainActor in
            while !Task.isCancelled, phoneCallActive, !isTornDown {
                try? await Task.sleep(for: .seconds(Self.idleWatchTickSeconds))
                guard !Task.isCancelled, phoneCallActive, !isTornDown else { return }
                // The meter's predicate without its first-turn gate: silence
                // it bills nothing for, but a first answer still in progress
                // is someone being here.
                // Picking a topic or waiting for its plan is someone being
                // here (device, 2026-10-28: the call put itself down while
                // the learner chose in the topic sheet, and the lesson's
                // "ready" note went into a hung-up call).
                if somethingIsHappening() || showingTutorTopics || tutorPlanning
                    || showingPronTopics || pronPlanning {
                    lastActivityAt = Date(); continue
                }
                // Send-to-answer with words held: they are composing, not
                // gone — a longer wait before the call puts itself down.
                let bar = sendToAnswer && !realtime.partial.isEmpty
                    ? Self.idlePauseHoldingSeconds : Self.idlePauseSeconds
                guard Date().timeIntervalSince(lastActivityAt) >= bar else { continue }
                isPausedForIdle = true
                await pauseCall()
                return
            }
        }
    }

    private func cancelIdleWatch() {
        idleWatchTask?.cancel()
        idleWatchTask = nil
    }

    // MARK: - The tutor's island

    /// What the call is about right now: a running lesson or sound is the
    /// topic, not the mode's name (2026-11-12, founder: a tutor call on the
    /// interview lesson read "Topic: Tutor").
    private var islandTitle: String {
        if tutorThisCall, let lesson = tutorLesson, lesson.droppedAt == nil {
            return lesson.title
        }
        if pronThisCall, let pronTopic {
            return pronTopic.symbol
        }
        return topicIsNews ? explain("News") : callDisplayTitle
    }

    /// A scene or a person's call keeps the topic and the way it was launched.
    private var islandCanChange: Bool {
        counterpart == nil && sessionScenarioId == nil
    }

    /// Free talk · Tutor · Pronunciation (2026-11-12). Coach mode is not one
    /// of them; "Try saying" stays in Call settings.
    private var islandGuidance: Binding<CallGuidance> {
        Binding(get: { pronThisCall ? .pronunciation : (tutorThisCall ? .tutor : .free) },
                set: { picked in
                    // Out of the pronunciation coach first: tutor mode
                    // refuses to start while it runs.
                    applyPronMode(picked == .pronunciation)
                    tutorModeChoice = picked == .tutor
                    // A call opened from the ring's tutor page is in tutor
                    // mode without the setting, so the setting may not move.
                    applyTutorMode(picked == .tutor)
                })
    }

    private func islandChangeTopic() {
        if pronThisCall { showingPronTopics = true }
        else if tutorThisCall { showingTutorTopics = true }
        else { showingIslandTopics = true }
    }

    /// A new topic picked mid-call in a plain call, from the same ideas the
    /// home's "Find a topic" shows: the prompt follows and the fluent self
    /// opens it.
    private func islandPicked(_ picked: String, blurb: String = "", isNews: Bool = false,
                              facts: [String] = []) {
        topic = picked
        topicBlurb = blurb
        topicIsNews = isNews
        newsFacts = facts
        guard RealtimeMode.isEnabled, phoneCallActive else { return }
        realtime.setSystem(systemPrompt() + realtimeStyleRules)
        realtime.nudge("The learner picked a new topic on their screen: \"\(picked)\". Say sure in a few words and open it with one short question.")
    }

    /// The pronunciation coach switched on or off mid-call from the island.
    /// On: the call is held for the app's verdicts and the first round of
    /// the course is written, as a call opened on the ring's page does. Off:
    /// the round is put away and the call is an ordinary one again.
    private func applyPronMode(_ on: Bool) {
        guard on != pronThisCall else { return }
        if on {
            applyTutorMode(false)
            tutorThisCall = false
        }
        pronThisCall = on
        if !on {
            pronSendTask?.cancel()
            pronSendTask = nil
            pronWindowOpen = false
            pronPlanning = false
            pronTopic = nil
            pronRound = nil
        }
        guard RealtimeMode.isEnabled, phoneCallActive else { return }
        realtime.setCallMode(on ? "pron" : (tutorThisCall ? "tutor" : "free"), openTalk: isFreeMode)
        sendTutorSystem()
        guard on else { return }
        guard let topic = PronunciationCall.startingTopic(language: appState.targetLanguage,
                                                          level: appState.proficiency) else {
            tutorNudge(PronunciationNotes.planFailed)
            return
        }
        startPronRound(topic: topic, note: nil, first: true)
    }

    private func applyTutorMode(_ on: Bool) {
        guard on != tutorThisCall, !pronThisCall else { return }
        tutorThisCall = on
        if on { tutorWasOn = true }
        // Its turns are the app's to send now (`appSendsTurns`), or no longer.
        pronSendTask?.cancel()
        pronSendTask = nil
        pronWindowOpen = on && realtime.state == .listening
        // The classic path reads `tutorThisCall` at its next turn.
        guard RealtimeMode.isEnabled, phoneCallActive else { return }
        realtime.setMeterFromStart(on)
        realtime.setCallMode(on ? "tutor" : "free", openTalk: isFreeMode)
        realtime.setSystem(systemPrompt() + realtimeStyleRules)
        if on, tutorLesson == nil {
            realtime.nudge("Tutor mode was just turned on. Ask them, in one short question, what they want to be able to say today — they can also pick a topic from the button on their screen.")
        }
    }

    /// What the lock screen calls this call. The same words the toolbar shows.
    private var callDisplayTitle: String {
        topic.isEmpty ? emptyTopicTitle : topic
    }

    /// A call with no topic is named after the home ring's page it came
    /// from: the tutor call is "Tutor", not "Let's talk".
    private var emptyTopicTitle: String {
        (pronThisCall ? TalkRingMode.pronunciation
            : tutorThisCall ? TalkRingMode.tutor : TalkRingMode.freeTalk).title
    }

    // MARK: - Surviving the screen going away

    /// The audio session was taken (incoming phone call, Siri, an alarm) or
    /// handed back.
    ///
    /// On `.began` iOS has ALREADY stopped the engine and any playback, so
    /// there is nothing to stop — what matters is that our state stops lying:
    /// a `listening` phase with a dead engine keeps the endpoint monitor
    /// spinning on a transcript that can never change. On `.ended` the system
    /// tells us whether it's our turn again; `shouldResume` is the only case
    /// where reopening the mic is polite.
    private func handleAudioInterruption(_ note: Notification) {
        guard !isTornDown,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if RealtimeMode.isEnabled {
            // A real phone call or Siri took the session. The realtime stack
            // can't survive that; put the call down cleanly — the transcript
            // stays, one tap resumes — instead of letting the classic
            // recovery below wake LiveTranscriber into the realtime engine.
            if type == .began, phoneCallActive {
                Task { await pauseCall() }
            }
            return
        }
        switch type {
        case .began:
            cancelSilenceTimer()
            if phase == .listening { stopListeningDiscardingChunks() }
            if phase == .speaking { player.stop() }
            // `.thinking` is left alone: the reply is in flight over the
            // network, and it will speak (or fail) on its own terms.
            if phase == .listening || phase == .speaking { phase = .idle }
            CallNowPlaying.update(title: callDisplayTitle, isPlaying: false)
        case .ended:
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:))
            guard options?.contains(.shouldResume) == true else { return }
            Task { await resumeCallIfStalled(force: true) }
        @unknown default:
            break
        }
    }

    /// Reopen the mic when the call should be listening and isn't.
    ///
    /// The test is `live.isEngineRunning`, never `isRunning` — an interrupted
    /// run still reads as started. Cheap and idempotent, which is why it can
    /// hang off every foreground: on the normal path the engine is alive (the
    /// call kept running in the background) and this returns immediately.
    private func resumeCallIfStalled(force: Bool = false) async {
        // The realtime path has NO LiveTranscriber to resuscitate — its mic
        // lives in RealtimeTalkClient, which has its own watchdog and route
        // recovery. This guard is what ended a full day of "random" crashes
        // (2026-09-01): on every scenePhase blip this safety net saw
        // `live.isEngineRunning == false` (trivially true — it never ran),
        // "revived" the classic recognizer ON TOP of the realtime engine,
        // and LiveTranscriber's installTap raised into a SIGABRT.
        guard !RealtimeMode.isEnabled else { return }
        guard !isTornDown, phoneCallActive else { return }
        // Only the two waiting-for-the-learner phases can be silently dead.
        // Mid-reply, the call is doing something that doesn't need the mic.
        guard phase == .listening || phase == .idle else { return }
        guard force || !live.isEngineRunning else { return }
        if phase == .listening { stopListeningDiscardingChunks() }
        lastActivityAt = Date()   // coming back from an interruption isn't idling
        await startRecording()
        CallNowPlaying.update(title: callDisplayTitle, isPlaying: true)
    }

    /// Fresh chunk state for this listening run — or none, when the feature is
    /// off or the link is constrained (same guard as `startTranscription`: on
    /// a bad uplink the pieces would stall and every turn would burn the full
    /// assembly deadline for nothing).
    private func startChunkPipeline() {
        discardChunkPipeline()
        let path = NetworkPathStatus.shared
        guard Self.chunkedASREnabled, path.isSatisfied, !path.isConstrained else { return }
        chunkASR = ChunkASRState()
    }

    /// Abandon the run's pieces (dropped segment, paused call). In-flight
    /// tasks are cancelled; each deletes its own file on the way out.
    private func discardChunkPipeline() {
        guard let chunk = chunkASR else { return }
        chunkASR = nil
        for task in chunk.tasks { task.cancel() }
    }

    /// Fire the reply request for a turn the VAD hasn't confirmed yet, keyed
    /// to nothing on disk — `requestReply` adopts it only if the committed
    /// turn still says the same words. A discarded speculation costs the
    /// LEARNER nothing (Gemini calls are free, rate-capped) but it is not
    /// free to us: the tokens were spent. The `turn-spec:` key prefix is what
    /// the edge function counts them by, so keep it.
    private func fireSpeculativeReply(snapshot: String) {
        guard activeVoiceId != nil,
              !snapshot.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let hypothetical = Turn(
            id: UUID(), role: .user, audioURL: nil,
            transcript: snapshot, durationMs: 0, timestamp: Date(),
            suggestion: nil)
        let messages = ConversationEngine.geminiMessages(from: modelTurns() + [hypothetical])
        let key = "turn-spec:\(UUID().uuidString)"
        let task = Task { @MainActor in
            try await fetchTurnPayload(messages: messages, idempotencyKey: key,
                                       onReply: { _, _ in })
        }
        speculativeReply = SpeculativeReply(text: snapshot, firedAt: Date(), task: task)
        turnTrace("spec/fired chars=\(snapshot.count)")
    }

    /// Hand the in-flight speculation to the committed turn — or kill it.
    /// `answered` must be the text the model WOULD be asked about now (the
    /// chunk-assembled line when one landed, else the on-device final);
    /// adopting a speculation that answered different words would have the
    /// fluent self reply to a sentence the learner never said.
    private func takeSpeculative(matching answered: String) -> SpeculativeReply? {
        guard let spec = speculativeReply else { return nil }
        speculativeReply = nil
        guard ConversationEngine.saysTheSameThing(spec.text, answered) else {
            spec.task.cancel()
            // The head start was thrown away at adoption. Logged so the miss
            // rate is measurable: `spec` only says when one was USED, which
            // made every failure mode invisible in telemetry.
            turnTiming["spec_miss"] = "1"
            turnTrace("spec/mismatch — discarded")
            return nil
        }
        return spec
    }

    /// Stop the mic on an exit where the turn's audio is NEVER sent (wall
    /// hit, interruption, pause, hang-up) — the chunk pipeline goes with it,
    /// including the stopped run's un-cut tail file.
    private func stopListeningDiscardingChunks() {
        _ = live.stop()
        speculativeReply?.task.cancel()
        speculativeReply = nil
        discardChunkPipeline()
        if let stale = live.lastChunkRecordingURL {
            try? FileManager.default.removeItem(at: stale)
        }
        micOpenedAt = nil
    }

    /// Encode one cut piece and put its transcription in flight. Fully
    /// background — nothing ever awaits it; `adoptChunkTranscript` harvests
    /// whatever has settled at turn end.
    private func sendChunk(_ url: URL, state: ChunkASRState) {
        let index = state.nextIndex
        state.nextIndex += 1
        let prior = state.textSoFar()
        let target = appState.targetLanguage
        let task = Task { @MainActor in
            defer { try? FileManager.default.removeItem(at: url) }
            let encoded = await Task.detached(priority: .userInitiated) {
                Self.encodeTurnAudio(at: url)
            }.value
            guard let inline = encoded.inline else {
                state.failedCount += 1
                return
            }
            let heard = await UtteranceTranscriber.transcribeChunk(
                audio: inline, priorText: prior, targetLanguage: target,
                idempotencyKey: "asr-chunk:\(state.runId.uuidString):\(index)")
            if let heard {
                state.resolved[index] = heard
            } else {
                state.failedCount += 1
            }
        }
        state.tasks.append(task)
    }

    /// Append one transcribed piece to the turn text, dropping any leading run
    /// of words that merely repeats the tail of what is already there.
    ///
    /// Each piece is transcribed with the turn's text SO FAR as continuity
    /// context, and the model sometimes writes that context back out ahead of
    /// the words it actually heard. Measured 2026-08-19 on a 65-second turn cut
    /// into 11 pieces: the assembled transcript read the same two sentences
    /// three times over, and — because a full assembly REPLACES the on-device
    /// text — that is what reached the bubble, the summary, the drill cards and
    /// the book. The prompt now fences the context, but the join refuses an
    /// echo in code too: a prompt is a request, this is a guarantee.
    ///
    /// Overlaps shorter than `minEchoWords` are left alone — people really do
    /// repeat two or three words across a pause, and cutting those would edit
    /// the learner's own speech.
    /// - Returns: the joined text, and how many words were dropped as echo.
    nonisolated static func stitch(_ text: String, _ piece: String) -> (String, Int) {
        if !WordSplitter.spaced { return stitchUnspaced(text, piece) }
        let minEchoWords = 4
        let maxEchoWords = 80
        let pieceWords = piece.split(separator: " ").map(String.init)
        guard !pieceWords.isEmpty else { return (text, 0) }
        guard !text.isEmpty else { return (piece, 0) }

        // Compare on normalized words (case, punctuation and filler markers
        // differ between two transcriptions of the same speech); keep a map
        // back to raw positions so the drop count applies to the real words.
        let prev = Self.comparableWords(text.split(separator: " ").map(String.init))
        let cur = Self.comparableWords(pieceWords)
        var dropRaw = 0
        let limit = min(prev.count, cur.count, maxEchoWords)
        if limit >= minEchoWords {
            for k in stride(from: limit, through: minEchoWords, by: -1) {
                guard prev.suffix(k).map(\.text) == cur.prefix(k).map(\.text) else { continue }
                // Everything up to and including the last echoed word.
                dropRaw = cur[k - 1].rawIndex + 1
                break
            }
        }
        let kept = pieceWords.dropFirst(dropRaw)
        guard !kept.isEmpty else { return (text, pieceWords.count) }
        return (text + " " + kept.joined(separator: " "), dropRaw)
    }

    /// `stitch` for a language written without spaces: the same echo rule
    /// over SEGMENTS, and the pieces joined as they were written — a space
    /// between two Japanese pieces is a space the learner never said. A
    /// longer bar than words (segments are finer: 行き|まし|た is three), and
    /// the cut lands at the end of the last echoed segment in the raw piece.
    nonisolated private static func stitchUnspaced(_ text: String, _ piece: String) -> (String, Int) {
        let minEchoSegments = 6
        let maxEchoSegments = 120
        let pieceTokens = WordSplitter.segmentRanges(piece)
        guard !pieceTokens.isEmpty else { return (text, 0) }
        guard !text.isEmpty else { return (piece, 0) }
        let prev = WordSplitter.segments(text)
        let cur = pieceTokens.map(\.surface)
        var drop = 0
        let limit = min(prev.count, cur.count, maxEchoSegments)
        if limit >= minEchoSegments {
            for k in stride(from: limit, through: minEchoSegments, by: -1)
            where Array(prev.suffix(k)) == Array(cur.prefix(k)) {
                drop = k
                break
            }
        }
        guard drop > 0 else { return (text + piece, 0) }
        guard drop < pieceTokens.count else { return (text, pieceTokens.count) }
        let rest = piece[pieceTokens[drop - 1].range.upperBound...]
            .drop { $0.isWhitespace || $0.isPunctuation }
        return (text + rest, drop)
    }

    /// Words reduced to their comparable form, dropping tokens that normalize
    /// to nothing (stray punctuation) so they can't align by accident.
    nonisolated private static func comparableWords(
        _ words: [String]
    ) -> [(text: String, rawIndex: Int)] {
        words.enumerated().compactMap { index, word in
            let normalized = word.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined()
            return normalized.isEmpty ? nil : (normalized, index)
        }
    }

    /// Energy-based endpointing loop, started with the mic. Every tick it
    /// checks how long the mic has ACTUALLY been silent (last voiced audio,
    /// not last transcript change) against the text-completeness tier, and
    /// auto-sends when both the audio and the STT partial have settled.
    private func startEndpointMonitor() {
        cancelSilenceTimer()
        silenceTask = Task { @MainActor in
            while !Task.isCancelled, phoneCallActive, phase == .listening {
                try? await Task.sleep(nanoseconds: UInt64(Self.endpointTickSeconds * 1_000_000_000))
                guard !Task.isCancelled, phoneCallActive, phase == .listening else { return }
                // Nothing transcribed yet → the user hasn't said anything
                // (or STT hasn't caught up). Never send an empty turn.
                guard !live.transcript.trimmingCharacters(in: .whitespaces).isEmpty,
                      let lastVoiced = live.lastVoicedAt else { continue }
                let audioSilence = Date().timeIntervalSince(lastVoiced)
                // Evidence accumulates as they speak, so a long gap raises the
                // bar for the gap AFTER it — within this turn and the next few.
                sessionPauseFloor = max(sessionPauseFloor, live.observedPauseSeconds)
                // The LIVE partial's clock, not the transcript's: a late
                // rescored final rewrites the bubble while the learner is
                // already silent, and treating that as "still speaking" made
                // every corrected turn wait an extra settle window before the
                // fluent self answered — the learner paid for their own
                // correction. See `LiveTranscriber.lastLivePartialAt`.
                let sinceTextChange = live.lastLivePartialAt.map { Date().timeIntervalSince($0) }
                    ?? .greatestFiniteMagnitude
                // The user has plausibly finished — spend the rest of the VAD
                // wait warming the network path (TLS + auth token) so the turn
                // request fires onto a hot connection.
                if audioSilence >= Self.preconnectAfterSilenceSeconds, !didPreconnectThisTurn {
                    didPreconnectThisTurn = true
                    GeminiClient.shared.preconnect()
                }
                // Cut the chunk capture at this pause and put its
                // transcription in flight while the learner is still
                // (possibly) mid-turn. 0.5s of true silence is below every
                // VAD tier, so on a turn that is actually ending this same
                // cut IS the speculative tail send — its round trip overlaps
                // the confirmation wait happening right here.
                if let chunk = chunkASR,
                   audioSilence >= Self.chunkRotateSilenceSeconds,
                   voicedSecondsThisTurn() - chunk.voicedMark >= Self.chunkMinVoicedSeconds,
                   let piece = live.rotateCaptureChunk() {
                    chunk.voicedMark = voicedSecondsThisTurn()
                    sendChunk(piece, state: chunk)
                }
                // Speculative reply: the pause has outlived the chunk cut and
                // the partial has settled — odds are this turn is over, and
                // the VAD will spend another 0.5–1 s making sure. Spend that
                // same window on the model's thinking time instead.
                //
                // Only a CHANGED PARTIAL invalidates the snapshot — never mic
                // energy alone. Energy cancelling looked right and churned in
                // practice (measured 2026-08-21, noise=0.18: fired/cancelled
                // 4x in one turn — the room's noise reads as "voice" forever).
                // Correctness never needed it: adoption re-checks the words
                // (`takeSpeculative`), so a speculation outlived by real new
                // speech dies at the transcript change or at the match check.
                if let spec = speculativeReply, live.transcript != spec.text {
                    spec.task.cancel()
                    speculativeReply = nil
                    turnTrace("spec/cancelled — the partial moved on")
                }
                if speculativeReply == nil,
                   specFiresThisTurn < Self.maxSpecFiresPerTurn,
                   audioSilence >= Self.speculateAfterSilenceSeconds,
                   sinceTextChange >= Self.speculateSettleSeconds {
                    specFiresThisTurn += 1
                    fireSpeculativeReply(snapshot: live.transcript)
                }
                // Primary: real audio silence for the tier duration, AND the
                // recognizer's partial has settled (its lag would otherwise
                // truncate the turn's tail).
                let audioSettled = audioSilence >= currentVadWaitSeconds()
                    && sinceTextChange >= Self.sttSettleSeconds
                // Fallback: steady background noise never reads as silent —
                // fire on the old transcript-quiet signal as an upper bound.
                let transcriptSettled = sinceTextChange >= Self.noisyRoomFallbackSeconds
                // Ceiling: in a café BOTH of the above can fail forever. The
                // room never goes quiet, so energy endpointing never fires,
                // and the recognizer keeps making words out of other people's
                // voices, so the "transcript-quiet" fallback keeps restarting
                // — the turn hangs on "Listening" until the learner taps.
                // Reported from a real café, 2026-08-18. But the clock alone
                // also cut real monologues mid-sentence (same day): with no
                // silence at all, 30s arrives while the LEARNER is the one
                // talking. So the ceiling holds off while the close-mic
                // evidence says a person is speaking — a room's babble never
                // clears the voiced threshold, so the café case fires exactly
                // as before — and only the absolute cap cuts a person.
                let listened = speechStartedAt().map { Date().timeIntervalSince($0) } ?? 0
                let ranLong = listened >= Self.maxListenSecondsHard
                    || (listened >= Self.maxListenSeconds && !someoneIsTalkingHere())
                guard audioSettled || transcriptSettled || ranLong else { continue }
                // A ceiling'd turn is the one case where the transcript may be
                // nobody's — a room talking into an open mic for 30s. Sending
                // it would pay for a reply to a stranger's sentence, so the
                // segment is dropped and the mic reopened instead. Everything
                // the learner never said costs nothing and leaves no trace.
                if ranLong, !audioSettled, !transcriptSettled,
                   voicedSecondsThisTurn() < Self.minVoicedSecondsPerTurn {
                    await restartListeningQuietly()
                    return
                }
                // `vad_wait_ms` alone hid the worst case: on the noisy fallback
                // the energy meter never saw silence, so it logs a TINY audio
                // gap for a turn that actually sat out the 6s transcript wait.
                // Record which condition fired, the transcript-quiet duration,
                // and how loud the room was, so "slow outside" is readable.
                turnTiming = [
                    "vad_wait_ms": String(Int(audioSilence * 1000)),
                    // "ceiling" is the one to watch: it means neither
                    // endpointing signal ever fired and the turn was cut by
                    // the clock. A rising share of it is a room problem.
                    "vad_path": audioSettled ? "audio" : (transcriptSettled ? "noisy" : "ceiling"),
                    // Since 2026-09-04: from the FIRST VOICED frame, not the
                    // mic opening — a long think no longer counts as listening.
                    "listened_ms": String(Int(listened * 1000)),
                    "text_quiet_ms": String(Int(min(sinceTextChange, 60) * 1000)),
                    "noise": String(format: "%.2f", live.ambientNoiseLevel),
                    // The longest thinking gap this turn spoke through. Reads
                    // as "how close did we come to cutting them off": whenever
                    // it approaches `vad_wait_ms`, the fixed tiers were about
                    // to end a turn the learner was still in the middle of.
                    "pause_max_ms": String(Int(live.observedPauseSeconds * 1000)),
                    // What the floor actually demanded of this turn. Compare
                    // with `vad_wait_ms` to see whether the learner's own
                    // pausing, or the fixed tier, decided when to answer.
                    "pause_floor_ms": String(Int(sessionPauseFloor * 1000)),
                    // Requested is not granted — some routes refuse the unit.
                    // Without this, a `vad_path=noisy` turn can't be told apart
                    // from one where noise suppression simply never engaged.
                    "voice_proc": live.voiceProcessingActive ? "1" : "0",
                    // How many speculations this turn FIRED (0–3). With `spec`
                    // (used) and `spec_miss` (thrown away at adoption), the
                    // three together say where the ~40% of turns that get no
                    // head start actually lose it: never fired, churned out by
                    // trailing partials, or mismatched at adoption.
                    "spec_fires": String(specFiresThisTurn),
                ]
                turnEndedSpeakingAt = Date()
                // This learner's composing pace, kept for the NEXT call — with
                // one turn's decay already applied, so a single 4 s gap in the
                // last turn of tonight's call doesn't open tomorrow's on a
                // 3.5 s wait for "Yeah."
                UserDefaults.standard.set(
                    min(sessionPauseFloor * Self.pauseFloorDecay, Self.vadLongSeconds),
                    forKey: Self.pauseFloorDefaultsKey)
                HapticEngine.voiceSent()
                await stopAndSend()
                return
            }
        }
    }

    /// Drop what the mic collected and open a fresh segment, without sending
    /// anything. The room's words go with it, along with the fluency meter's
    /// count — so the next 30 s has to earn its own evidence of a person.
    ///
    /// Deliberately silent: nothing was said, so there is nothing to show. The
    /// idle watchdog keeps its own clock across this (`lastActivityAt` is not
    /// touched here), which is what lets a room full of noise eventually pause
    /// the call instead of restarting forever.
    private func restartListeningQuietly() async {
        guard !isTornDown, phoneCallActive, phase == .listening else { return }
        // The room's audio goes with the words: pieces already in flight are
        // abandoned and the stopped run's chunk tail is deleted unheard.
        stopListeningDiscardingChunks()
        await startRecording()
    }

    /// Inspect the latest STT transcript and pick a REQUIRED TRUE-SILENCE
    /// duration (seconds since the mic last heard voiced audio):
    ///   • 5.0s — clearly mid-thought (filler / hanging conjunction / stub).
    ///   • 0.8s — wrapped up cleanly (terminal punctuation .!?).
    ///   • 1.6s — anything in between.
    ///
    /// …then RAISED, never lowered, to the longest thinking pause this turn has
    /// already survived (`observedPauseSeconds`). The tiers above are a guess
    /// about the speaker read off their words; that is a measurement of the
    /// speaker themselves, and where the two disagree the measurement wins.
    /// Learners compose mid-sentence far more slowly than the lexical cues
    /// admit — a clause can end on a clean period and still be half a thought,
    /// and the tuning that took the tiers down to 0.8/1.6s was driven purely by
    /// latency telemetry, which cannot see a learner being cut off (their next
    /// turn just looks like a new sentence).
    private func currentVadWaitSeconds() -> Double {
        let trimmed = live.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lexical: Double
        if Self.isLikelyIncomplete(trimmed) {
            lexical = Self.vadLongSeconds
        } else if let last = trimmed.last, ".!?".contains(last) {
            lexical = Self.vadShortSeconds
        } else {
            lexical = Self.vadDefaultSeconds
        }
        // Only pauses they actually CLOSED by speaking again count, so this
        // can never chase the silence that is currently running. Capped at the
        // long tier: one freak gap must not turn the rest of the call into a
        // conversation with a wall.
        let demonstrated = min(sessionPauseFloor + Self.pauseFloorMargin,
                               Self.vadLongSeconds)
        return max(lexical, demonstrated)
    }

    private static let fillerWords: Set<String> = [
        "uh", "um", "er", "ah", "hmm", "mm", "well",
        "음", "어", "그", "그러니까", "에"
    ]
    private static let trailingConjunctions: Set<String> = [
        "and", "but", "or", "so", "because", "cause",
        "if", "when", "while", "that", "which", "though", "although"
    ]
    private static let trailingFunctionWords: Set<String> = [
        "the", "a", "an", "to", "in", "on", "at", "of",
        "for", "with", "by", "from", "into", "about"
    ]

    private static func isLikelyIncomplete(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        // Dictation punctuates from prosody: a COMMA is the recognizer saying
        // this sentence keeps going, and an ellipsis or a dash that they
        // trailed off. Without this they all fell to the default tier, which
        // is the recognizer telling us the learner is mid-thought and us
        // answering anyway.
        if let last = trimmed.last, ",;:-–—…、，".contains(last) { return true }
        if trimmed.hasSuffix("...") { return true }
        let words = trimmed
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard let last = words.last else { return true }
        // Very short transcripts are almost always still being formed.
        if words.count <= 2,
           !last.hasSuffix("?"),
           !last.hasSuffix("."),
           !last.hasSuffix("!") {
            return true
        }
        let stripped = last.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        if fillerWords.contains(stripped)         { return true }
        if trailingConjunctions.contains(stripped) { return true }
        if trailingFunctionWords.contains(stripped) { return true }
        return false
    }

    private func cancelSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = nil
    }

    private func openConversation() async {
        // Once, at the top of the call: whose mic records you
        // (`MicPreferenceStore`). Here rather than in `startRecording`, which
        // runs every turn — a modal between turns is a modal in the middle of
        // a conversation. No-op after the first answer, and whenever no
        // Bluetooth device is connected.
        await askMicChoiceIfNeeded()
        // Once per install, before the very first call: level, speed, coach
        // mode, Send (`FirstCallSetupSheet`). Before the opener is written,
        // so the level and coach mode it sets shape this call's prompt.
        await askFirstCallSetupIfNeeded()
        sessionPauseFloor = max(sessionPauseFloor, Self.rememberedPauseFloor())
        phase = .thinking
        // The opener plays before any mic session exists — arm the call's
        // audio session or the greeting streams into `.soloAmbient` (muted by
        // the ring switch on most phones). Detached: `setActive` can block
        // for hundreds of ms, and inline it lands exactly on the open-morph
        // frames. It runs while the opener text is fetched; awaited below
        // before anything plays.
        let audioSessionReady = Task.detached(priority: .userInitiated) {
            // Classic path only. The realtime client configures the session
            // itself inside startAudio, and this warm-up racing it mid-build
            // stopped the engine twice and failed the whole call
            // ("Couldn't open the microphone", 2026-09-02) — the two-stacks
            // collision again, this time at session setup.
            if !RealtimeMode.isEnabled { AudioSessionRouting.warmUpForConversation() }
        }
        do {
            let opener: String
            if let initialOpener, !initialOpener.isEmpty {
                // Answered the daily call: the voicemail already said its
                // piece. Anything generated here would talk over a question
                // the learner is mid-way through answering.
                opener = initialOpener
            } else if pronThisCall {
                // A reading drill: the voice waits for the first sentence.
                await audioSessionReady.value
                await beginPronunciationCall()
                return
            } else if tutorThisCall {
                // A lesson, not a chat: the tutor opens on the topic, the
                // lesson left halfway, or the question of what to practice.
                await audioSessionReady.value
                await beginTutorCall()
                return
            } else if topicIsNews, let fromPool = openNewsConversation() {
                opener = fromPool
            } else if learnerPicksTopic {
                // They came to talk about something: the first line hands
                // them the topic instead of a hello.
                opener = FreeTalkOpeners.topicOpener(language: appState.targetLanguage)
            } else if isFirstMeeting {
                // They've never spoken. A friend's hello is a greeting
                // between people who know each other — this call opens by
                // introducing itself (the FIRST CALL block runs the rest of
                // it). Bundled, so the first greeting of all never waits on
                // Gemini.
                opener = FreeTalkOpeners.introOpener(language: appState.targetLanguage)
            } else if topic.isEmpty, counterpart == nil {
                // Free talk: the fluent self says hello itself, from
                // everything its prompt knows, earlier today included
                // (2026-11-12, founder). It replaced bundled hellos and
                // lines written ahead, whose fallback was the same line on
                // every call.
                if promptClock == nil { pinPromptClock() }
                helloBeforeClock = true
                await startRealtimeCall(opener: nil)
                guard !isTornDown else { return }
                realtime.nudge(FreeTalkOpeners.sayHelloNote)
                return
            } else if let line = learnerOpensLine {
                // A starter the LEARNER opens (asking a stranger the way):
                // the other side waits to be spoken to, and the coach's own
                // slot above the pill offers a first line — shown whatever
                // coach mode says, since without it the call is a silence
                // nobody explained. The first reply clears it like any
                // suggestion.
                coachReply = CoachReply(
                    say: line.say,
                    meaning: LanguageCatalog.sameLanguage(appState.targetLanguage,
                                                          appState.nativeLanguage) ? "" : line.meaning,
                    turnId: UUID(), heading: explain("You go first"))
                await startRealtimeCall(opener: nil)
                return
            } else if let sid = sessionScenarioId,
                      let stored = appState.nextScenarioOpener(for: sid) {
                // Scenario talk with a stored opener pool: rotate — instant
                // start, no Gemini call, and the line's TTS is already in the
                // phrase cache after its first play.
                opener = stored
            } else if RealtimeMode.isEnabled {
                // No line in hand: a scenario without a stored pool, or a
                // Find-people call — Gemini WRITES the greeting. Nothing about
                // the call needs it, so the line is opened first and the
                // greeting is said when it lands (`RealtimeTalkClient.say`).
                // Awaiting it here put the model's 2–4 s in front of the audio
                // stack, the socket and the gateway's own start-up instead of
                // alongside them: 6–8 s of silence after the tap, measured
                // 2026-09-13. A greeting that never arrives now costs the call
                // nothing — the learner simply speaks first.
                let askedAt = Date()
                async let written = generateOpener()
                await startRealtimeCall(opener: nil)
                guard !isTornDown else { return }
                // The greeting can be pathologically slow — measured on device
                // 2026-09-13, a scenario opener that had not returned after 37
                // seconds (the request reached the server; the model didn't
                // come back). Nothing can be done about that from here, but a
                // call where nobody speaks and nothing says why is the worst
                // possible shape for it, so the screen asks the learner to
                // start after `openerPatience`.
                let late = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(Self.openerPatience * 1_000_000_000))
                    guard !Task.isCancelled, !isTornDown else { return }
                    openerIsLate = true
                }
                let line = try? await written
                late.cancel()
                openerIsLate = false
                let ms = Int(Date().timeIntervalSince(askedAt) * 1000)
                Self.step("opener: written in \(ms)ms (\(line == nil ? "FAILED" : "ok"))")
                Telemetry.log("talk_opener", [
                    "ms": String(ms),
                    "ok": line == nil ? "0" : "1",
                    "kind": sessionScenarioId != nil ? "scenario" : (counterpart != nil ? "person" : "topic"),
                ])
                if let line, !isTornDown {
                    realtime.say(line, audio: activeVoiceId.flatMap {
                        PhraseAudioStore.shared.url(text: line, voiceId: $0)
                    })
                }
                return
            } else {
                opener = try await generateOpener()
            }
            // The screen may have closed while the opener was being fetched.
            guard !isTornDown else { return }
            if RealtimeMode.isEnabled {
                // The gateway speaks the opener and owns the audio from here:
                // one engine for both directions, which is what makes talking
                // over the fluent self possible. `audioSessionReady` is
                // deliberately NOT awaited — the client configures the session
                // itself, and a second configuration would fight it.
                await startRealtimeCall(opener: opener)
                return
            }
            // Session must be armed before playback OR the mic fallback below.
            await audioSessionReady.value
            // Speak the opener in the active voice — a call starts with the
            // other side TALKING, not a line to read. Repeated openers for
            // the same phrasing hit the content cache, and the idempotency
            // key keeps a re-open from billing the voice twice.
            if let voiceId = activeVoiceId {
                do {
                    try await speakAndAppend(opener, voiceId: voiceId,
                                             idempotencyKey: "tts-opener:\(sessionId.uuidString)")
                    // speakAndAppend owns the phase from here: playback
                    // completion flips back to .idle and re-enters listening
                    // in phone-call mode.
                    return
                } catch {
                    // TTS blip — fall through to the text-only opener rather
                    // than failing the whole session open.
                }
            }
            turns.append(Turn(
                id: UUID(), role: .fluentSelf, audioURL: nil,
                transcript: opener, durationMs: 0, timestamp: Date(),
                suggestion: nil
            ))
            didSaveCurrentSession = false
            phase = .idle
            if phoneCallActive {
                await startRecording()
            }
        } catch {
            phase = .idle
            // A spent day is not a failed opener — same rule as the meter's
            // own wall, so it lands on the same sheet.
            if case VoiceError.fairUseLimit = error { fairUseHalted = true; return }
            if error.isDailyCapReached { dailyCapReached = true; return }
            outOfCredits = error.isOutOfCredits
            self.error = error.localizedDescription
        }
    }

    // MARK: - Realtime path (gateway)

    /// Pick the dropped call back up: same wiring, same voice, the turns so
    /// far as history, and NO opener — the learner speaks next, the fluent
    /// self already knows what was said.
    private func reconnectRealtimeCall() async {
        guard !isTornDown else { return }
        callDropped = nil
        phoneCallActive = true
        phase = .listening
        await startRealtimeCall(opener: nil)
    }

    /// Open the call on the realtime gateway and wire its turns into `turns`.
    ///
    /// This is the whole integration: everything the learning loop needs
    /// already hangs off `turns`, `sessionId` and `endSession`, so the only
    /// job here is to produce the same turns from a different transport —
    /// with their audio, so Practice keeps listen-back, replay and shadowing.
    /// How long the screen waits for a written greeting before telling the
    /// learner to start. Long enough that a normal 2–4 s generation is never
    /// interrupted by it.
    private static let openerPatience: TimeInterval = 7

    /// DEBUG console line, same stream as the realtime client's.
    private static func step(_ message: String) {
        RealtimeTalkClient.step(message)
    }

    private func startRealtimeCall(opener: String?) async {
        guard let voiceId = activeVoiceId else {
            error = explain("Your voice isn't ready yet.")
            return
        }
        realtime.onUserTurn = { text, url, ms, fluency, flags in
            guard !isTornDown else { return }
            giveClockAfterHello()
            // A turn whose correction is skipped (own language, a
            // pronunciation call) still ends the early one.
            if flags.native || pronThisCall { _ = takeEarlyCorrection(matching: "") }
            // The rest of a turn the gateway re-opened after cutting the
            // learner off (2026-10-08): it joins the bubble it belongs to —
            // one turn, one take, one correction — instead of standing as a
            // second turn the summary and the coach would read as two lines.
            if flags.continues, let idx = turns.lastIndex(where: { $0.role == .user }) {
                let joined = turns[idx].transcript
                    + (WordSplitter.spaced ? " " : "") + text
                turns[idx].transcript = joined
                turns[idx].durationMs = ms
                turns[idx].fluency = fluency
                turns[idx].suggestion = nil
                let id = turns[idx].id
                if let url, let data = try? Data(contentsOf: url) {
                    turns[idx].audioURL = TurnAudioStore.shared.save(data, turnId: id)
                    try? FileManager.default.removeItem(at: url)
                }
                didSaveCurrentSession = false
                creditGoalChips(turnId: id)
                let correction = flags.native || pronThisCall ? Task { [TurnFix]?.none }
                    : requestRealtimeSuggestion(for: id, said: joined,
                                                early: takeEarlyCorrection(matching: joined))
                tutorTurn(turnId: id, said: joined, ownLanguage: flags.native, correction: correction)
                pronTurn(turnId: id, said: joined)
                checkDisownedLine(turnId: id, said: joined)
                checkRecalledTalk(turnId: id, said: joined)
                return
            }
            var turn = Turn(id: UUID(), role: .user, audioURL: nil,
                            transcript: text, durationMs: ms, timestamp: Date(),
                            suggestion: nil)
            turn.fluency = fluency
            turn.coachLine = shownCoachLine
            // `TurnAudioStore` owns the file from here; the client wrote it to
            // a temp path precisely so this move is the only copy.
            if let url, let data = try? Data(contentsOf: url) {
                turn.audioURL = TurnAudioStore.shared.save(data, turnId: turn.id)
                try? FileManager.default.removeItem(at: url)
            }
            turns.append(turn)
            let firstWords = !learnerSpokeThisCall
            learnerSpokeThisCall = true
            didSaveCurrentSession = false
            creditGoalChips(turnId: turn.id)
            if firstWords { syncCoachSteer() }
            // A coach hint on a word outside the chip row is judged the same
            // way; its key joins `usedGoalKeys` so the line can tick.
            if let hint = coachHint, !coachStale, !usedGoalKeys.contains(hint.key),
               !TalkGoalPicker.hits(in: turn, among: [hint]).isEmpty {
                withAnimation(.easeInOut(duration: 0.25)) { _ = usedGoalKeys.insert(hint.key) }
                HapticEngine.success()
            }
            // A line said in their own language was answered with the target
            // way to say it; a correction of it would be built on words in
            // the wrong language.
            let correction = flags.native || pronThisCall ? Task { [TurnFix]?.none }
                : requestRealtimeSuggestion(for: turn.id, said: text,
                                            early: takeEarlyCorrection(matching: text))
            tutorTurn(turnId: turn.id, said: text, ownLanguage: flags.native, correction: correction)
            pronTurn(turnId: turn.id, said: text)
            checkDisownedLine(turnId: turn.id, said: text)
            checkRecalledTalk(turnId: turn.id, said: text)
        }
        // The bubble appears WITH the voice and fills as the line is written —
        // the same "you read what you are hearing" the HTTP path gets from
        // split speech. Audio is attached at the end, to the same turn.
        realtime.onReplyBegan = { context in
            guard !isTornDown else { return }
            if let turnAt = tutorWaitTurnAt {
                let ms = { (d: Date) in String(Int(d.timeIntervalSince(turnAt) * 1000)) }
                Telemetry.log("tutor_turn_wait", ["kind": tutorWaitNoteAt == nil ? "none" : tutorWaitKind,
                                                  "note_ms": tutorWaitNoteAt.map(ms) ?? "",
                                                  "reply_ms": ms(Date()),
                                                  "send": sendToAnswer ? "1" : "0",
                                                  "early": earlyCorrectionUsed ? "1" : "0",
                                                  "early_fires": String(earlyCorrectionFired)])
                tutorWaitTurnAt = nil
                tutorWaitNoteAt = nil
            }
            flushHeldSuggestions()
            // The hint belonged to the question just answered.
            if (coachHint != nil || coachReply != nil) && !coachStale {
                withAnimation(.easeInOut(duration: 0.2)) { coachStale = true }
            }
            let turn = Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                            transcript: "", durationMs: 0, timestamp: Date(),
                            suggestion: nil)
            realtimeReplyTurns[context] = turn.id
            turns.append(turn)
            didSaveCurrentSession = false
        }
        realtime.onReplyDelta = { context, delta in
            guard let id = realtimeReplyTurns[context],
                  let idx = turns.firstIndex(where: { $0.id == id }) else { return }
            // A delta prefixed with NUL is the authoritative full text, sent
            // when the reply closes — deltas can be coalesced upstream.
            if delta.hasPrefix("\u{0}") {
                turns[idx].transcript = String(delta.dropFirst())
            } else {
                turns[idx].transcript += delta
            }
            didSaveCurrentSession = false
        }
        realtime.onMeter = { seconds in meter.adoptServerCount(seconds) }
        realtime.onReplyWithdrawn = { context in
            guard let id = realtimeReplyTurns.removeValue(forKey: context) else { return }
            turns.removeAll { $0.id == id }
            didSaveCurrentSession = false
        }
        realtime.onReplyCutIn = { context in
            guard let id = realtimeReplyTurns[context],
                  let idx = turns.firstIndex(where: { $0.id == id }) else { return }
            turns[idx].talkedOver = true
        }
        realtime.onReplyFinished = { context, text, url, ms in
            guard !isTornDown else { return }
            giveClockAfterHello()
            guard let id = realtimeReplyTurns[context],
                  let idx = turns.firstIndex(where: { $0.id == id }) else { return }
            // A line still draining through the player is still being
            // revealed sentence by sentence; the reveal writes its last words,
            // so its context keeps pointing at this bubble until then (the
            // next line's `onReplyBegan` overwrites a stale entry).
            if !realtime.isRevealing(context) {
                realtimeReplyTurns.removeValue(forKey: context)
                turns[idx].transcript = text
            }
            turns[idx].durationMs = ms
            if let url, let data = try? Data(contentsOf: url) {
                turns[idx].audioURL = TurnAudioStore.shared.save(data, turnId: id)
                // Cached by (text, voice) like every other spoken line, so a
                // repeat of the same sentence is free and shadowing finds it.
                PhraseAudioStore.shared.save(data, text: text, voiceId: voiceId, timings: [])
                try? FileManager.default.removeItem(at: url)
            }
            didSaveCurrentSession = false
            lastFinishedReply = (id, text)
            if tutorThisCall { finishedReplies[id] = text }
            advanceCoach(afterReply: text, turnId: id)
        }
        realtime.tutorCall = tutorWasOn || tutorThisCall
        realtime.forceManualTurns = pronThisCall || tutorThisCall
        realtime.callMode = pronThisCall ? "pron" : (tutorThisCall ? "tutor" : "free")
        realtime.openTalk = isFreeMode
        await realtime.connect(
            voiceId: voiceId,
            language: appState.targetLanguage,
            system: systemPrompt() + realtimeStyleRules,
            opener: opener,
            // The launcher warms the next pool greetings' TTS into the phrase
            // cache (`FreeTalkOpeners.warmFirstCall`), so the line is usually
            // already here in the learner's own voice — the client plays it
            // the moment the call is up instead of waiting on the gateway's
            // own round trip for a line the phone already has. A miss is a
            // nil and the gateway speaks it exactly as before.
            // A stranger's opener must be the voice the gateway will answer
            // in — never a take cached before their slot got a native voice.
            openerAudio: opener.flatMap {
                PhraseAudioStore.shared.url(text: $0, voiceId: voiceId,
                                            allowLineage: VoicePreset.speaking(voiceId) == voiceId)
            },
            // A resumed talk carries its history so the fluent self knows what
            // was already said.
            history: turns.map { (role: $0.role == .user ? "user" : "model",
                                  text: $0.transcript) })
        if case .failed(let message) = realtime.state {
            // A spent allowance already raised its own sheet (see the
            // realtime.state observer) — don't stack an error alert on it.
            if realtime.wallCode == nil { error = message }
            phase = .idle
            return
        }
        // The nobody-is-here watchdog. It was armed only in the classic
        // path's `startRecording`, so from the day realtime became the only
        // call path (2026-09-05) a quiet screen never put itself down: the
        // mic stayed hot until the gateway's own 3-minute hang-up ENDED the
        // call, with no "tap to pick it back up". The loop already reads
        // `isBillableMoment`'s realtime branch and `pauseCall`'s, so arming
        // it here is the whole fix. Stamped here too, not only by the callers:
        // a reconnect mid-call must not inherit a clock that is already 25 s
        // into the 30, or the picked-up call pauses before anyone can speak.
        lastActivityAt = Date()
        isPausedForIdle = false
        startIdleWatch()
        syncCoachSteer()
        // A picked-up call is a new gateway session: the final check's hold
        // has to be set on it again.
        if tutorHolds { realtime.setHoldReplies(true) }
        if let note = pendingTutorNudge {
            pendingTutorNudge = nil
            realtime.nudge(note)
        }
    }

    /// A tutor note for a call that may be paused: a paused call has hung up,
    /// so the note waits and goes out when the call is picked back up.
    private func tutorNudge(_ note: String, waitKind: String = "other") {
        if tutorWaitTurnAt != nil, tutorWaitNoteAt == nil {
            tutorWaitNoteAt = Date()
            tutorWaitKind = pronThisCall ? "pron" : waitKind
        }
        if RealtimeMode.isEnabled, !phoneCallActive {
            pendingTutorNudge = note
        } else {
            realtime.nudge(note)
        }
    }

    /// The gateway speaks prose, not the `{reply, suggestion}` JSON the HTTP
    /// turn returns — so the schema instruction is replaced by the two rules
    /// that actually matter out loud.
    private static let callStyleRules = """

        This is a LIVE phone call. Speak in one to three short sentences, \
        never write JSON, never add labels or stage directions — just say \
        your line.
        """

    /// The correction card, on its own clock.
    ///
    /// On the HTTP path the suggestion rides the same call as the reply; here
    /// the reply is prose and the correction is a separate, later request. It
    /// must stay that way: the voice is already playing by the time this
    /// fires, so nothing the learner hears ever waits on coaching.
    private static func correctionErrorKind(_ error: Error) -> String {
        switch error {
        case GeminiError.truncated:                 return "truncated"
        case GeminiError.malformedJSON:             return "malformed_json"
        case GeminiError.jsonNotFound:              return "json_not_found"
        case GeminiError.httpError(let status, _):  return "http_\(status)"
        case is CancellationError:                  return "cancelled"
        case let e as URLError:                     return "url_\(e.code.rawValue)"
        default:                                    return String(describing: error).prefix(60).description
        }
    }

    // MARK: - An earlier talk brought up (`TalkRecall`)

    /// The learner may be talking about an earlier talk. If so its lines go
    /// into the prompt for the replies after this one; nothing waits on it.
    private func checkRecalledTalk(turnId: UUID, said: String) {
        guard isFreeMode, !helloBeforeClock else { return }
        let open = recallIndex.filter { e in !recalledTalks.contains(e) }
        guard TalkRecall.mayRecall(said, entries: open) else { return }
        let lastReply = turns.last(where: { $0.role != .user })?.transcript ?? ""
        Task { @MainActor in
            guard let hit = await TalkRecall.recalled(newest: said, lastReply: lastReply,
                                                      entries: open, turnId: turnId),
                  !isTornDown, isFreeMode, !recalledTalks.contains(hit) else { return }
            recallQueries[hit.id] = said
            recalledTalks = Array((recalledTalks + [hit]).suffix(TalkRecall.heldAtOnce))
            realtime.setSystem(systemPrompt() + realtimeStyleRules)
            Telemetry.log("talk_recalled", [
                "days_ago": String(PromptClock.calendarDays(from: hit.endedAt, to: Date())),
                "held": String(recalledTalks.count),
            ])
        }
    }

    // MARK: - "That wasn't me" (`MisheardJudge`)

    /// The learner may be saying an earlier line was not theirs. Almost no
    /// turn is: the word check decides whether to ask at all.
    private func checkDisownedLine(turnId: UUID, said: String) {
        guard !pronThisCall, MisheardJudge.mayRetract(said) else { return }
        let candidates = disownCandidates(before: turnId)
        guard !candidates.isEmpty else { return }
        Task { @MainActor in
            guard let hit = await MisheardJudge.retractedLine(newest: said, candidates: candidates,
                                                              turnId: turnId),
                  !isTornDown else { return }
            disown(hit)
        }
    }

    /// The lines they could mean, oldest first: the end of the talk this call
    /// opened on (a line caught at the end of one call is disowned at the
    /// start of the next), then this call's own.
    private func disownCandidates(before turnId: UUID) -> [MisheardJudge.Candidate] {
        func pairs(_ all: [Turn], session: UUID, last: Int) -> [MisheardJudge.Candidate] {
            var out: [MisheardJudge.Candidate] = []
            for (i, t) in all.enumerated() where t.role == .user && !t.excludedFromScoring
                && !t.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let reply = i + 1 < all.count && all[i + 1].role == .fluentSelf ? all[i + 1].transcript : ""
                out.append(.init(turnId: t.id, sessionId: session, said: t.transcript, reply: reply))
            }
            return Array(out.suffix(last))
        }
        var earlier: [MisheardJudge.Candidate] = []
        if let key = earlierToday?.key, let id = UUID(uuidString: key),
           let s = SessionStore.shared.load().first(where: { $0.id == id }) {
            earlier = pairs(s.turns, session: id, last: 4)
        }
        let cut = turns.firstIndex(where: { $0.id == turnId }) ?? turns.count
        return earlier + pairs(Array(turns[..<cut]), session: sessionId, last: 6)
    }

    /// What the transcript page's "misheard" swipe does, done now.
    private func disown(_ hit: MisheardJudge.Candidate) {
        if hit.sessionId == sessionId {
            guard let idx = turns.firstIndex(where: { $0.id == hit.turnId }) else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                turns[idx].excludedFromScoring = true
                turns[idx].suggestion = nil
            }
            heldSuggestions[hit.turnId] = nil
            didSaveCurrentSession = false
        } else {
            if let updated = SessionStore.shared.excludeTurnFromScoring(sessionId: hit.sessionId,
                                                                        turnId: hit.turnId) {
                appState.reassessAfterEvidenceChange(in: updated)
            }
            appState.forgetNotes(fromSession: hit.sessionId, heardIn: hit.said)
        }
        Telemetry.log("talk_line_disowned", ["scope": hit.sessionId == sessionId ? "call" : "earlier"])
    }

    /// The per-turn correction. Its task answers the turn's fixes ([] when
    /// too short to correct, nil when the call failed) so a tutor lesson can
    /// judge the same turn alongside it (`tutorTurn`).
    @discardableResult
    private func requestRealtimeSuggestion(for turnId: UUID, said: String,
                                           early: Task<ConversationTurnPayload?, Never>? = nil) -> Task<[TurnFix]?, Never> {
        // Words, not spaces: a Japanese line is one space-free run, and
        // counting on " " gave every Japanese turn a length of one — no
        // correction was ever requested on this path.
        guard WordSplitter.count(said) >= 3 else {
            // Too short to correct; a lesson still judges it (a name alone
            // can be a challenge done).
            return Task { [] }
        }
        // A correction already asked for these words before Send (tutor
        // lesson, Send mode) is the one used; anything else is asked now.
        let request = early ?? correctionPayload(said: said, key: "rt-suggest:\(turnId.uuidString)")
        return Task { @MainActor () -> [TurnFix]? in
            guard let payload = await request.value else { return nil }
            let fixes = payload.turnSuggestion(for: said)?.fixes ?? []
            // `transcript == said`: a turn that has since been joined with its
            // continuation is corrected as the whole line, not as its first half.
            guard !isTornDown,
                  let suggestion = payload.turnSuggestion(for: said),
                  let idx = turns.firstIndex(where: { $0.id == turnId }),
                  turns[idx].transcript == said else { return fixes }
            // A held tutor turn: the card waits for the tutor's voice, so the
            // correction never shows before the answer (founder, 2026-11-06).
            if tutorWaitTurnAt != nil {
                heldSuggestions[turnId] = suggestion
                // A reply that never begins must not lose the card: the
                // summary and the drill cards are built from it.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(8))
                    flushHeldSuggestions()
                }
            } else {
                showSuggestion(suggestion, on: turnId)
            }
            return fixes
        }
    }

    private func flushHeldSuggestions() {
        let held = heldSuggestions
        heldSuggestions = [:]
        for (id, suggestion) in held { showSuggestion(suggestion, on: id) }
    }

    private func showSuggestion(_ suggestion: TurnSuggestion, on turnId: UUID) {
        guard let idx = turns.firstIndex(where: { $0.id == turnId }) else { return }
        turns[idx].suggestion = suggestion
        suggestionsShown += 1
        checkFocusRepeat(suggestion, turnId: turnId)
    }

    /// The correction call itself, for `said` as a reply to the last line
    /// the fluent self said.
    private func correctionPayload(said: String, key: String) -> Task<ConversationTurnPayload?, Never> {
        let target = appState.targetLanguage
        let native = appState.nativeLanguage
        // The line said TO them, so the rewrite can be natural IN THIS
        // conversation rather than natural in a vacuum — the whole turn is
        // being re-said now, and a turn only reads right against what it
        // answers. Context only; the prompt says so and forbids correcting it.
        let heard = turns.last(where: { $0.role == .fluentSelf })?
            .transcript.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = heard.isEmpty
            ? "They said: \"\(said)\""
            : "They were just told: \"\(heard)\"\nThey said: \"\(said)\""
        let system = ConversationEngine.correctionOnlyPrompt(
            targetLanguage: target, nativeLanguage: native,
            level: appState.proficiency, counterpart: counterpart,
            inScene: sessionScenarioId != nil)
        return Task { @MainActor () -> ConversationTurnPayload? in
            do {
                return try await GeminiClient.background.sendJSON(
                    system: system,
                    messages: [GeminiClient.Message(role: .user, content: content)],
                    // Headroom, not a length: thinking spends from the same
                    // ceiling, and a long turn's whole rewrite plus its fixes
                    // was cut off at 900 — a truncation loses the WHOLE
                    // correction, and Say it again then reads the turn raw.
                    maxTokens: 2048,
                    purpose: "turn",
                    idempotencyKey: key,
                    fastThinking: ConversationEngine.correctionThinksFast(targetLanguage: target))
            } catch {
                if Task.isCancelled { return nil }
                // Was invisible until 2026-10-06. One row per failed turn;
                // `words` says whether it is the long turns that fail.
                Telemetry.log("talk_correction_failed", [
                    "error": Self.correctionErrorKind(error),
                    "words": String(WordSplitter.count(said)),
                ])
                return nil
            }
        }
    }

    /// Send mode in a tutor lesson: the learner has stopped and not yet
    /// pressed Send, and the try will wait for its correction (~3 s on
    /// Haiku) once they do. So the correction starts once the words have
    /// held still for `earlyCorrectionSettle` (2026-11-06); at Send it is
    /// used if the turn says the same thing, else asked again. At most
    /// `maxEarlyCorrections` per turn.
    ///
    /// And without Send (2026-11-12, founder: "why can't the tutor answer as
    /// fast as free talk?"): free talk starts its reply the moment the words
    /// stand still, while a tutor try started its check only once the
    /// gateway committed the turn (~1 s later) and then waited ~3 s for it.
    /// The check now starts at the same moment free talk's reply does.
    private func armEarlyCorrection(_ partial: String) {
        earlyCorrectionTimer?.cancel()
        guard tutorThisCall, tutorJudging, !pronThisCall,
              RealtimeMode.isEnabled, phoneCallActive else { return }
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordSplitter.count(text) >= 3, earlyCorrectionFires < Self.maxEarlyCorrections,
              earlyCorrection?.said != text else { return }
        earlyCorrectionTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.earlyCorrectionSettle))
            guard !Task.isCancelled, !isTornDown,
                  realtime.partial.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
            earlyCorrection?.task.cancel()
            earlyCorrectionFires += 1
            earlyCorrection = (text, correctionPayload(said: text, key: "rt-suggest:early-\(UUID().uuidString)"))
        }
    }

    /// Every learner turn ends the early correction: the one asked for
    /// these words if there is one, nil otherwise (cancelled).
    private func takeEarlyCorrection(matching said: String) -> Task<ConversationTurnPayload?, Never>? {
        earlyCorrectionTimer?.cancel()
        let early = earlyCorrection.flatMap { e in
            ConversationEngine.saysTheSameThing(e.said, said) ? e.task : nil
        }
        earlyCorrectionUsed = early != nil
        earlyCorrectionFired = earlyCorrectionFires
        if early == nil { earlyCorrection?.task.cancel() }
        earlyCorrection = nil
        earlyCorrectionFires = 0
        return early
    }

    /// Short and generous: the words that count are the LAST ones, which
    /// land as one more update once the transcriber finalizes, and the cap
    /// was spent on pauses mid-sentence before they did (device, 2026-11-06:
    /// 3 fired, none used). A spare call is a few hundredths of a cent.
    private static let earlyCorrectionSettle = 0.5
    private static let maxEarlyCorrections = 8

    /// News topic: ZERO LLM calls. The platform news pool already generated
    /// this story once for everyone — the title is phrased as a friend
    /// bringing it up (that IS the opener) and the blurb is plain facts from
    /// the grounded pool generation. Day-old facts are fine for a practice
    /// talk; the per-user search-grounded opener this replaces was the single
    /// most expensive call in the app. Returns nil when there's nothing to
    /// speak — caller falls back to the plain opener.
    /// Topic/scenario opener. Scenario-backed talks generate a THREE-line
    /// pool in ONE call (same cost as the old single line) and store it on
    /// the scenario — every later talk rotates the pool for free. Custom
    /// topics (no scenario id) keep the single-line call.
    private func generateOpener() async throws -> String {
        let languageName = LanguageCatalog.englishName(appState.targetLanguage)
        if let sid = sessionScenarioId {
            struct OpenerPool: Decodable { let openers: [String] }
            let payload: OpenerPool? = try? await GeminiClient.shared.sendJSON(
                system: systemPrompt(),
                messages: [GeminiClient.Message(
                    role: .user,
                    content: """
                    Write THREE different natural opening lines in \(languageName) for this conversation.
                    Be IN the scenario — don't summarize it, don't explain it. Each line is the first
                    thing you'd say if this were really happening, in a way the user can respond to.
                    Make the three genuinely different angles, not rephrasings.
                    These lines are SAVED and reused in later talks, on other days and at
                    other hours — nothing tied to the time of day, the date, or an earlier talk.
                    Return STRICT JSON only — no prose: { "openers": ["...", "...", "..."] }
                    """
                )],
                maxTokens: 1200,
                purpose: "opener",
                idempotencyKey: "opener:\(sessionId.uuidString)"
            )
            let pool = (payload?.openers ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let first = pool.first {
                appState.storeScenarioOpeners(pool, for: sid)
                return first
            }
            // Pool call failed → fall through to the single-line opener
            // (same idempotency key: one logical opener, one charge).
        }
        return try await GeminiClient.shared.send(
            system: systemPrompt(),
            messages: [GeminiClient.Message(
                role: .user,
                content: """
                Open this conversation with ONE natural opening line in \(languageName).
                Be IN the scenario — don't summarize it, don't explain it. Just say the first
                thing you'd say if this were really happening, in a way the user can respond to.
                """
            )],
            purpose: "opener",
            idempotencyKey: "opener:\(sessionId.uuidString)"
        )
    }

    private func openNewsConversation() -> String? {
        let opener = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !opener.isEmpty else { return nil }
        // Pool facts (seeded via init) win; a pre-facts pool row falls back
        // to the blurb so the talk is never fact-free.
        if newsFacts.isEmpty {
            let fact = topicBlurb.trimmingCharacters(in: .whitespacesAndNewlines)
            newsFacts = fact.isEmpty ? [] : [fact]
        }
        return opener
    }

    /// Suspends until the learner answers the mic sheet; does nothing once
    /// they have. `onDismiss` resumes, so every dismissal path lands in one
    /// place.
    private func askMicChoiceIfNeeded() async {
        guard MicPreferenceStore.shouldAsk() else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            micChoiceContinuation = cont
            askingMicChoice = true
        }
    }

    private func resumeAfterMicChoice() {
        micChoiceContinuation?.resume()
        micChoiceContinuation = nil
    }

    /// Same shape as the mic sheet: suspends until the sheet goes, and
    /// `onDismiss` resumes whichever way it went.
    private func askFirstCallSetupIfNeeded() async {
        // Marked shown by the sheet's Start, the only way out of it.
        guard FirstCallSetupSheet.shouldShow() else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            firstCallSetupContinuation = cont
            askingFirstCallSetup = true
        }
    }

    private func resumeAfterFirstCallSetup() {
        // Tutor mode decides the opener, read right after this resumes; take
        // the sheet's answer here rather than trust `onChange` to have run.
        tutorThisCall = ((TutorMode.isOn && sessionCounterpartId == nil) || forceTutor) && !pronThisCall
        if tutorThisCall { tutorWasOn = true }
        firstCallSetupContinuation?.resume()
        firstCallSetupContinuation = nil
    }

    private func startRecording() async {
        guard !isTornDown else { return }
        let granted = await LiveTranscriber.requestPermissions()
        guard granted else {
            // iOS won't re-prompt once denied — guide the user to Settings
            // instead of dead-ending on a generic error.
            phoneCallActive = false
            phase = .idle
            showMicPermissionAlert = true
            return
        }
        do {
            // Conversation keeps the Bluetooth (HFP) mic allowed by DEFAULT:
            // the whole point of earphones is phone-in-pocket, where the
            // built-in mic hears nothing. Forcing the built-in mic on everyone
            // was tried 2026-08 and reverted the same day for exactly that
            // reason — so the only thing that overrides it is the learner
            // choosing the phone mic themselves (`MicPreferenceStore`), which
            // is a statement that their phone is in front of them. HFP puts
            // Talk's output on the earphone's CALL volume domain while
            // listening surfaces play on the media domain; that gap is
            // compensated in signal (`a2dpBoostDB`), not by giving up the mic.
            // `measurementMode: false` is explicit because it otherwise
            // defaults to `preferBuiltInMic`, and `.measurement` would make
            // the fluent self's replies noticeably quiet.
            // `voiceProcessing: true` — Talk is the surface people use OUTSIDE
            // (walking, cafés, transit), and it is the only mic surface with no
            // deterministic score riding on raw levels, so it is where iOS's
            // noise suppression belongs. It cleans the audio for BOTH consumers
            // (Apple STT and the Gemini transcription call) and, by keeping the
            // energy meter's noise floor down, lets real endpointing fire
            // instead of the 6s `noisyRoomFallbackSeconds` crawl.
            try live.start(locale: appState.targetLanguage,
                           preferBuiltInMic: MicPreferenceStore.forcesBuiltInMic,
                           measurementMode: false,
                           contextualStrings: recognitionHints(),
                           captureToFile: true,   // keep the user's own audio for listen-back
                           chunkCapture: Self.chunkedASREnabled,
                           voiceProcessing: true)
            startChunkPipeline()
            micOpenedAt = Date()
            // Last turn's pausing still describes this learner, but with less
            // and less authority the longer they go without needing it.
            sessionPauseFloor *= Self.pauseFloorDecay
            didPreconnectThisTurn = false
            specFiresThisTurn = 0
            phase = .listening
            startEndpointMonitor()
            isPausedForIdle = false
            startIdleWatch()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Vocabulary the user is LIKELY to say this turn — biases STT toward
    /// the conversation's domain (topic words, names, news terms). Rebuilt
    /// every turn since the mic restarts per turn.
    ///
    /// Deliberately does NOT include the fluent self's last line: contextual
    /// strings make the recognizer substitute toward the hint list whenever
    /// the audio is unclear, so biasing toward the avatar's words puts words
    /// in the user's mouth they never said.
    private func recognitionHints() -> [String] {
        var hints: [String] = []
        if !topic.isEmpty { hints.append(topic) }
        if let name = appState.persona?.displayName, !name.isEmpty { hints.append(name) }
        hints.append(contentsOf: appState.persona?.interests ?? [])
        for fact in newsFacts { hints.append(contentsOf: Self.significantWords(fact)) }
        var seen = Set<String>()
        return hints.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Content-word extraction for recognition hints: keeps tokens ≥ 4 chars
    /// (drops articles/particles that would only add noise to the bias list).
    private static func significantWords(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
    }

    // NOTE: called from INSIDE the endpoint-monitor task — do not
    // cancelSilenceTimer() here, that would self-cancel and abort the
    // Gemini/TTS awaits below. Setting phase = .thinking is what makes the
    // monitor loop exit on its next tick.
    private func stopAndSend() async {
        // .thinking first so the endpoint monitor exits, then wait the beat
        // for the recognizer's FINAL pass — the committed turn text is the
        // language-model-rescored version, not the last raw partial.
        phase = .thinking
        let finalizeStarted = Date()
        // The turn ships with the text the learner is ALREADY reading on
        // screen. The recognizer's rescored final pass keeps running and edits
        // the bubble in place if it improves — off the critical path, so the
        // transcription costs the turn no time at all.
        let turnId = UUID()
        let finalText = live.stopAndFinalizeInBackground { [self] upgraded in
            applyRecognizerUpgrade(upgraded, to: turnId)
        }
        turnTiming["finalize_ms"] = String(Int(Date().timeIntervalSince(finalizeStarted) * 1000))
        lastRecognizerText[turnId] = finalText
        let fluency = live.fluencyStats()
        let elapsedMs = Int((Date().timeIntervalSince(speechStartedAt() ?? Date())) * 1000)
        micOpenedAt = nil

        // Chunk pipeline: whatever was captured since the last cut is the
        // tail. With voice in it, it becomes the final piece; without, it is
        // the trailing quiet after a cut that already caught the real tail.
        let chunkState = chunkASR
        chunkASR = nil
        if let tail = live.lastChunkRecordingURL {
            if let chunk = chunkState,
               fluency.speakingSeconds - chunk.voicedMark >= Self.chunkTailMinVoicedSeconds {
                sendChunk(tail, state: chunk)
            } else {
                try? FileManager.default.removeItem(at: tail)
            }
        }

        var userTurn = Turn(
            id: turnId, role: .user, audioURL: nil,
            transcript: finalText, durationMs: max(0, elapsedMs), timestamp: Date(),
            suggestion: nil,
            fluency: fluency
        )
        userTurn.coachLine = shownCoachLine
        // Keep the user's own audio so they can listen back to how they
        // actually sounded (temp AAC from the mic tap → TurnAudioStore).
        // `.m4a`, NOT the store's MP3 default: this file gets re-decoded for
        // the Gemini audio attachment, and ExtAudioFile refuses M4A bytes
        // behind an `.mp3` name (see the note on TurnAudioStore).
        if let rec = live.lastRecordingURL, let data = try? Data(contentsOf: rec) {
            userTurn.audioURL = TurnAudioStore.shared.save(data, turnId: userTurn.id,
                                                           fileExtension: "m4a")
            try? FileManager.default.removeItem(at: rec)
        }
        // Transcode NOW, off the main actor, in parallel with the rest of the
        // turn setup — decode + resample + AAC encode + base64 of a whole
        // utterance used to run inline right before the Gemini call, which put
        // it squarely on the critical path AND froze the UI while it ran.
        turnAudioEncode = userTurn.audioURL.map { url in
            (turnId, Task.detached(priority: .userInitiated) {
                Self.encodeTurnAudio(at: url)
            })
        }
        // With a recording in hand an audio-grounded rewrite is still coming.
        // The bubble is NOT held for it — it shows the recognizer's line now
        // and swaps when Gemini's lands. The flag only marks "better text is
        // in flight" so late arrivals resolve in the right order.
        userTurn.transcriptPending = userTurn.audioURL != nil
        turns.append(userTurn)
        learnerSpokeThisCall = true
        didSaveCurrentSession = false
        creditGoalChips(turnId: userTurn.id)

        // Hold every rewrite of this bubble from HERE, not from inside
        // `requestReply`. The chunk wait below and the recognizer's rescored
        // pass both land in this window, and while nothing was armed they
        // painted their corrections before the reply had even been asked for.
        deferredTurnWork = DeferredTurnWork(turnId: turnId)
        if let chunk = chunkState, chunk.nextIndex > 0 {
            adoptChunkTranscript(chunk, turnId: turnId, guess: finalText)
        }
        await requestReply(forUserTurn: userTurn.id)
    }

    /// Zero-wait harvest of the in-flight chunk transcripts: when EVERY piece
    /// already resolved by the time the turn ends, the assembled
    /// audio-grounded text replaces the on-device guess BEFORE the reply is
    /// generated — the whole point of the pipeline. Anything still in flight
    /// falls back to today's behavior on the spot: on-device text now,
    /// whole-turn correction later. (This was a polled 0.1 s deadline that
    /// telemetry showed costing ~130 ms on ~87% of turns for nothing — see
    /// the note where `chunkRotateSilenceSeconds` is defined.)
    private func adoptChunkTranscript(_ chunk: ChunkASRState, turnId: UUID,
                                      guess: String) {
        let waitedMs = 0
        turnTiming["chunks"] = String(chunk.nextIndex)
        turnTiming["chunk_wait_ms"] = String(waitedMs)
        let assembled = chunk.textSoFar()
        // Non-zero means a piece repeated what came before it and `stitch`
        // caught it. Watch it: a rising count says the fenced context is being
        // continued again, and a re-worded echo would slip past the stitcher.
        turnTiming["chunk_echo_words"] = String(chunk.echoWords)
        guard chunk.isSettled, !chunk.hasFailure, !assembled.isEmpty,
              turns.contains(where: { $0.id == turnId }) else {
            turnTiming["chunk_path"] = chunk.hasFailure ? "failed" : "late"
            for task in chunk.tasks { task.cancel() }
            return
        }
        turnTiming["chunk_path"] = "full"
        // Same event the whole-turn path logs, so one query reads both eras:
        // a `chunk_*` outcome means the reply itself was generated from
        // audio-grounded text, and `ms` is what the assembly wait cost.
        Telemetry.log("talk_asr_upgrade", [
            "asr": "chunk_" + Self.asrDelta(heard: assembled, guess: guess),
            "ms": String(waitedMs),
            "guess_len": String(guess.count),
            "audio": "aac",
            "input": Self.currentInputPortType(),
            "worn_mic": AudioSessionRouting.hasWornMicAvailable() ? "1" : "0",
        ])
        chunkResolvedTurns.insert(turnId)
        // The REPLY is generated from this text (see `turnPayload`), but the
        // bubble keeps the on-device line until the voice is out — a swap here
        // is the one the learner reads as "it corrects me, then answers", and
        // it is the most visible of the three because it precedes the Gemini
        // call itself.
        if deferredTurnWork?.turnId == turnId {
            chunkModelText[turnId] = assembled
            deferredTurnWork?.chunkTranscript = assembled
            turnTrace("chunk/held wait=\(waitedMs)ms — model gets it, screen doesn't")
        } else {
            turnTrace("chunk/applied wait=\(waitedMs)ms — NOT held (voice already out?)")
            applyChunkTranscript(assembled, to: turnId)
        }
    }

    /// One console line per ordering-critical moment of a turn, DEBUG only.
    ///
    /// The order these print in IS the bug this instruments: every rewrite of
    /// the learner's bubble must come after `voice/started`, never before. The
    /// values themselves go to Telemetry — this exists because the console is
    /// where the order is READ while testing on a device.
    private func turnTrace(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("🗣️ [turn] \(message())")
        #endif
    }

    /// Put the chunk pipeline's assembled line on screen. Ground truth:
    /// neither the recognizer's late rescore nor any stray whole-turn result
    /// may clobber it.
    private func applyChunkTranscript(_ assembled: String, to turnId: UUID) {
        chunkModelText[turnId] = nil
        guard let idx = turns.firstIndex(where: { $0.id == turnId }) else { return }
        turnTrace("chunk/applied — bubble changed")
        turns[idx].transcript = assembled
        turns[idx].transcriptPending = false
        lastRecognizerText[turnId] = nil
        creditGoalChips(turnId: turnId)
    }

    /// Generate the fluent-self reply for `turnId` (the latest user turn).
    /// Extracted from `stopAndSend` so a failed turn — usually a transient
    /// network error — can be retried from an inline button WITHOUT making
    /// the user speak again. The user turn stays in `turns` either way.
    private func requestReply(forUserTurn turnId: UUID) async {
        failedTurnId = nil
        outOfCredits = false
        phase = .thinking
        guard let voiceId = activeVoiceId else {
            phase = .idle
            // No voice can start for this turn, so nothing else would release
            // the hold `stopAndSend` armed — the bubble would keep the raw
            // guess forever and the transcription would never fire.
            flushDeferredTurnWork()
            resolvePendingTranscript(turnId)
            return
        }
        // The learner's utterance is transcribed by its OWN call — see
        // `startTranscription`. It used to be a field on the turn call with
        // the audio attached, which forced the model to ingest and transcribe
        // before it could write the reply's first token: measured 4.1s to
        // first reply vs 2.1s without the audio. The reply is the only thing
        // the learner is waiting to HEAR, so it goes text-only and the
        // corrected line catches up in the bubble a moment later.
        //
        // That call is now also deferred until the voice is out. Running it
        // HERE made it concurrent in control flow but not in resources: its
        // audio upload shared a connection with the request below, and the
        // reply's first sentence arrived 0.8–2.2s later for it. Held work
        // resumes in `voiceDidStart()`; the failure paths below flush it too,
        // so a turn that never speaks still gets its corrected transcript.
        //
        // `stopAndSend` normally armed this already, before the chunk wait —
        // re-arming would drop the assembled line it parked there. Arming is
        // for the OTHER caller: Retry, which re-enters on a flushed turn.
        if deferredTurnWork?.turnId != turnId {
            deferredTurnWork = DeferredTurnWork(turnId: turnId)
        }
        do {
            let geminiStarted = Date()
            // TTS starts on the reply's FIRST SENTENCE, not the whole reply —
            // `onReply` fires twice: once with the opening sentence the moment
            // it closes, then once with the full text. The suggestion that
            // follows is written while the voice is already loading.
            var speakTask: Task<Void, Error>?
            var openingTask: Task<Void, Never>?
            let speakEarly: @MainActor (String, Bool) -> Void = { reply, isComplete in
                guard !isTornDown else { return }
                let text = Self.stripLeakedSchemaTail(reply)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // A brace-opener is un-unwrappable JSON debris, never speech —
                // stay silent and let the buffered decode / rescue path decide.
                guard !text.isEmpty, !text.hasPrefix("{") else { return }
                if !isComplete {
                    guard openingTask == nil, speakTask == nil else { return }
                    turnTiming["gemini_first_ms"] =
                        String(Int(Date().timeIntervalSince(geminiStarted) * 1000))
                    turnTiming["tts_split"] = "1"
                    openingTask = Task { @MainActor in
                        await beginSplitSpeech(text, voiceId: voiceId, turnId: turnId)
                    }
                    return
                }
                guard speakTask == nil else { return }
                if let openingTask {
                    // The opening sentence is already on its way to the
                    // speaker. Wait for it to be airborne, then continue the
                    // SAME audio stream with the rest — nothing restarts.
                    speakTask = Task { @MainActor in
                        await openingTask.value
                        try await finishSplitSpeech(fullText: text, voiceId: voiceId,
                                                    turnId: turnId)
                    }
                } else {
                    turnTiming["gemini_first_ms"] =
                        String(Int(Date().timeIntervalSince(geminiStarted) * 1000))
                    turnTiming["tts_split"] = "0"
                    speakTask = Task { @MainActor in
                        try await speakAndAppend(text, voiceId: voiceId,
                                                 idempotencyKey: "tts-turn:\(turnId.uuidString)")
                    }
                }
            }
            let payload: ConversationTurnPayload
            let answered = chunkModelText[turnId]
                ?? turns.first(where: { $0.id == turnId })?.transcript ?? ""
            if let spec = takeSpeculative(matching: answered) {
                // The model has been writing since mid-pause. Await what's
                // left of it; on any failure fall back to a fresh request —
                // a speculation must never cost a turn its Retry-able path.
                turnTiming["spec"] = "1"
                turnTiming["spec_lead_ms"] =
                    String(Int(Date().timeIntervalSince(spec.firedAt) * 1000))
                if let early = try? await spec.task.value {
                    payload = early
                } else {
                    payload = try await turnPayload(turnId: turnId, onReply: speakEarly)
                }
            } else {
                payload = try await turnPayload(turnId: turnId, onReply: speakEarly)
            }
            turnTiming["gemini_ms"] = String(Int(Date().timeIntervalSince(geminiStarted) * 1000))
            // The screen may have closed while the reply was in flight.
            guard !isTornDown else { return }
            let replyText = Self.stripLeakedSchemaTail(payload.reply)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let idx = turns.firstIndex(where: { $0.id == turnId }) {
                // Judged against the line the MODEL answered — for a
                // chunk-assembled turn the bubble is still holding the
                // on-device text (see `chunkModelText`).
                let modelAnswered = chunkModelText[turnId] ?? turns[idx].transcript
                if let s = payload.turnSuggestion(for: modelAnswered) {
                    // Data lands now; the CARD waits for the voice. Applying
                    // it here painted the correction a full TTS round trip
                    // before the fluent self spoke.
                    if deferredTurnWork?.turnId == turnId {
                        deferredTurnWork?.suggestion = s
                        turnTrace("suggestion/held for the voice")
                    } else {
                        turns[idx].suggestion = s
                        suggestionsShown += 1
                    }
                } else if payload.suggestion != nil {
                    turnTrace("suggestion/dropped — only re-spells what they said")
                }
            }
            // Already speaking from the stream callback: adopt its result so a
            // TTS failure still reaches the catch below and offers Retry.
            if let speakTask {
                try await speakTask.value
            } else if let openingTask {
                // The reply's closing quote never arrived (stream cut after the
                // opening sentence shipped). The learner is already hearing
                // this turn — finish it from whatever the payload recovered
                // rather than restart the line from the top.
                await openingTask.value
                try await finishSplitSpeech(fullText: replyText, voiceId: voiceId,
                                            turnId: turnId)
            } else {
                // After unwrapping, a reply that is still empty or raw JSON
                // must fail into the Retry chip — never reach TTS or the feed.
                guard !replyText.isEmpty, !replyText.hasPrefix("{") else {
                    throw GeminiError.invalidResponse
                }
                try await speakAndAppend(replyText, voiceId: voiceId,
                                         idempotencyKey: "tts-turn:\(turnId.uuidString)")
            }
            // DO NOT set phase = .idle here. speakAndAppend kicks off audio
            // playback (non-blocking) whose completion flips phase back to
            // .idle AND auto-restarts listening for phone-call mode.
        } catch {
            // Keep the user's turn and offer an inline Retry instead of a
            // dead-end alert, so a network blip doesn't lose what they said.
            // Out-of-credits is NOT retryable — flag it so the row shows the
            // paywall instead of a retry loop that can never succeed.
            Telemetry.log("talk_turn_error", [
                "error": (error as NSError).domain + ":\((error as NSError).code)",
                "status": error.voiceStatus ?? "",
                "out_of_credits": error.isOutOfCredits ? "1" : "0",
            ])
            phase = .idle
            // No voice will start for this turn, so nothing else will release
            // the held work. The learner still deserves the corrected line —
            // and Retry reuses this same user turn.
            flushDeferredTurnWork()
            // Today's allowance, not a blip: no Retry row (retrying can only
            // fail again today) and no error alert — the sheet says what
            // happened and what's left to do.
            if case VoiceError.fairUseLimit = error { fairUseHalted = true; return }
            if error.isDailyCapReached { dailyCapReached = true; return }
            outOfCredits = error.isOutOfCredits
            failedTurnId = turnId
        }
    }

    /// Fire the verbatim-transcription call for a user turn. Fully detached
    /// from the reply: it may land before it, after it, or not at all, and the
    /// bubble is correct at every one of those moments.
    ///
    /// Started only once the fluent self is audible (see `DeferredTurnWork`),
    /// so the audio path is reported on `talk_asr_upgrade` rather than
    /// `talk_turn_timing` — by the time it is known, the turn's timing row has
    /// already shipped and writing into it would leak the value onto the NEXT
    /// turn's row.
    private func startTranscription(forUserTurn turnId: UUID) {
        // Already audio-grounded via the chunk pipeline — the reply itself was
        // generated from that text and its event is logged. Nothing to fix.
        guard !chunkResolvedTurns.contains(turnId) else {
            chunkResolvedTurns.remove(turnId)
            return
        }
        guard let encode = turnAudioEncode, encode.turnId == turnId else {
            logTranscriptionSkip("no_file")
            resolvePendingTranscript(turnId)
            return
        }
        // On a constrained link (Low Data Mode / degraded path) the upload is
        // the thing most likely to stall — and unlike before, skipping it costs
        // the learner nothing but an unpolished line.
        let path = NetworkPathStatus.shared
        guard path.isSatisfied, !path.isConstrained else {
            logTranscriptionSkip("net")
            resolvePendingTranscript(turnId)
            return
        }
        let target = appState.targetLanguage
        transcribeTask?.cancel()
        transcribeTask = Task { @MainActor in
            let encoded = await encode.task.value
            let audioPath = encoded.inline.map {
                $0.mimeType == "audio/aac" ? "aac" : "wav"
            } ?? encoded.skip
            guard let inline = encoded.inline, !Task.isCancelled else {
                logTranscriptionSkip(audioPath)
                resolvePendingTranscript(turnId)
                return
            }
            let started = Date()
            let guess = turns.first(where: { $0.id == turnId })?.transcript ?? ""
            let heard = await UtteranceTranscriber.transcribe(
                audio: inline, asrGuess: guess, targetLanguage: target,
                idempotencyKey: "asr-turn:\(turnId.uuidString)")
            guard !Task.isCancelled, !isTornDown else { return }
            applyGeminiTranscript(heard, to: turnId, guess: guess, audio: audioPath,
                                  elapsedMs: Int(Date().timeIntervalSince(started) * 1000))
        }
    }

    /// A turn whose audio never made it as far as the transcription call.
    /// Same event as a successful one so "how often is a turn left on the raw
    /// on-device guess" is one query, not two.
    private func logTranscriptionSkip(_ audio: String) {
        Telemetry.log("talk_asr_upgrade", ["asr": "skipped", "audio": audio])
    }

    /// The audio-grounded line, once it lands. Wins over anything the
    /// recognizer produced — this is the only place `turns` gets the version
    /// the summary, drills and profile will learn from.
    ///
    /// Logged separately from `talk_turn_timing` because it resolves on its
    /// own clock: by the time it arrives the turn's timing row has usually
    /// already shipped.
    private func applyGeminiTranscript(_ heard: String?, to turnId: UUID,
                                       guess: String, audio: String, elapsedMs: Int) {
        defer { resolvePendingTranscript(turnId) }
        var outcome = "missing"
        if let heard, !heard.isEmpty, let idx = turns.firstIndex(where: { $0.id == turnId }) {
            outcome = Self.asrDelta(heard: heard, guess: turns[idx].transcript)
            turnTrace("gemini-asr/applied \(outcome) — bubble changed")
            turns[idx].transcript = heard
            // Ground truth — a late recognizer pass must not overwrite it.
            lastRecognizerText[turnId] = nil
            creditGoalChips(turnId: turnId)
        }
        Telemetry.log("talk_asr_upgrade", [
            "asr": outcome,
            "ms": String(elapsedMs),
            "guess_len": String(guess.count),
            "audio": audio,
            "input": Self.currentInputPortType(),
            "worn_mic": AudioSessionRouting.hasWornMicAvailable() ? "1" : "0",
        ])
    }

    /// same / minor / fixed. "fixed" used to be EXACT string inequality, which
    /// counted a differently-placed comma as a mishearing — the "82% wrong"
    /// measured 2026-08-14 was inflated by pure formatting noise, and how much
    /// was never knowable because the texts aren't logged. "minor" is that
    /// noise (same words, different casing/punctuation); "fixed" now means the
    /// WORDS differ.
    private static func asrDelta(heard: String, guess: String) -> String {
        if heard == guess { return "same" }
        return asrNormalized(heard) == asrNormalized(guess) ? "minor" : "fixed"
    }

    private static func asrNormalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Which mic the words came through — the missing dimension in every ASR
    /// accuracy question so far: an 8 kHz HFP earphone mic and the built-in
    /// mic have very different error rates, and nothing recorded which one a
    /// turn used.
    private static func currentInputPortType() -> String {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.portType.rawValue ?? "none"
    }

    /// Decode → 16 kHz mono → AAC-ADTS (~32 kbps, 8–13× smaller than WAV, so
    /// the upload survives a weak uplink), with WAV as the encode-failure
    /// fallback. Pure function, runs off the main actor.
    nonisolated private static func encodeTurnAudio(at url: URL) -> EncodedTurnAudio {
        if let aac = AudioLoudness.aacADTS16kMono(fromFileAt: url), !aac.isEmpty {
            guard aac.count <= 600_000 else {          // ~2min at 32kbps
                return EncodedTurnAudio(inline: nil, skip: "too_big")
            }
            return EncodedTurnAudio(
                inline: .init(mimeType: "audio/aac", base64Data: aac.base64EncodedString()),
                skip: "none")
        }
        if let wav = AudioLoudness.wav16kMono(fromFileAt: url), !wav.isEmpty {
            guard wav.count <= 3_000_000 else {        // ~90s at 16kHz
                return EncodedTurnAudio(inline: nil, skip: "too_big")
            }
            return EncodedTurnAudio(
                inline: .init(mimeType: "audio/wav", base64Data: wav.base64EncodedString()),
                skip: "none")
        }
        return EncodedTurnAudio(inline: nil, skip: "decode_fail")
    }

    /// Release the work held since the turn was sent, now that the fluent
    /// self is audible (or has definitively failed to become audible).
    /// Idempotent — every caller may fire, only the first one does anything.
    ///
    /// The recognizer's line is applied BEFORE the transcription starts on
    /// purpose: that call passes the bubble's current text as its ASR hint,
    /// so the better line makes a better hint.
    private func flushDeferredTurnWork() {
        guard let work = deferredTurnWork else { return }
        deferredTurnWork = nil
        turnTrace("flush — bubble may change from here on"
                  + (work.chunkTranscript != nil ? " (chunk)"
                     : work.recognizerUpgrade != nil ? " (recognizer)" : " (nothing held)"))
        if let assembled = work.chunkTranscript {
            // Audio-grounded and already answered — the recognizer's guess at
            // the same words has nothing to add.
            applyChunkTranscript(assembled, to: work.turnId)
        } else if let upgrade = work.recognizerUpgrade {
            applyRecognizerUpgrade(upgrade, to: work.turnId)
        }
        if let s = work.suggestion,
           let idx = turns.firstIndex(where: { $0.id == work.turnId }) {
            turns[idx].suggestion = s
            suggestionsShown += 1
        }
        startTranscription(forUserTurn: work.turnId)
    }

    /// Apply the recognizer's late rescored pass to a turn already on screen.
    ///
    /// Two upgrades race for this bubble: this one (local, fast, better than
    /// the raw partial) and Gemini's audio-grounded transcript (slower, but
    /// ground truth). Gemini always wins — which is exactly what "only touch
    /// the line if it's still the text the recognizer originally produced"
    /// enforces, with no extra state and no order assumptions.
    private func applyRecognizerUpgrade(_ text: String, to turnId: UUID) {
        // Still waiting on the fluent self: hold it. A bubble that rewrites
        // itself during the wait is what makes the correction FEEL like a
        // step the learner has to sit through.
        if deferredTurnWork?.turnId == turnId {
            deferredTurnWork?.recognizerUpgrade = text
            turnTrace("recognizer/held")
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = turns.firstIndex(where: { $0.id == turnId }),
              turns[idx].transcript != trimmed,
              turns[idx].transcript == lastRecognizerText[turnId] else { return }
        turnTrace("recognizer/applied — bubble changed")
        turns[idx].transcript = trimmed
        lastRecognizerText[turnId] = trimmed
        creditGoalChips(turnId: turnId)
    }

    /// Tick every studying chip this turn just produced.
    ///
    /// Runs on EVERY version of a user turn's text — the recognizer's line the
    /// instant they stop talking, its rescored pass, and Gemini's
    /// audio-grounded rewrite. The first one is what makes the tick feel like
    /// an answer to what they just said; the later ones can only add. Ticks are
    /// never removed: the same detector runs over the finished transcript at
    /// session end, so the wrap-up is where the count is settled, and a check
    /// that vanished mid-call would read as the app taking something back.
    /// A talk on a scenario book leads with THAT book's unmastered material
    /// and what its previous runs offered; any other call gets the notebook.
    /// Previous runs are matched by id, and by title for talks saved before
    /// the book page passed one (2026-09-25 — its Talk button launched with
    /// no scenario id, so every talk it started was linked by title alone).
    private func pickGoalItems() -> [TalkGoalItem] {
        guard let sid = sessionScenarioId,
              let scenario = appState.scenarios.first(where: { $0.id == sid }) else {
            return TalkGoalPicker.pick()
        }
        let title = scenario.displayTitle
        let previous = SessionStore.shared.load().filter {
            $0.id != sessionId && $0.endedAt != nil
                && ($0.originScenarioId == sid || $0.topic == title)
        }
        return TalkGoalPicker.pick(forScenario: scenario, previousTalks: previous,
                                   proficiency: appState.proficiency)
    }

    /// What coach mode may still offer this call, in the chip row's order.
    private func coachCandidates() -> [TalkGoalItem] {
        coach.candidates(from: (goalItems + coachExtras).filter { !usedGoalKeys.contains($0.key) })
    }

    /// Put the steer on the gateway — or take it off — to match the ration.
    /// Only sent when it changes; the gateway keeps it until told otherwise.
    private func syncCoachSteer() {
        // Nothing before the learner has spoken: a question built for a word
        // or a structure is an answer to THEM, and the opener is not.
        let open = coachMode && learnerSpokeThisCall && coach.mayHint
        let items = open ? coachCandidates() : []
        let focus = open ? grammarFocus : nil
        let steer = items.isEmpty && focus == nil ? ""
            : ConversationEngine.coachSteer(for: items, focus: focus)
        guard steer != coachSteerSent else { return }
        coachSteerSent = steer
        realtime.setSteer(steer)
    }

    /// The "try saying" on screen for the line being answered right now —
    /// kept on the learner's turn so a line read off it isn't scored
    /// (`Turn.readFromCoach`). Only while it still belongs to the latest
    /// fluent-self line: a late or stale one was not what they were looking at.
    private var shownCoachLine: String? {
        guard coachMode, let reply = coachReply,
              reply.turnId == turns.last(where: { $0.role == .fluentSelf })?.id else { return nil }
        return reply.say
    }

    /// Coach mode's one step per fluent-self line: ask `CoachSuggester` for
    /// something the learner could say back, every line, the opener included.
    /// When a word hint may be drawn (the ration below, and only once the
    /// learner has spoken) the studied items ride along, and an answer that
    /// naturally uses one names it — that is the word hint now. Then re-set
    /// the steer for the next line.
    private func advanceCoach(afterReply text: String, turnId: UUID) {
        guard coachMode, !tutorInFinalCheck else { return }
        var candidates: [TalkGoalItem] = []
        if learnerSpokeThisCall {
            let mayHint = coach.mayHint
            coach.replyFinished()
            if mayHint, CoachPlan.endsInQuestion(text) { candidates = coachCandidates() }
        }
        let before = turns.prefix { $0.id != turnId }.suffix(CoachSuggester.recentLines)
        let recent = before.map { CoachSuggester.Line(isLearner: $0.role == .user, text: $0.transcript) }
        let previousSay = coachReply?.say
        let about = coachAboutLearner
        Task { @MainActor in
            let result = await CoachSuggester.suggest(
                    line: text, recent: recent, aboutLearner: about,
                    otherSpeaker: coachOtherSpeaker,
                    situation: coachSituation,
                    register: coachRegister,
                    previousSay: previousSay,
                    candidates: candidates,
                    target: appState.targetLanguage, native: appState.nativeLanguage,
                    level: appState.proficiency, turnId: turnId)
            guard coachMode, !isTornDown,
                  // Still the line being answered — a late suggestion must
                  // never sit under the NEXT one.
                  turns.last(where: { $0.role == .fluentSelf })?.id == turnId else { return }
            let newHint = result?.item.flatMap { usedGoalKeys.contains($0.key) ? nil : $0 }
            if let newHint { coach.hintShown(newHint) }
            // One transaction: the hidden old line is swapped for the new one
            // in place, so the slot changes height at most once.
            withAnimation(.easeInOut(duration: 0.25)) {
                if let result { coachReply = result.reply }
                else if coachStale { coachReply = nil }
                if let newHint { coachHint = newHint }
                else if coachStale { coachHint = nil }
                coachStale = false
            }
            if newHint != nil { syncCoachSteer() }
        }
        if learnerSpokeThisCall { syncCoachSteer() }
    }

    /// Pick this call's grammar focus and name it. Coach mode only; a free
    /// talk with the fluent self or a cast call alike, since the slip is the
    /// learner's wherever they make it.
    private func loadGrammarFocus() async {
        guard coachMode, grammarFocus == nil else { return }
        let profile = ProfileStore.shared.load(targetLanguage: appState.targetLanguage,
                                               proficiency: appState.proficiency)
        guard let focus = await GrammarFocus.pick(from: profile, sessions: SessionStore.shared.load(),
                                                  target: appState.targetLanguage,
                                                  native: appState.nativeLanguage),
              !isTornDown, coachMode else { return }
        withAnimation(.easeInOut(duration: 0.3)) { grammarFocus = focus }
        syncCoachSteer()
    }

    /// A correction landed: if it is the focus coming back, badge its card
    /// and move the strip's count. Judged off the voice's path.
    private func checkFocusRepeat(_ suggestion: TurnSuggestion, turnId: UUID) {
        guard coachMode, let focus = grammarFocus,
              let fixes = suggestion.fixes, !fixes.isEmpty else { return }
        Task { @MainActor in
            guard await focus.isRepeat(fixes, turnId: turnId),
                  !isTornDown, grammarFocus == focus else { return }
            withAnimation(.easeInOut(duration: 0.25)) { _ = focusRepeatTurns.insert(turnId) }
        }
    }

    private func creditGoalChips(turnId: UUID) {
        guard !goalItems.isEmpty,
              let turn = turns.first(where: { $0.id == turnId }) else { return }
        let pending = goalItems.filter { !usedGoalKeys.contains($0.key) }
        guard !pending.isEmpty else { return }
        let hits = TalkGoalPicker.hits(in: turn, among: pending)
        guard !hits.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) { usedGoalKeys.formUnion(hits) }
        HapticEngine.success()
    }

    /// Stop holding a user turn's bubble for the audio-grounded rewrite —
    /// either it landed and `transcript` is now Gemini's, or it never will and
    /// the recognizer's guess is the best we have. Idempotent.
    private func resolvePendingTranscript(_ turnId: UUID) {
        guard let idx = turns.firstIndex(where: { $0.id == turnId }),
              turns[idx].transcriptPending else { return }
        turns[idx].transcriptPending = false
    }

    /// One structured turn call: transcript + reply + optional inline
    /// correction (repopulates Turn.suggestion: chip UI, SRS ingest,
    /// weekly-report pairs, suggestion_rate metric). Throws on an empty
    /// reply so the caller's audio→text rescue (and the Retry chip) engage
    /// instead of silently dead-ending the turn.
    /// `turns`, with any chunk-assembled line the bubble is still holding back
    /// substituted in. The model answers the audio-grounded text; the screen
    /// catches up when the voice does. Everything downstream of the call —
    /// summary, drills, the book — reads `turns` after the flush, by which
    /// time the two are the same text again.
    private func modelTurns() -> [Turn] {
        guard !chunkModelText.isEmpty else { return turns }
        return turns.map { turn in
            guard let assembled = chunkModelText[turn.id] else { return turn }
            var copy = turn
            copy.transcript = assembled
            return copy
        }
    }

    private func turnPayload(turnId: UUID,
                             onReply: @MainActor @escaping (String, Bool) -> Void)
    async throws -> ConversationTurnPayload {
        try await fetchTurnPayload(
            messages: ConversationEngine.geminiMessages(from: modelTurns()),
            // Keyed to the user turn: the inline Retry button re-runs this
            // same logical request without a second charge.
            idempotencyKey: "turn:\(turnId.uuidString)",
            onReply: onReply)
    }

    /// The turn request itself, parameterized over the message history so the
    /// speculative path can ask about a turn that isn't committed yet.
    private func fetchTurnPayload(messages: [GeminiClient.Message],
                                  idempotencyKey: String,
                                  onReply: @MainActor @escaping (String, Bool) -> Void)
    async throws -> ConversationTurnPayload {
        do {
            let payload: ConversationTurnPayload = try await GeminiClient.shared.sendJSONStream(
                system: systemPrompt()
                    + ConversationEngine.turnOutputInstruction(
                        targetLanguage: appState.targetLanguage,
                        nativeLanguage: appState.nativeLanguage,
                        level: appState.proficiency,
                        counterpart: counterpart,
                        inScene: sessionScenarioId != nil),
                messages: messages,
                // Headroom for reply + suggestion: a MAX_TOKENS truncation
                // shows up here as a DecodingError-failed turn. gen-3 counts
                // THINKING tokens against this ceiling too, so the budget is
                // shared with reasoning the user never sees. At 1024 that
                // combination truncated ~8% of turns into a dead Retry chip
                // (evenly split across wifi/cellular, i.e. not a network
                // fault). The ceiling is not billed, only tokens actually
                // produced, so the headroom is free.
                maxTokens: 2048,
                temperature: 0.7,
                purpose: "turn",
                idempotencyKey: idempotencyKey,
                // Speak as soon as the reply's FIRST SENTENCE closes; the rest
                // of the reply and the suggestion land while the voice loads.
                earlyField: "reply",
                onEarlyField: onReply,
                // Stream cut after the reply shipped: keep the turn the user
                // already heard, minus the correction.
                fallbackFromEarly: { ConversationTurnPayload(reply: $0, suggestion: nil) }
            )
            guard !payload.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GeminiError.invalidResponse
            }
            return payload
        } catch GeminiError.jsonNotFound(let raw) {
            // Model slipped out of JSON mode. Speak the raw text ONLY when it
            // is actual prose — a fragment starting with "{" is a truncated
            // JSON body, and reading that aloud is worse than failing into
            // the rescue/Retry path.
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("{") else {
                throw GeminiError.invalidResponse
            }
            return ConversationTurnPayload(reply: trimmed, suggestion: nil)
        }
    }

    /// Defensive cleanup: a malformed model turn occasionally NESTS the whole
    /// {reply, suggestion, transcript} schema INSIDE the reply string (escaped),
    /// so after JSON-decoding the reply literally trails with
    /// `","suggestion":null,"transcript":"…"}` — or IS the entire inner JSON
    /// body. Neither must ever be spoken: unwrap a whole-body reply to its
    /// inner "reply" field, then cut at the first leaked-schema seam.
    static func stripLeakedSchemaTail(_ reply: String) -> String {
        var text = reply
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let inner = GeminiClient.completedStringField("reply", in: trimmed) {
            text = inner
        }
        let pattern = #""\s*,\s*"(?:suggestion|transcript|reply)"\s*:"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text) else {
            return text
        }
        return String(text[..<r.lowerBound])
    }

    private func retryReply() {
        guard let id = failedTurnId else { return }
        Task { await requestReply(forUserTurn: id) }
    }

    /// The fluent self's voice just reached the speaker — the moment the
    /// learner experiences as "the answer arrived". Called exactly once per
    /// spoken line, from every TTS path (split stream, plain stream, buffered,
    /// cache hit).
    ///
    /// Two things hang off it. Releasing the held turn work comes FIRST and is
    /// deliberately outside the timing guard: openers carry no timing dict but
    /// a turn must never lose its correction to a logging condition.
    private func voiceDidStart(tts: String, ttsFirstMs: Int? = nil) {
        // The critical path is over — the uplink is free and the bubble can
        // change without reading as "correcting before answering".
        turnTrace("voice/started tts=\(tts) ← everything above this is pre-voice")
        flushDeferredTurnWork()
        guard !turnTiming.isEmpty else { return }
        var props = turnTiming
        props["tts"] = tts
        if let ttsFirstMs { props["tts_first_ms"] = String(ttsFirstMs) }
        if let anchor = turnEndedSpeakingAt {
            props["total_ms"] = String(Int(Date().timeIntervalSince(anchor) * 1000))
        }
        turnTiming = [:]
        turnEndedSpeakingAt = nil
        // Where the wait went, one line per turn: total_ms is speech-end →
        // first audible voice, and the *_ms entries are its parts (finalize,
        // chunk_wait, gemini_first, tts_first…). This is the number the
        // "still slow" reports are about — read it before touching any knob.
        turnTrace("timing " + props.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        Telemetry.log("talk_turn_timing", props)
    }

    /// Synthesize and start playing the reply's OPENING SENTENCE, leaving the
    /// PCM stream open for `finishSplitSpeech` to continue. The point is to
    /// spend the model's remaining writing time on the TTS round-trip instead
    /// of after it.
    ///
    /// Leaves `splitSpeech` nil on any failure — the caller then speaks the
    /// whole reply the ordinary way, so the worst case is the old behavior.
    private func beginSplitSpeech(_ prefix: String, voiceId: String, turnId: UUID) async {
        let ttsStarted = Date()
        var streamId: UUID?
        do {
            let result = try await VoiceClient.shared.synthesizeStreaming(
                voiceId: voiceId, text: prefix,
                idempotencyKey: "tts-turn:\(turnId.uuidString):open",
                purpose: "turn"
            ) { chunk, sampleRate in
                if isTornDown { return }
                if streamId == nil {
                    do {
                        // configureSession: false — mid-call streaming must
                        // inherit LiveTranscriber's live session untouched.
                        try player.startPCMStream(sampleRate: sampleRate, voiceKey: voiceId,
                                                  configureSession: false) {
                            Task { @MainActor in
                                guard phase == .speaking else { return }
                                phase = .idle
                                if phoneCallActive { await startRecording() }
                            }
                        }
                    } catch {
                        return   // engine refused → no split, no audio yet
                    }
                    let id = UUID()
                    streamId = id
                    turns.append(Turn(id: id, role: .fluentSelf, audioURL: nil,
                                      transcript: prefix, durationMs: 0,
                                      timestamp: Date(), suggestion: nil))
                    didSaveCurrentSession = false
                    phase = .speaking
                    splitSpeech = SplitSpeech(fluentTurnId: id, sampleRate: sampleRate,
                                              pcm: Data(), prefix: prefix)
                    voiceDidStart(tts: "stream",
                                  ttsFirstMs: Int(Date().timeIntervalSince(ttsStarted) * 1000))
                }
                player.feedPCMStream(chunk)
            }
            guard streamId != nil else { splitSpeech = nil; return }
            if case .pcm(let full, let rate) = result {
                splitSpeech?.pcm = full
                splitSpeech?.sampleRate = rate
            }
        } catch {
            Telemetry.log("talk_tts_split_open_failed", [
                "error": (error as NSError).domain + ":\((error as NSError).code)",
                "status": error.voiceStatus ?? "",
                "mid_stream": streamId != nil ? "1" : "0",
            ])
            if let id = streamId {
                player.stop()
                turns.removeAll { $0.id == id }
                phase = .thinking
            }
            splitSpeech = nil
        }
    }

    /// Continue the open stream with everything after the opening sentence,
    /// then close it. Falls back to speaking the whole reply when the opening
    /// never got airborne.
    private func finishSplitSpeech(fullText: String, voiceId: String,
                                   turnId: UUID) async throws {
        guard let split = splitSpeech else {
            guard !isTornDown else { return }
            try await speakAndAppend(fullText, voiceId: voiceId,
                                     idempotencyKey: "tts-turn:\(turnId.uuidString)")
            return
        }
        splitSpeech = nil
        // `fullText` must literally extend what we already spoke, or the two
        // halves can't be joined. If it doesn't, the honest move is to keep
        // the bubble to what the learner actually HEARD rather than show a
        // line whose second half was never voiced.
        let rest = fullText.hasPrefix(split.prefix)
            ? String(fullText.dropFirst(split.prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        guard !rest.isEmpty, !isTornDown else {
            player.finishPCMStream()
            finalizeSplitTurn(split, spokenText: split.prefix, voiceId: voiceId)
            return
        }
        if let idx = turns.firstIndex(where: { $0.id == split.fluentTurnId }) {
            turns[idx].transcript = fullText
        }
        var pcm = split.pcm
        var spoken = fullText
        do {
            let result = try await VoiceClient.shared.synthesizeStreaming(
                voiceId: voiceId, text: rest,
                idempotencyKey: "tts-turn:\(turnId.uuidString):rest",
                purpose: "turn"
            ) { chunk, _ in
                guard !isTornDown else { return }
                player.feedPCMStream(chunk)
            }
            if case .pcm(let more, _) = result { pcm.append(more) }
        } catch {
            // The remainder never arrived. The opening is already playing and
            // the learner heard a complete sentence — end the turn there
            // rather than restart it, and put the bubble back in sync.
            Telemetry.log("talk_tts_split_rest_failed", [
                "error": (error as NSError).domain + ":\((error as NSError).code)",
            ])
            spoken = split.prefix
            if let idx = turns.firstIndex(where: { $0.id == split.fluentTurnId }) {
                turns[idx].transcript = split.prefix
            }
        }
        player.finishPCMStream()
        finalizeSplitTurn(split, spokenText: spoken, voiceId: voiceId, pcm: pcm)
    }

    /// Cache what was actually spoken and hang it off the turn, so replay,
    /// shadowing and the phrase cache behave exactly as on the single-shot
    /// path. Timings come later from the free local alignment — never a paid
    /// re-synthesis (see `ShadowDrillView.recoverTimings`).
    private func finalizeSplitTurn(_ split: SplitSpeech, spokenText: String,
                                   voiceId: String, pcm: Data? = nil) {
        let audio = pcm ?? split.pcm
        guard !audio.isEmpty else { return }
        let wav = AudioLoudness.wavData(fromPCM16: audio, sampleRate: Int(split.sampleRate))
        let durationMs = Int(Double(audio.count / 2) / split.sampleRate * 1000)
        PhraseAudioStore.shared.save(wav, text: spokenText, voiceId: voiceId, timings: [])
        let savedURL = TurnAudioStore.shared.save(wav, turnId: split.fluentTurnId)
        if let idx = turns.firstIndex(where: { $0.id == split.fluentTurnId }) {
            turns[idx].audioURL = savedURL
            turns[idx].durationMs = durationMs
        }
    }

    /// Speak one fluent-self line and append it as a turn.
    ///
    /// Karaoke timings are deliberately NOT fetched here. `42cafcc` used to
    /// run a background `synthesizeWithTimestamps` on every line to get them,
    /// on the reasoning that the shared idempotency key made it free. It isn't
    /// free and it isn't correct:
    ///   • it is a SECOND render of audio we already have, which is
    ///     the exact thing the no-duplicate-TTS rule forbids;
    ///   • TTS is not deterministic, so that render's word onsets belong to
    ///     audio the learner never hears. Shadow then highlighted words
    ///     against a different take — drifting further the longer the line.
    /// Timings now come from the audio that actually played: the free
    /// on-device alignment in `LocalAlignment`, run by `ShadowDrillView` when
    /// a line is first opened for shadowing, with the duration-proportional
    /// estimate covering it until then.
    private func speakAndAppend(_ text: String, voiceId: String,
                                idempotencyKey: String? = nil) async throws {
        guard !isTornDown else { return }
        // Content-addressed cache hit avoids re-billing synthesis for repeated
        // fluent-self lines (greetings, short acknowledgements, etc.).
        // `allowLineage: false` — a LIVE call must sound like one take, so an
        // older clone's recording is never spliced in mid-conversation. Review
        // surfaces (scenes, drills, shadow) do accept it.
        if let cached = PhraseAudioStore.shared.data(text: text, voiceId: voiceId,
                                                    allowLineage: false) {
            let timings = PhraseAudioStore.shared.timings(text: text, voiceId: voiceId,
                                                          allowLineage: false) ?? []
            try appendTurnAndPlay(cached, timings: timings, transcript: text)
            voiceDidStart(tts: "cache")
            return
        }
        let ttsStarted = Date()

        // Streaming-first: the fluent self starts talking on the FIRST PCM
        // chunk (~0.2s of audio) instead of after the whole file downloads.
        // Any failure BEFORE audio starts falls back silently to the classic
        // buffered call below; a failure mid-playback surfaces as a retry.
        var streamTurnId: UUID?         // set once playback actually started
        var receivedAnyChunk = false
        do {
            let result = try await VoiceClient.shared.synthesizeStreaming(
                voiceId: voiceId, text: text,
                idempotencyKey: idempotencyKey,
                purpose: "turn"
            ) { chunk, sampleRate in
                // Closed mid-stream: swallow the chunks — never (re)start
                // playback on a dead screen.
                if isTornDown { return }
                if !receivedAnyChunk {
                    receivedAnyChunk = true
                    do {
                        // configureSession: false — mid-call streaming must
                        // inherit LiveTranscriber's live session untouched.
                        try player.startPCMStream(sampleRate: sampleRate,
                                                  voiceKey: voiceId,
                                                  configureSession: false) {
                            Task { @MainActor in
                                guard phase == .speaking else { return }
                                phase = .idle
                                // Phone call: avatar just finished talking →
                                // loop back to listening without a tap.
                                if phoneCallActive {
                                    await startRecording()
                                }
                            }
                        }
                        let id = UUID()
                        streamTurnId = id
                        turns.append(Turn(
                            id: id, role: .fluentSelf, audioURL: nil,
                            transcript: text, durationMs: 0, timestamp: Date(),
                            suggestion: nil
                        ))
                        didSaveCurrentSession = false
                        phase = .speaking
                        voiceDidStart(tts: "stream",
                                      ttsFirstMs: Int(Date().timeIntervalSince(ttsStarted) * 1000))
                    } catch {
                        // Engine refused to start — keep collecting the PCM;
                        // we'll play the accumulated audio the buffered way.
                        streamTurnId = nil
                    }
                }
                if streamTurnId != nil { player.feedPCMStream(chunk) }
            }

            switch result {
            case .pcm(let fullPCM, let sampleRate) where streamTurnId != nil && !fullPCM.isEmpty:
                player.finishPCMStream()
                let wav = AudioLoudness.wavData(
                    fromPCM16: fullPCM, sampleRate: Int(sampleRate))
                let durationMs = Int(Double(fullPCM.count / 2)
                    / sampleRate * 1000)
                PhraseAudioStore.shared.save(wav, text: text, voiceId: voiceId, timings: [])
                let savedURL = TurnAudioStore.shared.save(wav, turnId: streamTurnId!)
                if let idx = turns.firstIndex(where: { $0.id == streamTurnId }) {
                    turns[idx].audioURL = savedURL
                    turns[idx].durationMs = durationMs
                }
                // NO timing re-synthesis here. See `speakAndAppend`'s note.
                return
            case .pcm(let fullPCM, let sampleRate) where !fullPCM.isEmpty:
                let wav = AudioLoudness.wavData(
                    fromPCM16: fullPCM, sampleRate: Int(sampleRate))
                PhraseAudioStore.shared.save(wav, text: text, voiceId: voiceId, timings: [])
                try appendTurnAndPlay(wav, timings: [], transcript: text)
                voiceDidStart(tts: "buffered")
                return
            case .mp3(let data) where !data.isEmpty:
                PhraseAudioStore.shared.save(data, text: text, voiceId: voiceId, timings: [])
                try appendTurnAndPlay(data, timings: [], transcript: text)
                voiceDidStart(tts: "buffered")
                return
            default:
                break   // empty payload → buffered fallback below
            }
        } catch {
            Telemetry.log("talk_tts_stream_fallback", [
                "error": (error as NSError).domain + ":\((error as NSError).code)",
                "status": error.voiceStatus ?? "",
                "mid_stream": streamTurnId != nil ? "1" : "0",
            ])
            if let id = streamTurnId {
                // Audio already started, then the stream broke mid-sentence
                // (cellular loves doing this): stop cleanly, drop the
                // half-spoken turn, and fall through to the buffered call —
                // same idempotency key, so the re-synthesis isn't charged
                // again. The line restarts from the top, which beats
                // dead-ending the call on a Retry button. If the buffered
                // call fails too, THAT error surfaces as the retry row.
                // stop() doesn't fire the stream completion, so phase stays
                // ours to manage — back to .thinking while we re-fetch.
                player.stop()
                turns.removeAll { $0.id == id }
                phase = .thinking
            }
            // No audio reached the speaker → silent fallback.
        }

        let (newAudio, newTimings) = try await VoiceClient.shared
            .synthesizeWithTimestamps(voiceId: voiceId, text: text,
                                      idempotencyKey: idempotencyKey,
                                      purpose: "turn")
        PhraseAudioStore.shared.save(newAudio, text: text, voiceId: voiceId, timings: newTimings)
        try appendTurnAndPlay(newAudio, timings: newTimings, transcript: text)
        voiceDidStart(tts: "buffered")
    }

    /// Buffered playback path: append the fluent-self turn and play the full
    /// audio file (MP3 or WAV). Used for cache hits, the non-streaming
    /// fallback, and older edge deployments.
    private func appendTurnAndPlay(_ audio: Data, timings: [WordTiming],
                                   transcript text: String) throws {
        guard !isTornDown else { return }
        let turnId = UUID()
        let savedURL = TurnAudioStore.shared.save(audio, turnId: turnId, timings: timings)
        let durationMs = Self.mp3DurationMs(audio)
        turns.append(Turn(
            id: turnId, role: .fluentSelf, audioURL: savedURL,
            transcript: text, durationMs: durationMs, timestamp: Date(),
            suggestion: nil
        ))
        didSaveCurrentSession = false
        phase = .speaking
        // configureSession: false keeps the existing .playAndRecord session
        // (set up by LiveTranscriber) instead of switching to .playback and
        // back. Each switch costs 200–500ms — meaningful in a phone-call
        // loop. Speaker output still works because of .defaultToSpeaker.
        try player.play(audio, source: "conversation", configureSession: false) {
            Task { @MainActor in
                guard phase == .speaking else { return }
                phase = .idle
                // Phone call: avatar just finished talking → loop back to
                // listening so the user can reply without tapping.
                if phoneCallActive {
                    await startRecording()
                }
            }
        }
    }

    /// The free pool ran out mid-call — the one wall a paying account never
    /// meets. The call puts ITSELF down and wraps up: book first, plans after.
    ///
    /// It used to raise the error alert and wait for End. Prod, 2026-09-17: a
    /// first caller with 42 turns hit this wall at 23:57:51 and never pressed
    /// End — no summary call, no book, and the plans pitch (which hangs off
    /// the summary sheet's Done) never shown; five minutes later they were in
    /// Watch, and they never subscribed. The screen after the wall is a dead
    /// call — the gateway has torn the session down, the mic is closed,
    /// nothing answers — so leaving the learner on it with a message is
    /// asking them to find the one button that produces what the free call
    /// was FOR. A wall with no learner turn behind it (the pre-flight refused
    /// the greeting) keeps the alert: there is nothing to wrap up.
    private func handleTalkPoolSpent() {
        outOfCredits = true
        guard turns.contains(where: { $0.role == .user }), !isEnding else {
            // Nothing was said, so there is nothing to wrap up — and nothing
            // went wrong either, which is what "Something went wrong" claimed
            // until 2026-09-20. A free pool too small to carry a call is
            // closed on the call's very first tick (20260920150000), so this
            // is now the ordinary way a spent account meets the wall: the
            // plans are the honest answer, and the call screen leaves with
            // them. A subscriber's finished day never lands here — that is
            // `dailyCapReached`, its own sheet.
            Telemetry.log("talk_wall_before_speaking", ["turns": String(turns.count)])
            realtime.hangUp()
            phase = .idle
            phoneCallActive = false
            meter.stop()
            CallNowPlaying.end()
            DailyCallScheduler.releaseAfterLiveCall()
            closeAfterPaywall = true
            paywallSource = "talk_wall_before_speaking"
            showingPaywall = true
            return
        }
        freeCallSpent = true
        Telemetry.log("talk_free_call_spent", ["turns": String(turns.count)])
        Task { await endSession() }
    }

    private func endSession() async {
        // A correction still on its way attaches directly from here on.
        tutorWaitTurnAt = nil
        flushHeldSuggestions()
        // Once the summary sheet has closed, the call is wrapped up and the
        // screen is on its way out. The sheet's Done sits where the call's End
        // does (both top trailing), so a quick second tap on Done landed on
        // End and summarized the same talk again — every call of one learner
        // on build 65 (prod, 2026-10-02). When that second run failed it left
        // the draft's `summary: nil` on disk over a summary that had worked.
        guard !turns.isEmpty, !isEnding, !postCallExitStarted, !isTornDown else { return }
        if pronThisCall {
            finishPronunciationCall()
            return
        }
        phoneCallActive = false
        // The call is over — summary generation isn't talk time, and the lock
        // screen must stop showing a call that has hung up.
        meter.stop()
        CallNowPlaying.end()
        DailyCallScheduler.releaseAfterLiveCall()
        cancelSilenceTimer()
        cancelIdleWatch()
        // If a call is still live, stop the mic/playback so the overlay isn't
        // fighting an open recording while the summary generates.
        if phase == .listening {
            stopListeningDiscardingChunks()
        }
        if phase == .speaking { player.stop() }
        // Close the live call before the transcript is frozen for the summary:
        // a turn still arriving mid-wrap-up would land after the draft save.
        realtime.hangUp()
        // One row per coached call — how many hints, how many were answered
        // with the word — which is how "does it feel forced" gets measured.
        if coach.hintsShown > 0 || (grammarFocus != nil && learnerSpokeThisCall) {
            Telemetry.log("talk_coach", [
                "hints": "\(coach.hintsShown)",
                "used": "\(coach.hinted.filter { usedGoalKeys.contains($0) }.count)",
                "focus": grammarFocus == nil ? "none" : "on",
                "focus_repeats": "\(focusRepeatTurns.count)",
            ])
        }
        phase = .thinking
        withAnimation(.easeInOut(duration: 0.2)) { isEnding = true }
        defer { withAnimation(.easeInOut(duration: 0.2)) { isEnding = false } }
        // Hanging up is the one exit where deferring the transcription could
        // COST something: the last turn's voice may never start, and the draft
        // below freezes `turns` for the summary, the drills and the profile.
        // So release the held work and give it a bounded moment to land. Only
        // waits when a call is genuinely in flight, on a screen that is
        // already showing the wrap-up.
        flushDeferredTurnWork()
        if let pending = transcribeTask {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await pending.value }
                group.addTask { try? await Task.sleep(nanoseconds: 2_500_000_000) }
                await group.next()
                group.cancelAll()   // cancels the WAITER, never `pending` itself
            }
        }
        // The turns are final now (the held corrections have landed), so the
        // fluent self's goodbye can be written from them while the book builds.
        startGoodbye()
        // Persist the raw conversation FIRST. The summary call below can fail
        // (network, credits, malformed JSON) and turns live only in memory —
        // without this draft save a failed summary used to lose the whole
        // session. `SessionSummarizer` overwrites this row (same id) once the
        // analysis lands; until then the talk sits in Practice with a
        // "generate the review material" button instead of dead-ending here.
        // The draft save below overwrites a resumed talk's previous analysis
        // (summary: nil is what marks the row "needs analysis") — capture it
        // first so the summarizer can MERGE with it instead of losing it.
        let prior = SessionStore.shared.load().first { $0.id == sessionId }
        let priorSummary = prior?.summary
        let draft = Session(
            id: sessionId,
            userId: userId,
            targetLanguage: appState.targetLanguage,
            mode: .conversation,
            topic: topic.isEmpty ? nil : topic,
            startedAt: sessionStartedAt,
            endedAt: Date(),
            turns: tutorRoled(turns),
            summary: nil,
            origin: sessionOrigin,
            originScenarioId: sessionScenarioId,
            counterpartId: sessionCounterpartId,
            // Only a call the learner spoke in says anything about the focus;
            // an empty one must not count as a clean call and retire it.
            grammarFocus: learnerSpokeThisCall
                ? grammarFocus?.record(repeats: focusRepeatTurns.count) : nil,
            // Tutor mode and coach mode are judged per line (`Turn.tutorRole`,
            // `Turn.readFromCoach`). A resumed call saved as practice before
            // that stays one.
            coached: prior?.coached == true ? true : nil,
            tutorLesson: learnerSpokeThisCall ? (tutorLesson?.record ?? prior?.tutorLesson) : prior?.tutorLesson
        )
        if learnerSpokeThisCall, var lesson = tutorLesson, !lesson.sessionIds.contains(sessionId) {
            lesson.sessionIds.append(sessionId)
            TutorLessonStore.save(lesson)
            tutorLesson = lesson
        }
        SessionStore.shared.save(draft)
        didSaveCurrentSession = true
        var toAnalyze = draft
        toAnalyze.summary = priorSummary
        do {
            summaryProgress = SessionSummarizer.Progress()
            let result = try await SessionSummarizer.summarize(
                session: toAnalyze, appState: appState,
                onProgress: { summaryProgress = $0 })
            // Let the board finish walking its last steps onto the screen. The
            // local half of the wrap-up takes milliseconds, so without this the
            // rows that land at the end fill and vanish in the same frame and
            // the learner never sees what their talk produced.
            try? await Task.sleep(nanoseconds:
                UInt64(SummaryProgressView.revealTail * 1_000_000_000))
            summary = result.summary
            phase = .idle
            didSaveCurrentSession = true
            refreshDashboard()
        } catch {
            // A failed summary costs the session its ENTIRE review yield, so
            // it needs the same visibility the per-turn failure has — a
            // truncation here is silent otherwise (the talk still saved).
            Telemetry.log("talk_summary_error", [
                "error": (error as NSError).domain + ":\((error as NSError).code)",
                // Which field the model got wrong. Without it every decode
                // failure logs as NSCocoaErrorDomain:4864 and the next fix is
                // guesswork.
                "detail": error.decodeDetail ?? "",
                "turns": String(turns.count),
                "out_of_credits": error.isOutOfCredits ? "1" : "0",
            ])
            outOfCredits = error.isOutOfCredits
            // The talk itself is safe on disk — say so, and say where the
            // missing half is waiting. Without this the alert reads like the
            // whole conversation was lost, and the learner's only move is to
            // guess that re-tapping End retries.
            self.error = error.localizedDescription + "\n\n"
                + explain("Your conversation is saved. Open it under Review to generate its review material again.")
            phase = .idle
        }
    }

    /// The fluent self's ~12 s of feedback on the call just ended, spoken in
    /// the learner's voice while the book builds (`CallGoodbye`). Skipped when
    /// nothing in the call can be honestly praised. Fire and forget: nothing
    /// in the wrap-up waits on it, and a failure at any step is silence, which
    /// is what the wrap-up was before.
    private func startGoodbye() {
        guard learnerSpokeThisCall, goodbyeTask == nil,
              let voiceId = appState.speakingVoiceId else { return }
        let used = goalItems.filter { usedGoalKeys.contains($0.key) }.map(\.text)
        let target = appState.targetLanguage
        guard let facts = CallGoodbye.facts(turns: turns, wordsUsed: used, target: target) else {
            Telemetry.log("call_goodbye", ["outcome": "nothing_to_praise"])
            return
        }
        let started = Date()
        let id = sessionId
        let topic = topic
        let voice = CallGoodbyeVoice(player: player, voiceId: voiceId, sessionId: sessionId)
        goodbyeVoice = voice
        goodbyeTask = Task {
            func log(_ outcome: String, _ extra: [String: String] = [:]) {
                Telemetry.log("call_goodbye", extra.merging([
                    "outcome": outcome,
                    "ms": "\(Int(Date().timeIntervalSince(started) * 1000))",
                ]) { a, _ in a })
            }
            // The voice starts on the FIRST sentence while the rest is still
            // being written (founder 2026-11-12: the words, then a wait for
            // the voice). The card goes up with the first sound, never ahead
            // of it, and grows to the whole line when it is written.
            var first: String?
            var firstSpoken: Task<Bool, Never>?
            var known: CallGoodbye.Line?
            var spokenChars = 0
            voice.onStart = {
                guard !isTornDown else { return }
                goodbye = known ?? CallGoodbye.Line(spoken: first ?? "", translation: "")
                goodbyePlaying = true
                Telemetry.log("call_goodbye_voice", [
                    "voice_ms": "\(Int(Date().timeIntervalSince(started) * 1000))",
                    "early": first == nil ? "0" : "1",
                ])
            }
            voice.onFinish = {
                if goodbyePlaying { log("played", ["chars": "\(spokenChars)"]) }
                goodbyePlaying = false
            }
            let line = await CallGoodbye.write(
                facts: facts, topic: topic.isEmpty ? nil : topic, target: target,
                native: appState.nativeLanguage, level: appState.proficiency, sessionId: id,
                onFirstSentence: { sentence in
                    guard first == nil, !isTornDown else { return }
                    first = sentence
                    spokenChars = sentence.count
                    firstSpoken = Task { await voice.speak(sentence) }
                })
            guard !Task.isCancelled, !isTornDown else { return }
            guard let line else {
                // The text broke after the first sentence went to the voice:
                // let that sentence finish on its own.
                if let firstSpoken { _ = await firstSpoken.value; voice.finish() }
                log("no_line"); return
            }
            known = line
            if voice.started { goodbye = line }
            if let first, let firstSpoken {
                let firstPlayed = await firstSpoken.value
                guard !Task.isCancelled, !isTornDown else { return }
                if firstPlayed {
                    let rest = CallGoodbye.remainder(of: line.spoken, after: first)
                    if await voice.speak(rest) { spokenChars += rest.count }
                } else if await voice.speak(line.spoken) {
                    spokenChars = line.spoken.count
                }
            } else if await voice.speak(line.spoken) {
                spokenChars = line.spoken.count
            }
            voice.finish()
            if !voice.started, !isTornDown {
                // The words still go up; only the voice is missing.
                goodbye = line
                log("no_audio")
            }
        }
    }

    private func stopGoodbye() {
        guard goodbyePlaying else { return }
        goodbyePlaying = false
        goodbyeVoice?.stop()
        Telemetry.log("call_goodbye", ["outcome": "stopped"])
    }

    private func refreshDashboard() {
        // Off-main: `PracticeStats.snapshot()` decodes the FULL session
        // archive — on the appear frame it visibly hitches the pill→call
        // morph, and it only gets slower as sessions accumulate. Reads only,
        // so a background hop is safe; results land back on the main actor.
        Task.detached(priority: .utility) {
            let due = DrillStore.shared.dueCount()
            let snap = PracticeStats.snapshot()
            await MainActor.run {
                dueDrillCount = due
                dashboard = snap
            }
        }
    }

    /// Exit the call screen — back to the presenter's morph when hosted in
    /// RootTabView's ZStack, plain dismiss when presented as a cover.
    private func close() {
        tearDown()
        // Every way out passes here, including the ones with NO summary sheet
        // (closed without saving, a summary that failed) — the first call is
        // asked about however it ended. Once shown it is never shown again,
        // so the summary path, which asks before the plans pitch, can't be
        // asked twice. A beat late: this can run while a confirmation dialog
        // is still going away.
        if FirstCallCheckSheet.shouldShow(learnerSpoke: learnerSpokeThisCall) {
            FirstCallCheckSheet.markShown()
            closeAfterFirstCallCheck = true
            firstCallCheckTrigger = .close
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                showingFirstCallCheck = true
            }
            return
        }
        if let onClose { onClose() } else { dismiss() }
        // The report waits ~1.5 s on the account after Done, with only the ✕
        // on screen; a close in that gap took the report away with this
        // screen and nothing raised it again until the next launch (prod
        // 2026-10-21, the whole twenty minutes spent and no report). The
        // root's own gate decides whether it is due.
        if !trialReportAppeared { DailyCallInbox.shared.pendingTrialReport = true }
        // Staged AFTER the screen is gone, never before: the Practice tab
        // lives UNDER this overlay, and a route consumed while the call is
        // still fading would present the review deck on top of it.
        if routeToPracticeOnClose {
            routeToPracticeOnClose = false
            appState.pendingPracticeRoute = .studying
        }
    }

    /// "Go to Review" from the spent-day sheet. The call can't continue
    /// today, so leaving IS the answer — but a talk carrying the learner's
    /// own turns is never dropped on the way out: it wraps up first (summary,
    /// drills, book) and the Practice tab is where that flow's Done lands.
    private func leaveForPractice() {
        routeToPracticeOnClose = true
        if turns.contains(where: { $0.role == .user }) && !didSaveCurrentSession {
            Task { await endSession() }
        } else {
            close()
        }
    }

    /// Hard-stop every live pipeline this screen owns, and mark the screen
    /// dead so in-flight async work can't resurrect audio after the UI is
    /// gone. Idempotent — safe to call from any close path.
    private func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        if phoneCallActive { HapticEngine.phoneCallEnded() }
        phoneCallActive = false
        meter.stop()
        CallNowPlaying.end()
        DailyCallScheduler.releaseAfterLiveCall()
        cancelSilenceTimer()
        cancelIdleWatch()
        // The transcription runs on its own clock and can outlive the screen —
        // it must not keep uploading (or write into `turns`) after the call
        // has been hung up.
        transcribeTask?.cancel()
        transcribeTask = nil
        realtime.hangUp()
        turnAudioEncode?.task.cancel()
        splitSpeech = nil
        _ = live.stop()
        discardChunkPipeline()
        if let stale = live.lastChunkRecordingURL {
            try? FileManager.default.removeItem(at: stale)
        }
        goodbyeTask?.cancel()
        goodbyeVoice?.stop()
        goodbyePlaying = false
        player.stop()
        phase = .idle
    }

    private func startNewSession() {
        failedTurnId = nil
        // Closed by code, not a swipe — the sheet's onDismiss must not exit.
        if summary != nil { summaryClose = .code }
        summary = nil
        postCallExitStarted = false
        sessionId = UUID()
        sessionStartedAt = Date()
        turns = []
        pinPromptClock()
        tutorThisCall = ((TutorMode.isOn && sessionCounterpartId == nil) || forceTutor) && !pronThisCall
        tutorWasOn = tutorThisCall
        tutorCheckTurnIds = []
        learnerSpokeThisCall = false
        didSaveCurrentSession = false
        // The last call's goodbye ends with it; a new call is a new one.
        goodbyeTask?.cancel()
        goodbyeTask = nil
        goodbyeVoice?.stop()
        goodbyeVoice = nil
        goodbye = nil
        if goodbyePlaying { goodbyePlaying = false; player.stop() }
        phase = .idle
        if !topic.isEmpty {
            phoneCallActive = true   // stay in phone-call mode for continuity
            meter.start(sessionId: sessionId)   // fresh session, fresh tick keys
            // endSession took the last call off the lock screen; this is a new
            // one and has to put itself back.
            DailyCallScheduler.holdForLiveCall()
            CallNowPlaying.begin(
                title: callDisplayTitle,
                onResume: { Task { if !phoneCallActive, !isTornDown { await handleMicTap() } } },
                onPause: { Task { if phoneCallActive { await pauseCall() } } }
            )
            Task { await openConversation() }
        }
    }

    /// The summary sheet is GONE (its `onDismiss`, Done or swipe) → leave the
    /// talk seat entirely, back to the Talk home, offering the plans first
    /// when the free pool is spent. Summary is already saved to History.
    /// Only ever called from that `onDismiss`: the plans are a second sheet
    /// on the same presenter, and presenting it while the first is still
    /// animating out is what emptied the paywall (see the sheet).
    private func endAndClose() {
        summary = nil
        phoneCallActive = false
        cancelSilenceTimer()
        // The plans are offered when the free minutes are SPENT, never while
        // any are left (2026-09-21: ten free minutes replaced the trial, and
        // the welcome sheet promises the decision comes after them). "Spent"
        // is the pool ending this call, or less than a call's minimum left
        // after it — the next tap could not open a call either way.
        if let cached = BillingGate.shared.account, cached.isEntitled || cached.unlimited {
            // Entitlement doesn't lapse mid-call; no round trip on every exit.
            logPostCallPitch("skipped_entitled")
            endAndCloseAfterPitch()
            return
        }
        Task {
            // Forced: they just spent minutes, so a cached snapshot from
            // before the call would answer about a different account.
            let account = await BillingGate.shared.snapshot(force: true)
            guard let account, !account.isEntitled, !account.unlimited else {
                // Already paying, or we couldn't ask — never hold the
                // exit on a question we have no answer to.
                logPostCallPitch(account == nil ? "skipped_lookup_failed"
                                                : "skipped_entitled")
                endAndCloseAfterPitch()
                return
            }
            guard freeCallSpent || account.needsSubscription else {
                logPostCallPitch("skipped_minutes_left")
                endAndCloseAfterPitch()
                return
            }
            if TrialReportStore.shouldOffer(account) {
                logPostCallPitch("trial_report")
                trialReport = TrialReportStore.current(targetLanguage: appState.targetLanguage)
                return
            }
            logPostCallPitch("shown")
            closeAfterPaywall = true
            paywallSource = freeCallSpent ? "after_free_call_spent" : "after_free_minutes_low"
            showingPaywall = true
        }
    }

    private func logPostCallPitch(_ decision: String) {
        let props = ["decision": decision, "free_call_spent": freeCallSpent ? "1" : "0"]
        Telemetry.log("post_call_pitch", props)
        Analytics.capture("post_call_pitch", props)
    }

    /// Everything the end of a call does once the plans question is settled.
    private func endAndCloseAfterPitch() {
        // They came back and had another real call — the first moment at which
        // "how is it going" is a question about something. The sheet's
        // onDismiss completes the exit.
        if FeedbackPrompt.shouldShowReturningTalk(callSeconds: callElapsed) {
            FeedbackPrompt.markShown(.returningTalk)
            dismissAfterFeedback = true
            feedbackContext = .returningTalk
        } else if ReviewRequest.shouldAsk(callSeconds: callElapsed) {
            close()
            ReviewRequest.ask()
        } else {
            close()
        }
    }

    /// How long this call ran, in seconds — the same clock the header shows.
    /// Still readable here: only the meter's next `start` (a new session)
    /// clears it, and the summary sheet sits between that and this.
    private var callElapsed: TimeInterval {
        TimeInterval(meter.clock.seconds)
    }

    private static func mp3DurationMs(_ data: Data) -> Int {
        guard let player = try? AVAudioPlayer(data: data) else { return 0 }
        return Int(player.duration * 1000)
    }

    /// The call where the fluent self meets the learner for the first time.
    ///
    /// A plain free talk only: a scenario casts the model as the barista and a
    /// Find-people call as a stranger, and neither of those can spend itself
    /// getting to know the user without breaking what it was launched as. So
    /// this is not "the first talk ever" but "the first talk where the fluent
    /// self is itself" — someone whose first tap was a news story still gets
    /// properly introduced later, which is the point.
    /// `UserPersona.metAt` is stamped when such a talk gets summarized, so an
    /// abandoned call that said nothing is not counted as having met anyone.
    private var isFirstMeeting: Bool {
        appState.persona?.metAt == nil && topic.isEmpty && counterpart == nil && !learnerPicksTopic
            && !tutorThisCall && !pronThisCall
    }

    /// Read the clock for a call that is starting. A resumed talk's saved
    /// lines are from whenever it paused, so the prompt says how long ago —
    /// otherwise a talk from last week is continued as if it never stopped.
    private func pinPromptClock() {
        promptClock = PromptClock.make(
            now: Date(),
            sessions: SessionStore.shared.loadAcrossLanguages(),
            excluding: sessionId,
            resumedFrom: isResuming ? turns.last?.timestamp : nil
        )
        freeTalkCue = .random(hasRecentNews: appState.persona?.currentNotes()
            .contains { $0.kind == .now } ?? false)
        earlierToday = isResuming ? nil
            : EarlierToday.current(language: appState.targetLanguage, excluding: sessionId)
        recallIndex = TalkRecall.index(
            sessions: SessionStore.shared.loadAcrossLanguages(), now: Date(),
            excluding: Set([sessionId] + [earlierToday?.key].compactMap { $0.flatMap(UUID.init(uuidString:)) }))
        recalledTalks = []
        recallQueries = [:]
        personHistory = sessionCounterpartId.flatMap {
            PersonHistory.build(personId: $0, sessions: SessionStore.shared.load(),
                                excluding: sessionId, pickUp: pickUpLastTalk)
        }
    }

    // MARK: - Pronunciation call (`PronunciationCall`)

    /// How a pronunciation call opens: the voice says hi while the first
    /// round is written, then asks for the first sentence. Every learner
    /// turn is held (`tutorJudging` is true for the whole call) and answered
    /// with the app's note.
    private func beginPronunciationCall() async {
        await startRealtimeCall(opener: nil)
        realtime.setHoldReplies(true)
        guard let topic = PronunciationCall.startingTopic(language: appState.targetLanguage,
                                                          level: appState.proficiency) else {
            tutorNudge(PronunciationNotes.planFailed)
            return
        }
        // Silent while the round is written (the card says "Preparing…"):
        // a hello and then the sound's intro was two openers in a row
        // (founder, 2026-11-04: "Hi there!" isn't needed).
        startPronRound(topic: topic, note: nil, first: true)
    }

    /// Write a round for `topic` and put it on screen. `note`: what the voice
    /// says while it is written.
    private func startPronRound(topic: PronunciationCourse.Topic, note: String?, first: Bool = false) {
        guard pronThisCall, !pronPlanning else { return }
        let avoid = pronRound?.topic.id == topic.id ? (pronRound?.lines.map(\.text) ?? []) : []
        withAnimation(.easeInOut(duration: 0.25)) {
            pronPlanning = true
            pronTopic = topic
            pronRound = nil
        }
        pronUnheard = 0
        UserDefaults.standard.set(topic.id, forKey: PronunciationCall.lastTopicKey(appState.targetLanguage))
        UserDefaults.standard.set(false, forKey: PronunciationCall.lastFinishedKey(appState.targetLanguage))
        sendTutorSystem()
        if let note { tutorNudge(note) }
        Task { @MainActor in
            let round = await PronunciationPlanner.plan(
                topic: topic, targetLanguage: appState.targetLanguage,
                nativeLanguage: appState.nativeLanguage, level: appState.proficiency,
                persona: appState.persona, avoid: avoid,
                review: PronunciationProgressStore.all(language: appState.targetLanguage)[topic.id]?.missedWords ?? [])
            guard !isTornDown, pronTopic?.id == topic.id else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                pronPlanning = false
                pronRound = round
            }
            sendTutorSystem()
            guard let round else {
                Telemetry.log("pron_plan_failed", ["topic": topic.id])
                tutorNudge(PronunciationNotes.planFailed)
                return
            }
            Telemetry.log("pron_round_started", ["topic": topic.id, "lines": String(round.lines.count),
                                                 "first": first ? "1" : "0"])
            tutorNudge(PronunciationNotes.ready(round, first: first))
        }
    }

    /// One learner turn of a pronunciation call. The take is read by Azure
    /// against the sentence on screen and the verdict is code
    /// (`PronunciationJudge`); the voice then says exactly one line for it.
    private func pronTurn(turnId: UUID, said: String) {
        guard pronThisCall else { return }
        // `tutor_turn_wait` (kind pron): turn in hand → note → the voice.
        tutorWaitTurnAt = Date()
        tutorWaitNoteAt = nil
        if pronPlanning {
            tutorNudge("They spoke while the sentences are still being prepared. Say \"one moment\" in a few words.")
            return
        }
        guard let round = pronRound else {
            tutorNudge(PronunciationNotes.planFailed)
            return
        }
        if round.isFinished {
            pronAfterRound(turnId: turnId, said: said, round: round)
            return
        }
        guard let i = round.current else { return }
        let line = round.lines[i]
        let drill = line.drillWord
        pronReadTexts[turnId] = drill ?? line.text
        let audioURL = turns.first(where: { $0.id == turnId })?.audioURL
        let turnMs = turns.first(where: { $0.id == turnId })?.durationMs ?? -1
        let target = appState.targetLanguage
        let early = pronEarly
        pronEarly = nil
        let reuse = early?.matches(roundId: round.id, index: i, reference: drill ?? line.text,
                                   turnMs: turnMs) == true
        if !reuse { early?.task.cancel() }
        Task { @MainActor in
            var result: PronunciationResult?
            var outcome = PronunciationAssessor.Outcome.skipped
            let assessStart = Date()
            if reuse, let early {
                (result, outcome) = await early.task.value
            } else if let audioURL {
                (result, outcome) = await PronunciationAssessor.assess(
                    audioURL: audioURL, reference: drill ?? line.text, language: target, surface: "pron_call",
                    alternates: PronunciationContrast.alternates(for: drill ?? line.text, topicId: round.topic.id))
            }
            // From the turn in hand: with an early read, only what was left.
            pronAssessMs = Int(Date().timeIntervalSince(assessStart) * 1000)
            pronEarlyUsed = reuse
            guard !isTornDown, tutorStillSaid(turnId, said), var now = pronRound,
                  now.id == round.id, now.current == i else { return }
            if let result {
                PronunciationLedger.shared.record([result], id: turnId, surface: "pron_call")
            }
            if let drill {
                pronWordTake(drill, result: result, outcome: outcome, said: said,
                             noAudio: audioURL == nil, round: &now, index: i)
                return
            }
            // No reader at all (no key, the day's cap, no audio on file), or
            // two takes in a row with nothing usable: judge the words alone,
            // so the call can never loop on "read it again".
            let noReader = result == nil
                && (outcome == .unconfigured || outcome == .capped || outcome == .skipped
                    || audioURL == nil || pronUnheard >= 2)
            let verdict = noReader
                ? PronunciationJudge.fallback(line: line, said: said, language: target)
                : PronunciationJudge.verdict(result: result, line: line, said: said,
                                             phonemes: now.topic.phonemes, language: target,
                                             only: line.watch)
            // What missed this time, out of what missed before: the next
            // reading is judged on these alone.
            if !noReader, result != nil {
                switch verdict {
                case .notYet:
                    now.lines[i].watch = Set(PronunciationJudge.missedWords(
                        result: result, line: line, said: said, phonemes: now.topic.phonemes,
                        language: target, only: line.watch).map(PronunciationJudge.key))
                case .notSmooth:
                    now.lines[i].watch = []
                default:
                    break
                }
            }
            var verdictWord = ""
            if case .notYet(let w, _, _, _) = verdict { verdictWord = w }
            Telemetry.log("pron_take", [
                "topic": now.topic.id,
                "verdict": Self.pronVerdictName(verdict),
                "word": verdictWord,
                "watch": now.lines[i].watch.map { String($0.count) } ?? "",
                "score": result.map { String($0.soundScore) } ?? "",
                "fluency": result.map { String($0.fluency) } ?? "",
                "prosody": result?.prosody.map(String.init) ?? "",
                "outcome": outcome.rawValue,
                // Judged by comparison: how many other spellings came back,
                // and by how much one beat the sentence (empty = none did).
                "alts": result?.alternates.map { String($0.count) } ?? "",
                "gap": result.flatMap { PronunciationContrast.misses(in: $0).first.map { String($0.gap) } } ?? "",
                "try": String(line.tries + 1),
                "assess_ms": String(pronAssessMs),
                "early": pronEarlyUsed ? "1" : "0",
            ])
            if let result { now.lines[i].lastResult = result }
            // The note about the sentence left before this one has been read.
            now.carried = nil
            let fb = PronunciationJudge.feedback(for: verdict, result: result, line: line,
                                                 phonemes: now.topic.phonemes)
            if let fb { now.lines[i].feedback = fb }
            if case .notSmooth = verdict { now.lines[i].notSmooth = true } else { now.lines[i].notSmooth = false }
            if case .notYet(let w, _, _, let heard) = verdict, let heard {
                now.lines[i].heardWord = w
                now.lines[i].heardAs = heard
            } else {
                now.lines[i].heardWord = nil
                now.lines[i].heardAs = nil
            }
            switch verdict {
            case .offScript:
                pronUnheard = 0
                withAnimation(.easeInOut(duration: 0.25)) { pronRound = now }
                tutorNudge(PronunciationNotes.offScript(said: said))
            case .unheard:
                pronUnheard += 1
                tutorNudge(PronunciationNotes.unheard)
            case .pass(let score):
                pronUnheard = 0
                pronClearMissed(in: line.text, topicId: now.topic.id)
                now.lines[i].passed = true
                if score > 0 { now.lines[i].bestScore = max(now.lines[i].bestScore ?? 0, score) }
                withAnimation(.easeInOut(duration: 0.3)) { pronRound = now }
                HapticEngine.success()
                sendTutorSystem()
                if now.isFinished { finishPronRound(now) }
                tutorNudge(PronunciationNotes.passed(score: score,
                                                     next: now.current.map { now.lines[$0] },
                                                     round: now,
                                                     afterMisses: line.tries > 0))
            case .notSmooth(let score):
                pronUnheard = 0
                now.lines[i].tries += 1
                now.lines[i].bestScore = max(now.lines[i].bestScore ?? 0, score)
                if now.lines[i].tries >= PronunciationCall.maxMisses {
                    pronMoveOnAfterMisses(&now, index: i, word: nil, sound: nil)
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) { pronRound = now }
                tutorNudge(PronunciationNotes.notSmooth(sentence: line.text,
                                                        pauseBefore: PronunciationJudge.pauseBefore(in: result),
                                                        tries: now.lines[i].tries))
            case .notYet(let word, let sound, let score, let heard):
                pronUnheard = 0
                now.lines[i].tries += 1
                now.lines[i].bestScore = max(now.lines[i].bestScore ?? 0, score)
                if now.lines[i].tries >= PronunciationCall.maxMisses {
                    pronMoveOnAfterMisses(&now, index: i, word: word, sound: sound)
                    return
                }
                // The word on its own first, then the sentence again. A word
                // already right on its own is practiced joined to its
                // neighbours instead: the joining is what slipped.
                now.lines[i].drillTries = 0
                if now.lines[i].soloPassed.contains(PronunciationJudge.key(word)) {
                    let chunk = PronunciationJudge.flowText(for: word, in: line.text)
                    now.lines[i].drillWord = chunk
                    withAnimation(.easeInOut(duration: 0.25)) { pronRound = now }
                    sendTutorSystem()
                    tutorNudge(PronunciationNotes.inFlow(chunk: chunk, word: word, sound: sound,
                                                         heardAs: fb?.heardAs, score: fb?.spokenScore,
                                                         topic: now.topic))
                    return
                }
                now.lines[i].drillWord = PronunciationJudge.drillText(for: word, in: line.text, language: target)
                withAnimation(.easeInOut(duration: 0.25)) { pronRound = now }
                sendTutorSystem()
                tutorNudge(PronunciationNotes.notYet(word: now.lines[i].drillWord ?? word, sound: sound, heard: heard,
                                                     topic: now.topic, sentence: line.text,
                                                     heardAs: fb?.heardAs, score: fb?.spokenScore))
            }
        }
    }

    /// The tutor lesson takes the same turn-taking (founder, 2026-11-13:
    /// "the same logic" — Send and reset there, and a turn that still sends
    /// by itself once they go quiet).
    private var appSendsTurns: Bool { pronThisCall || tutorThisCall }

    /// The pronunciation call's turn-taking (founder, 2026-11-04): the
    /// gateway holds everything (send-to-answer), and the APP sends. What
    /// was heard while the fluent self was speaking — reading along, a
    /// murmur — is thrown away when it stops; from then on is the learner's
    /// turn, sent by itself once they go quiet.
    private func pronStateChanged(from old: RealtimeTalkClient.State, to new: RealtimeTalkClient.State) {
        guard appSendsTurns else { return }
        if new == .speaking {
            pronWindowOpen = false
            pronSendTask?.cancel()
        } else if old == .speaking {
            // Reading along early in the line is thrown away; words begun in
            // its last second are the learner answering, and stay (a one-word
            // answer comes that fast — founder, 2026-11-04: "I said it and it
            // vanished").
            if hasHeldWords, let since = pronHeardSince, Date().timeIntervalSince(since) > 1.0 {
                realtime.discardTurn(filterStale: false)
                pronHeardSince = nil
            }
            pronWindowOpen = true
            // Words kept from the end of the line: send them by the usual rule.
            if hasHeldWords { pronHeard(realtime.partial) }
        }
    }

    /// A send the gateway had nothing for: it is still their turn.
    private func pronSendSettled(_ pending: Bool) {
        if appSendsTurns, !pending, realtime.state == .listening { pronWindowOpen = true }
    }

    /// Words arriving in the learner's window: send once they stop. Quicker
    /// when the sentence on screen is (nearly) all there — a reader pausing
    /// mid-sentence for a hard word must not be cut off.
    private func pronHeard(_ partial: String) {
        guard appSendsTurns else { return }
        if partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pronHeardSince = nil
        } else if pronHeardSince == nil {
            pronHeardSince = Date()
        }
        guard pronWindowOpen, !realtime.sendPending else { return }
        pronSendTask?.cancel()
        guard !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // The line on screen: the sentence or word being read, or in a
        // tutor lesson the current challenge's example.
        let sentence = pronThisCall
            ? (pronRound?.current.map { pronRound!.lines[$0].drillWord ?? pronRound!.lines[$0].text } ?? "")
            : (tutorLesson?.current.map { tutorLesson!.challenges[$0].example } ?? "")
        let whole = !sentence.isEmpty && PronunciationJudge.overlap(said: partial, line: sentence) >= 0.8
        // A word practiced alone has no middle to pause in, and a word that
        // came out wrong never matches the screen: waiting 2.5 s for it made
        // every missed try the slowest one (2026-11-10).
        let drilling = pronThisCall && (pronRound?.current.map { pronRound!.lines[$0].drillWord != nil } ?? false)
        pronSendTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(whole ? 1.0 : (drilling ? 1.2 : 2.5)))
            // Still voicing (the transcript lags the mouth): give it a beat.
            var extra = 0
            while !Task.isCancelled, realtime.level > 0.25, extra < 10 {
                try? await Task.sleep(for: .milliseconds(300))
                extra += 1
            }
            guard !Task.isCancelled, pronWindowOpen, realtime.partial == partial,
                  !realtime.sendPending, realtime.state != .speaking else { return }
            pronWindowOpen = false
            pronStartEarlyRead()
            realtime.sendTurn()
        }
    }

    /// Starts Azure on the take being sent, so it runs while the gateway
    /// waits for the final transcript (`pronEarly`).
    private func pronStartEarlyRead() {
        pronEarly?.task.cancel()
        pronEarly = nil
        guard pronThisCall, !pronPlanning, let round = pronRound, !round.isFinished,
              let i = round.current, let take = realtime.currentTurnWAV() else { return }
        let line = round.lines[i]
        let reference = line.drillWord ?? line.text
        let target = appState.targetLanguage
        let alternates = PronunciationContrast.alternates(for: reference, topicId: round.topic.id)
        let url = take.url
        let task = Task { () -> (result: PronunciationResult?, outcome: PronunciationAssessor.Outcome) in
            defer { try? FileManager.default.removeItem(at: url) }
            return await PronunciationAssessor.assess(audioURL: url, reference: reference,
                                                      language: target, surface: "pron_call",
                                                      alternates: alternates)
        }
        pronEarly = PronEarlyRead(roundId: round.id, index: i, reference: reference,
                                  ms: take.ms, task: task)
    }

    /// The learner's own "Next sentence": the only way a sentence is left
    /// unpassed. Its word and when it comes back are said, and shown.
    private func pronSkipSentence() {
        guard pronThisCall, !pronPlanning, var now = pronRound, let i = now.current else { return }
        if hasHeldWords { realtime.discardTurn(filterStale: false) }
        let fb = now.lines[i].feedback
        let word = fb?.ok == false ? fb?.word : nil
        let sound = fb?.ok == false ? fb?.sound : nil
        let later = pronGiveUp(&now, index: i, word: word, sound: sound)
        Telemetry.log("pron_skip", ["topic": now.topic.id, "tries": String(now.lines[i].tries),
                                    "retry": later ? "0" : "1"])
        withAnimation(.easeInOut(duration: 0.3)) { pronRound = now }
        sendTutorSystem()
        if now.isFinished { finishPronRound(now) }
        tutorNudge(PronunciationNotes.moveOn(word: word, sound: sound, topic: now.topic,
                                             next: now.current.map { now.lines[$0] },
                                             round: now, laterInRound: later))
    }

    /// The learner's own "Back to the sentence" while a word is drilled.
    private func pronLeaveWord() {
        guard pronThisCall, var now = pronRound, let i = now.current,
              let word = now.lines[i].drillWord else { return }
        if hasHeldWords { realtime.discardTurn(filterStale: false) }
        now.lines[i].drillWord = nil
        now.lines[i].drillTries = 0
        withAnimation(.easeInOut(duration: 0.25)) { pronRound = now }
        sendTutorSystem()
        tutorNudge(PronunciationNotes.wordBack(word: word, sound: now.lines[i].feedback?.sound,
                                               topic: now.topic))
    }

    /// A sentence missed `maxMisses` times moves on by itself. It does not
    /// come back at the end of the round (that is a third reading); its word
    /// waits for the next round on this sound.
    private func pronMoveOnAfterMisses(_ now: inout PronunciationRound, index i: Int,
                                       word: String?, sound: String?) {
        if hasHeldWords { realtime.discardTurn(filterStale: false) }
        now.lines[i].isRetry = true
        _ = pronGiveUp(&now, index: i, word: word, sound: sound)
        Telemetry.log("pron_auto_next", ["topic": now.topic.id, "tries": String(now.lines[i].tries),
                                         "word": word ?? ""])
        withAnimation(.easeInOut(duration: 0.3)) { pronRound = now }
        sendTutorSystem()
        if now.isFinished { finishPronRound(now) }
        tutorNudge(PronunciationNotes.moveOn(word: word, sound: sound, topic: now.topic,
                                             next: now.current.map { now.lines[$0] },
                                             round: now, laterInRound: false))
    }

    /// A sentence the learner skipped. The first time it goes to the END
    /// of the round, once (true); its second time it is left, and its word
    /// is kept for the next round on this sound (false).
    private func pronGiveUp(_ round: inout PronunciationRound, index i: Int,
                            word: String?, sound: String?) -> Bool {
        round.lines[i].skipped = true
        round.lines[i].drillWord = nil
        round.carried = .init(word: word?.trimmingCharacters(in: .punctuationCharacters), sound: sound,
                              laterInRound: !round.lines[i].isRetry)
        if !round.lines[i].isRetry {
            var again = PronunciationRound.Line(id: UUID(), text: round.lines[i].text,
                                                focus: round.lines[i].focus)
            again.isRetry = true
            round.lines.append(again)
            return true
        }
        if let word = word?.trimmingCharacters(in: .punctuationCharacters), !word.isEmpty {
            PronunciationProgressStore.update(language: appState.targetLanguage, topicId: round.topic.id) {
                var list = ($0.missedWords ?? []).filter {
                    PronunciationJudge.key($0) != PronunciationJudge.key(word)
                }
                list.append(word)
                $0.missedWords = Array(list.suffix(8))
            }
        }
        return false
    }

    /// Words kept from earlier rounds leave the list once said right.
    private func pronClearMissed(in text: String, topicId: String) {
        let lang = appState.targetLanguage
        guard let missed = PronunciationProgressStore.all(language: lang)[topicId]?.missedWords,
              !missed.isEmpty else { return }
        let said = Set(text.split(whereSeparator: \.isWhitespace).map { PronunciationJudge.key(String($0)) })
        let left = missed.filter { !said.contains(PronunciationJudge.key($0)) }
        guard left.count != missed.count else { return }
        PronunciationProgressStore.update(language: lang, topicId: topicId) { $0.missedWords = left }
    }

    /// A take of one word said on its own (`Line.drillWord`). Right → back
    /// to the sentence; not yet → the word again, until it is right or the
    /// learner taps "Back to the sentence".
    private func pronWordTake(_ word: String, result: PronunciationResult?,
                              outcome: PronunciationAssessor.Outcome, said: String,
                              noAudio: Bool, round now: inout PronunciationRound, index i: Int) {
        let probe = PronunciationRound.Line(id: UUID(), text: word,
                                            focus: word.split(whereSeparator: \.isWhitespace).map(String.init))
        let noReader = result == nil
            && (outcome == .unconfigured || outcome == .capped || outcome == .skipped
                || noAudio || pronUnheard >= 2)
        var verdict = noReader
            ? PronunciationJudge.fallback(line: probe, said: said, language: appState.targetLanguage)
            : PronunciationJudge.verdict(result: result, line: probe, said: said,
                                         phonemes: now.topic.phonemes, language: appState.targetLanguage,
                                         wordDrill: true)
        // One word has no rhythm to judge: its sounds are the take.
        if case .notSmooth(let score) = verdict { verdict = .pass(score: score) }
        // A word read on its own that Azure couldn't match is that word not
        // coming out yet — never "they said something else", which the voice
        // answered with "just the word" to someone who had just said it
        // (2026-11-06: 9 of 66 word takes).
        if case .offScript = verdict, let result {
            verdict = .notYet(word: word, sound: nil, score: result.soundScore, heard: nil)
        }
        Telemetry.log("pron_word_take", [
            "topic": now.topic.id,
            "word": word,
            "verdict": Self.pronVerdictName(verdict),
            "score": result.map { String($0.soundScore) } ?? "",
            "try": String(now.lines[i].drillTries + 1),
            "assess_ms": String(pronAssessMs),
            "early": pronEarlyUsed ? "1" : "0",
        ])
        // The last miss on this word, to say whether this one came closer.
        let previous = now.lines[i].drillTries > 0 && now.lines[i].feedback?.ok == false
            ? now.lines[i].feedback?.spokenScore : nil
        let fb = PronunciationJudge.feedback(for: verdict, result: result, line: probe,
                                             phonemes: now.topic.phonemes)
        if let fb { now.lines[i].feedback = fb }
        switch verdict {
        case .pass, .notSmooth:
            // One word has no rhythm to judge: its sounds are the take.
            pronUnheard = 0
            pronClearMissed(in: word, topicId: now.topic.id)
            if !word.contains(where: \.isWhitespace) {
                now.lines[i].soloPassed.insert(PronunciationJudge.key(word))
            }
            now.lines[i].drillWord = nil
            now.lines[i].drillTries = 0
            withAnimation(.easeInOut(duration: 0.3)) { pronRound = now }
            HapticEngine.success()
            sendTutorSystem()
            tutorNudge(PronunciationNotes.wordPassed(word: word))
        case .notYet(_, let sound, _, _):
            pronUnheard = 0
            now.lines[i].drillTries += 1
            // Two misses on the word alone and it goes back to the sentence
            // by itself (`maxMisses`). Every miss says what was off and a
            // new tip, never a bare "again" (founder, 2026-11-10).
            if now.lines[i].drillTries >= PronunciationCall.maxMisses {
                now.lines[i].drillWord = nil
                now.lines[i].drillTries = 0
                withAnimation(.easeInOut(duration: 0.25)) { pronRound = now }
                sendTutorSystem()
                tutorNudge(PronunciationNotes.wordBack(word: word, sound: sound, topic: now.topic,
                                                       chosen: false))
                return
            }
            withAnimation(.easeInOut(duration: 0.25)) { pronRound = now }
            tutorNudge(PronunciationNotes.wordAgain(word: word, sound: sound, topic: now.topic,
                                                   heardAs: fb?.heardAs, score: fb?.spokenScore,
                                                   previous: previous, tries: now.lines[i].drillTries))
        case .offScript:
            pronUnheard = 0
            tutorNudge(PronunciationNotes.wordOffScript(word: word))
        case .unheard:
            pronUnheard += 1
            tutorNudge(PronunciationNotes.unheard)
        }
    }

    private static func pronVerdictName(_ v: PronunciationJudge.Verdict) -> String {
        switch v {
        case .pass: return "pass"
        case .notYet: return "not_yet"
        case .notSmooth: return "not_smooth"
        case .offScript: return "off_script"
        case .unheard: return "unheard"
        }
    }

    /// The round's last sentence was passed or left: the course remembers it.
    private func finishPronRound(_ round: PronunciationRound) {
        let mean = round.meanScore
        UserDefaults.standard.set(true, forKey: PronunciationCall.lastFinishedKey(appState.targetLanguage))
        PronunciationProgressStore.update(language: appState.targetLanguage, topicId: round.topic.id) {
            $0.rounds += 1
            $0.passed += round.passedCount
            if let mean {
                $0.lastScore = mean
                $0.bestScore = max($0.bestScore ?? 0, mean)
            }
        }
        Telemetry.log("pron_round_done", ["topic": round.topic.id,
                                          "passed": String(round.passedCount),
                                          "of": String(round.lines.count),
                                          "mean": mean.map(String.init) ?? ""])
    }

    /// After a round: another round of the same sound, another sound (the
    /// course opens), or done for today.
    private func pronAfterRound(turnId: UUID, said: String, round: PronunciationRound) {
        let asked = tutorLine(answeredBy: turnId)
        let target = appState.targetLanguage
        Task { @MainActor in
            let answer = await TutorNext.read(said, askedWith: asked,
                                              lesson: "pronunciation of \(round.topic.symbol)",
                                              targetLanguage: target)
            guard !isTornDown, tutorStillSaid(turnId, said), pronRound?.id == round.id else { return }
            switch answer?.choice {
            case .more, .again:
                startPronRound(topic: round.topic,
                               note: "They want another round of \"\(round.topic.symbol)\". Say in a few words that you're getting new sentences — nothing else.")
            case .new:
                tutorNudge("They want a different sound. Say in a few words that they can pick one on their screen now.")
                showingPronTopics = true
            case .stop:
                tutorNudge(PronunciationNotes.goodbye)
            default:
                tutorNudge(PronunciationNotes.unclearNext)
            }
        }
    }

    /// End: no summary and no book — a round of read sentences is not a
    /// conversation. What it leaves is the ledger and the course's progress.
    private func finishPronunciationCall() {
        phoneCallActive = false
        meter.stop()
        CallNowPlaying.end()
        DailyCallScheduler.releaseAfterLiveCall()
        cancelSilenceTimer()
        cancelIdleWatch()
        if phase == .listening { stopListeningDiscardingChunks() }
        if phase == .speaking { player.stop() }
        realtime.hangUp()
        let lines = pronRound?.lines ?? []
        Telemetry.log("pron_call_ended", [
            "topic": pronTopic?.id ?? "",
            "passed": String(lines.filter(\.passed).count),
            "done": String(lines.filter { $0.passed || $0.skipped }.count),
        ])
        didSaveCurrentSession = true
        phase = .idle
        endAndClose()
    }

    // MARK: - Tutor lesson (`TutorLesson`)

    /// How a tutor call opens: on the call's own topic, on the lesson left
    /// halfway, or on the question of what to practice.
    private func beginTutorCall() async {
        let composed = topicBlurb.isEmpty ? topic : "\(topic). \(topicBlurb)"
        if !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // The tutor speaks once the plan is ready ("Preparing your
            // lesson…" on the strip meanwhile). Planned after the call is up,
            // so the ready note can't go out before there is a socket.
            await startRealtimeCall(opener: nil)
            startTutorLesson(request: composed, picked: false, fromTopic: true, topicId: lessonTopicId)
            return
        }
        if let saved = TutorLessonStore.resumable(language: appState.targetLanguage) {
            tutorLesson = saved
            await startRealtimeCall(opener: nil)
            realtime.setHoldReplies(tutorHolds)
            if saved.inFinalCheck {
                realtime.nudge("The learner is back for the final check of last time's lesson (see TUTOR MODE). Greet them in a few words, say the only thing left is the final check, and ask them to say it all in their own words, in one go — no example, no hints.")
            } else {
                realtime.nudge("The learner is back to finish last time's lesson (see TUTOR MODE). Greet them in a few words, say you're picking it up where you left off and which challenge is next, give its example line, and ask them to say it.")
            }
            return
        }
        await startRealtimeCall(opener: FreeTalkOpeners.tutorOpener(language: appState.targetLanguage))
    }

    /// EVERY learner turn of a tutor call lands here, once (2026-10-28,
    /// founder: "the app decides, the tutor says it"). The stage is fixed
    /// the moment the turn lands:
    /// - no lesson → the line may name a topic (the tutor answers it itself:
    ///   there is nothing to judge, and the plan's "ready" note follows);
    /// - a challenge → `tutorCheck`;  the final check → `tutorFinalCheckTry`;
    /// - a finished lesson → `tutorAfterLesson` (more / again / another).
    /// While a lesson exists the gateway HOLDS the turn (`tutorJudging`) and
    /// the tutor answers once, with the note each of those sends — every
    /// branch below sends exactly one. The judge runs alongside the
    /// correction, never after it, so the hold is one call long, not two.
    private func tutorTurn(turnId: UUID, said: String, ownLanguage: Bool = false, correction: Task<[TurnFix]?, Never>) {
        guard tutorThisCall, !tutorPlanning else { return }
        if tutorJudging {
            tutorWaitTurnAt = Date()
            tutorWaitNoteAt = nil
        }
        guard let lesson = tutorLesson, lesson.droppedAt == nil else {
            let asked = tutorLine(answeredBy: turnId)
            startTutorLesson(request: said, askedWith: asked, picked: false, fromTopic: false)
            return
        }
        if lesson.isFinished {
            tutorAfterLesson(turnId: turnId, said: said, correction: correction, lesson: lesson)
        } else if lesson.inFinalCheck {
            tutorFinalCheckTry(turnId: turnId, said: said, ownLanguage: ownLanguage, correction: correction)
        } else {
            tutorCheck(turnId: turnId, said: said, ownLanguage: ownLanguage, correction: correction)
        }
    }

    /// A try the tutor judged itself, checked behind it (2026-11-13): the
    /// app's verdict (judge + correction, as for a held turn) against what
    /// the tutor's line did. Both clean and the tutor moved on → tick. The
    /// app found a slip, a missing part or a weak answer but the tutor moved
    /// on → a note makes it take that back, and the challenge stays. The
    /// tutor asked again → nothing to do; the next try is judged the same way.
    private func tutorReconcile(turnId: UUID, said: String, lessonId: UUID, index i: Int,
                                challenge: TutorLesson.Challenge, verdict: TutorJudge.Verdict,
                                slips: [String]) async {
        let appClean = slips.isEmpty && verdict.done && !verdict.isWeak
        let reply = await tutorReply(after: turnId)
        let tutorSaid: TutorReplyRead.Said? = if let reply {
            await TutorReplyRead.read(reply, challenge: challenge, targetLanguage: appState.targetLanguage)
        } else { nil }
        guard !isTornDown, var now = tutorLesson, now.id == lessonId, now.current == i else { return }
        Telemetry.log("tutor_self_judge", [
            "app": appClean ? "clean" : (verdict.isWeak ? "weak" : (!slips.isEmpty ? "slips" : "not_done")),
            "tutor": tutorSaid?.rawValue ?? "unknown",
            "index": String(i + 1),
        ])
        if appClean {
            guard tutorSaid == .movedOn else { return }
            tutorLastTry = ""
            tutorLastFixes = []
            tutorMissedThisChallenge = false
            tutorCleanOnce = false
            now.challenges[i].doneAt = Date()
            now.challenges[i].line = said
            if now.current == nil { beginFinalCheck(&now) }
            TutorLessonStore.save(now)
            withAnimation(.easeInOut(duration: 0.3)) { tutorLesson = now }
            // The tutor already moved on: nothing for its next turn to do.
            tutorJustTicked = false
            HapticEngine.success()
            Telemetry.log("tutor_challenge_done", ["index": String(i + 1),
                                                   "of": String(now.challenges.count),
                                                   "by": "self"])
            sendTutorSystem()
            return
        }
        tutorMissedThisChallenge = true
        tutorCleanOnce = false
        tutorLastFixes = slips
        sendTutorSystem()
        guard tutorSaid == .movedOn else { return }
        let what = verdict.isWeak
            ? "as an answer in the real situation it is weak: \(verdict.weak_note ?? "generic")"
            : !slips.isEmpty ? "slips: \(slips.joined(separator: "; "))"
            : "it doesn't do challenge \(i + 1) yet (\"\(challenge.task)\")\(verdict.missing_note.map { ": \($0)" } ?? "")"
        tutorNudge("You moved on, but the app's check of their last try found what you missed: \(what). In at most 15 words take it back (\"Wait, one thing: …\"), name only that, and ask them to say that line once more. The lesson stays on challenge \(i + 1).", waitKind: "self_takeback")
    }

    /// The tutor's line that answered `turnId`, once it has finished.
    private func tutorReply(after turnId: UUID, limit: TimeInterval = 25) async -> String? {
        let start = Date()
        while Date().timeIntervalSince(start) < limit, !isTornDown {
            if let idx = turns.firstIndex(where: { $0.id == turnId }),
               let reply = turns[(idx + 1)...].first(where: { $0.role == .fluentSelf }),
               let text = finishedReplies[reply.id] {
                return text
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    /// The real situation a goal's lesson prepares for ("interview: … at …"),
    /// nil for any other lesson. The judge holds a goal's answers to the bar
    /// of the person on the other side.
    private func realGoalLine(for lesson: TutorLesson) -> String? {
        guard let id = lesson.topicId, id.hasPrefix("goal:") else { return nil }
        let goalId = id.split(separator: ":").dropFirst().first.map(String.init)?.uppercased()
        return UpcomingGoalStore.shared.goals
            .first { $0.id.uuidString.uppercased() == goalId }?.promptLine()
    }

    /// Write the curriculum for `request` and start it. `picked`: chosen on
    /// screen, so the tutor says so right away (nobody spoke). A new pick
    /// replaces the lesson in progress, which stays saved, unfinished.
    private func startTutorLesson(request: String, askedWith: String? = nil,
                                  picked: Bool, fromTopic: Bool = false,
                                  nextRoundOf: TutorLesson? = nil, topicId: String? = nil,
                                  afterOwnReply: Bool = false) {
        guard tutorThisCall, !tutorPlanning else { return }
        let topicId = topicId ?? nextRoundOf?.topicId
        // A topic from the map with its lesson still open (often just its
        // final check) picks that lesson up instead of writing a new one.
        if let topicId, nextRoundOf == nil,
           let open = TutorLessonStore.all(language: appState.targetLanguage)
               .first(where: { $0.topicId == topicId && !$0.isFinished && $0.droppedAt == nil }),
           open.id != tutorLesson?.id {
            if var old = tutorLesson, !old.isFinished {
                old.droppedAt = Date()
                TutorLessonStore.save(old)
            }
            var lesson = open
            if !lesson.sessionIds.contains(sessionId) { lesson.sessionIds.append(sessionId) }
            TutorLessonStore.save(lesson)
            withAnimation(.easeInOut(duration: 0.3)) {
                tutorLesson = lesson
                tutorStripExpanded = true
            }
            tutorJustTicked = false
            tutorLastFixes = []
            tutorLastTry = ""
            tutorMissedThisChallenge = false
            tutorCleanOnce = false
            tutorRepeatAsked = false
            sendTutorSystem()
            if lesson.inFinalCheck {
                realtime.nudge("The learner picked a topic whose lesson they already did (see TUTOR MODE); only the final check is left. Say so in a few words and ask them to say it all in their own words, in one go — no example, no hints.")
            } else {
                realtime.nudge("The learner picked a topic they started before (see TUTOR MODE). Say you're picking it up where they left off, say which challenge is next, give its example line, and ask them to say it.")
            }
            return
        }
        let plannerRequest = topicId.flatMap(TutorCurriculum.request(for:)).map {
            nextRoundOf == nil ? $0 : request
        } ?? request
        if picked, var old = tutorLesson, !old.isFinished {
            old.droppedAt = Date()
            TutorLessonStore.save(old)
        }
        withAnimation(.easeInOut(duration: 0.25)) { tutorPlanning = true }
        // The block says "being set up" while the planner writes, so the
        // tutor can't run a round of its own that the ready note restarts.
        tutorJustTicked = false
        sendTutorSystem()
        if picked {
            realtime.nudge("The learner picked a topic on their screen: \"\(request)\". Say in a few words that you're setting it up — nothing else yet.")
        }
        Task { @MainActor in
            var missReason = "request_failed"
            let planned = await TutorPlanner.plan(
                request: plannerRequest, askedWith: askedWith, targetLanguage: appState.targetLanguage,
                nativeLanguage: appState.nativeLanguage, level: appState.proficiency,
                persona: appState.persona,
                weakPoints: LearnerWeakPoints.lines(profile: appState.learnerProfile,
                                                    sessions: SessionStore.shared.load()),
                miss: { missReason = $0 })
            guard !isTornDown else { return }
            withAnimation(.easeInOut(duration: 0.25)) { tutorPlanning = false }
            guard var lesson = planned else {
                // A line that names no topic is the planner working, not
                // failing, so it gets its own event (the console flags *_failed).
                Telemetry.log(missReason == "no_topic" ? "tutor_plan_no_topic" : "tutor_plan_failed",
                              ["picked": picked ? "1" : "0", "code": missReason])
                // Back off "being set up", or the tutor waits for a plan
                // that never comes.
                sendTutorSystem()
                if let round = nextRoundOf {
                    tutorNudge("Setting up the next round of \"\(round.titleTarget)\" didn't work. Say so in a few words and ask whether they'd like another topic instead.")
                } else if picked || fromTopic {
                    tutorNudge("Setting up the lesson didn't work. Ask them, in one short question, what exactly they want to be able to say about: \"\(request)\".")
                }
                return
            }
            lesson.sessionIds = [sessionId]
            lesson.topicId = topicId
            TutorLessonStore.save(lesson)
            if let topicId, TutorCurriculum.topic(topicId) != nil {
                TutorProgressStore.update(language: appState.targetLanguage, topicId: topicId) {
                    if $0.startedAt == nil { $0.startedAt = Date() }
                }
                Telemetry.log("tutor_topic_started", ["topic": topicId,
                                                      "source": picked ? "map" : (nextRoundOf != nil ? "round" : "voice")])
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                tutorLesson = lesson
                tutorStripExpanded = true
            }
            tutorJustTicked = false
            tutorLastFixes = []
            tutorLastTry = ""
            tutorMissedThisChallenge = false
            tutorCleanOnce = false
            tutorRepeatAsked = false
            Telemetry.log("tutor_lesson_started", ["challenges": String(lesson.challenges.count),
                                                   "picked": picked ? "1" : "0"])
            sendTutorSystem()
            if afterOwnReply {
                // The tutor answered the request itself (self-judged turn,
                // not held) before the app read it as a change of topic, so
                // that line may already have reassured and taught. The plain
                // ready note made it do both again, two lines in a row with
                // no learner turn between ("Pas de souci…" twice, device
                // 2026-11-13).
                tutorNudge("Today's lesson is ready (see TUTOR MODE). Your last line already answered their request and they haven't spoken since, so this line follows straight on from it: no second \"no problem\", no reassurance, don't open the way that line opened, don't announce the topic. If it asked them to say something that already does challenge 1, that stays the one thing on the table: ask for it once more, short. If it asked for something else, or for nothing, replace it in one breath with challenge 1 (\"Let's start with this one: …\"), so only one request is left. Bring challenge 1 in: a natural question that asks for it and how they could say it (its example line, fitted to them). At most two short sentences.", waitKind: "ready_after_self")
            } else if nextRoundOf != nil {
                tutorNudge("The next round is ready (see TUTOR MODE): new challenges, a step further than the last round. Say so in a few words — don't go over the last round again — then bring challenge 1 into the conversation: a natural question that asks for it, about their life, and how they could say it (its example line, fitted to them).")
            } else {
                // A call that opened on its own topic has said nothing yet;
                // every other path already named it ("setting that up"), and
                // naming it again opened three lines in a row the same way
                // ("좋아, 오늘은…", device 2026-11-02).
                let intro = fromTopic
                    ? "In a few words say what it is and that you'll go one step at a time"
                    : "Don't announce the topic again, you already did. Say in a few words that you'll go one step at a time"
                tutorNudge("Today's lesson is ready (see TUTOR MODE). \(intro), then bring challenge 1 into the conversation: a natural question that asks for it, about their life, and how they could say it (its example line, fitted to them).")
            }
        }
    }

    /// One learner try on the current challenge. The APP decides every step
    /// and the tutor says it (founder, 2026-10-28, replacing "the tutor
    /// judges, the app follows" of 2026-10-25: two judges left the checklist
    /// on challenge 3 while the tutor was still asking for challenge 1). The
    /// turn is held at the gateway (`holdReplies`) until the verdict note
    /// below arrives, and the tutor answers once, with it:
    /// - a slip, or the line doesn't do the challenge → NOT YET, what to fix;
    /// - right after a miss → ONCE MORE, so it sticks;
    /// - right on the first try, or right again after "once more" → DONE,
    ///   ticked, and the tutor starts the next challenge (or the final check).
    private func tutorCheck(turnId: UUID, said: String, ownLanguage: Bool = false, correction: Task<[TurnFix]?, Never>) {
        guard let lesson = tutorLesson, let i = lesson.current else { return }
        let asked = tutorLine(answeredBy: turnId)
        let challenge = lesson.challenges[i]
        let target = appState.targetLanguage
        // The tutor already answered this try itself (not held); the app
        // checks behind it and never speaks first (`tutorReconcile`).
        let selfJudged = tutorSelfJudges
        if selfJudged, tutorWaitTurnAt != nil {
            tutorWaitNoteAt = Date()
            tutorWaitKind = "self"
        }
        Task { @MainActor in
            // Asked on every try, fixes or not: a request to change the
            // topic can come with a mistake in it.
            async let judged = TutorJudge.read(said, challenge: challenge,
                                               targetLanguage: target, askedWith: asked,
                                               ownLanguage: ownLanguage,
                                               realGoal: realGoalLine(for: lesson))
            // The judge (~0.7 s) is read before the correction (~3 s on
            // Haiku): a turn that isn't a try is answered without waiting
            // for it (2026-11-06, the wait after Send was ~4–5 s).
            let verdict = await judged
            guard !isTornDown, tutorStillSaid(turnId, said), tutorLesson?.id == lesson.id,
                  tutorLesson?.current == i else { return }
            if verdict?.wantsOtherTopic == true, selfJudged {
                // The tutor already answered this turn itself, whatever it
                // made of it; the ready note follows on from that line.
                dropTutorLesson(said: said, answeredBySelf: true)
                return
            }
            if verdict?.wantsOtherTopic == true {
                // The held turn's one line, before the lesson changes.
                tutorNudge("They asked to leave this lesson. Agree right away in a few words — never \"let's finish this one first\". If they named what they'd like instead, say that's the new lesson and you're setting it up; otherwise ask what they'd like to practice.", waitKind: "leave")
                dropTutorLesson(said: said)
                return
            }
            // A line in their own language is a request for the words, never
            // a miss — and with no judge to say otherwise, still help.
            let kind: TutorJudge.Verdict.Kind = ownLanguage ? .help : (verdict?.turnKind ?? .attempt)
            if selfJudged, kind != .attempt {
                Telemetry.log(kind == .help ? "tutor_turn_help" : "tutor_turn_talk", ["self": "1"])
                return
            }
            if kind == .help {
                Telemetry.log("tutor_turn_help", ["own_language": ownLanguage ? "1" : "0"])
                tutorNudge("Not a try: they \(ownLanguage ? "said this in their own language — they couldn't find the \(LanguageCatalog.englishName(target))" : "asked for help with how to say it, or are stuck"). Teach it: give them the \(LanguageCatalog.englishName(target)) line for what they meant, short and at their level, fitted to challenge \(i + 1) (\"\(challenge.task)\"; e.g. \"\(challenge.example)\"), and invite them to say it. No \"not yet\" — this is help, not a miss.", waitKind: "help")
                return
            }
            if kind == .talk {
                Telemetry.log("tutor_turn_talk")
                tutorNudge("Not a try: they're just talking with you (a remark, a story, or a question). Answer it as a real conversation partner — react to what they meant, answer a question properly. Then steer back with one natural question that asks for challenge \(i + 1) (\"\(challenge.task)\"). No verdict, no \"not yet\".", waitKind: "talk")
                return
            }
            let fixes = await correction.value ?? []
            guard !isTornDown, tutorStillSaid(turnId, said), var now = tutorLesson,
                  now.id == lesson.id, now.current == i else { return }
            let slips = fixes.map { "\"\($0.was)\" → \"\($0.now)\"" }
            guard let verdict else {
                // The tutor already answered it; with no check there is
                // nothing to add or tick.
                if !selfJudged {
                    tutorNudge("The app couldn't check that line. Ask them, in a few words, to say it once more.", waitKind: "unchecked")
                }
                return
            }
            tutorLastTry = said
            if selfJudged {
                await tutorReconcile(turnId: turnId, said: said, lessonId: lesson.id, index: i,
                                     challenge: challenge, verdict: verdict, slips: slips)
                return
            }
            // A goal's lesson (an interview): an answer the interviewer would
            // count against them is not done, whatever the grammar and the
            // level (2026-11-12, founder). The slips stay on the card.
            if verdict.isWeak {
                tutorMissedThisChallenge = true
                tutorCleanOnce = false
                tutorLastFixes = slips
                tutorJustTicked = false
                sendTutorSystem()
                Telemetry.log("tutor_turn_weak", ["slips": String(slips.count)])
                tutorNudge("Result: NOT YET. As an answer in the real situation it is weak: \(verdict.weak_note ?? "generic"). In at most 25 words: say plainly how the person on the other side would hear it, give one concrete way to make it stronger from their own life, and ask them to try again. No grammar talk, no \"great\".", waitKind: "weak")
                return
            }
            if !slips.isEmpty || !verdict.done {
                tutorMissedThisChallenge = true
                tutorCleanOnce = false
                tutorLastFixes = slips
                tutorJustTicked = false
                sendTutorSystem()
                let what = slips.isEmpty
                    ? "It doesn't do challenge \(i + 1) yet (\"\(challenge.task)\")\(verdict.missing_note.map { ": \($0)" } ?? "")."
                    : "Slips: \(slips.joined(separator: "; "))."
                // Short, the way a coach says it (2026-11-12, founder: "just
                // 'no s at the end, again' — the rest is filler"). The fix is
                // already on their screen; the whole sentence read back and a
                // reaction to the content made every miss a paragraph.
                if !slips.isEmpty {
                    tutorNudge("Result: NOT YET. \(what) In at most 10 words: name only what to fix, the way a coach would (\"Service, no s. Again.\"), and ask them to say it again. No reaction to the content, no whole sentence read back, no \"great\".", waitKind: "not_yet")
                } else {
                    tutorNudge("Result: NOT YET, it doesn't do the challenge yet. \(what) In at most 15 words: say what's missing and give the example fitted to them, then ask them to say it. No reaction to the content, no \"great\".", waitKind: "not_yet")
                }
                return
            }
            tutorLastFixes = []
            if tutorMissedThisChallenge && !tutorCleanOnce {
                tutorCleanOnce = true
                tutorJustTicked = false
                sendTutorSystem()
                tutorNudge("Result: ONCE MORE. That was right. In at most 8 words: say it was right and ask for it once more, so it sticks. No reaction to the content. Don't move on yet.", waitKind: "once_more")
                return
            }
            tutorLastTry = ""
            tutorMissedThisChallenge = false
            tutorCleanOnce = false
            tutorRepeatAsked = false
            now.challenges[i].doneAt = Date()
            now.challenges[i].line = said
            // The last tick opens the final check; passing it finishes the
            // lesson, and even then the call goes on (device, 2026-10-24:
            // three ticks in 80 s and the call cut to the book mid-flow).
            let last = now.current == nil
            if last { beginFinalCheck(&now) }
            TutorLessonStore.save(now)
            withAnimation(.easeInOut(duration: 0.3)) { tutorLesson = now }
            tutorJustTicked = true
            HapticEngine.success()
            Telemetry.log("tutor_challenge_done", ["index": String(i + 1),
                                                   "of": String(now.challenges.count),
                                                   "by": "app"])
            sendTutorSystem()
            if last {
                tutorNudge("Result: DONE — that was the last challenge. In a few words say that's every part, then ask them to say it all now, in their own words, in one go — no example, no list of the parts, no hints. That is the final check.", waitKind: "done")
            } else if let n = now.current {
                let next = now.challenges[n]
                tutorNudge("Result: DONE — challenge \(i + 1) is checked off. A short, real \"you got it\" that reacts to what they said, then move the conversation on to challenge \(n + 1) (\"\(next.task)\"): a natural question that asks for it, about their life, and how they could say it (\"\(next.example)\", fitted to them).", waitKind: "done")
            }
        }
    }

    /// The lesson is done and the tutor asked "once more, more of this, or
    /// another topic?". The turn is held; the app reads the answer and the
    /// tutor says ONE line for it, sent BEFORE anything changes state, so
    /// the reply never comes from a block that has already moved on.
    /// A "once more" is judged like the final check (slips named), without
    /// changing the pass.
    private func tutorAfterLesson(turnId: UUID, said: String,
                                  correction: Task<[TurnFix]?, Never>, lesson: TutorLesson) {
        let asked = tutorLine(answeredBy: turnId)
        let target = appState.targetLanguage
        let repeating = tutorRepeatAsked
        let next = TutorCurriculum.next(
            progress: TutorProgressStore.all(language: target),
            level: appState.proficiency, excluding: lesson.topicId)
        Task { @MainActor in
            if repeating {
                tutorRepeatAsked = false
                async let judged = TutorFinalCheck.read(said, lesson: lesson, askedWith: asked,
                                                        targetLanguage: target)
                let fixes = await correction.value ?? []
                let verdict = await judged
                guard !isTornDown, tutorStillSaid(turnId, said),
                      tutorLesson?.id == lesson.id else { return }
                if verdict?.attempt == true {
                    let slips = fixes.map { "\"\($0.was)\" → \"\($0.now)\"" }
                    if slips.isEmpty, verdict?.understood != false, (verdict?.missing ?? []).isEmpty {
                        tutorNudge("Their once-more was clean. Say so warmly in a few words, then ask whether they want more of this topic or another one.")
                    } else {
                        tutorNudge("Their once-more:\(slips.isEmpty ? "" : " slips \(slips.joined(separator: "; ")).")\(verdict?.missing_note.map { " Missing or unclear: \($0)." } ?? "") Name each by saying it the right way, briefly — no \"great\". Then ask whether they want more of this topic or another one.")
                    }
                    return
                }
                // Not an attempt: read it as an answer to the question instead.
            }
            let answer = await TutorNext.read(said, askedWith: asked, lesson: lesson.title,
                                              targetLanguage: target,
                                              suggested: next?.topic.english)
            guard !isTornDown, tutorStillSaid(turnId, said),
                  tutorLesson?.id == lesson.id, !tutorPlanning else { return }
            let choice = answer?.choice ?? .unclear
            Telemetry.log("tutor_after_lesson", ["choice": choice.rawValue])
            switch choice {
            case .more:
                tutorNudge("They want more of this topic. Say great in a few words and that you're setting up the next round, a step further — nothing else yet.")
                let done = lesson.challenges.map(\.task).joined(separator: "; ")
                startTutorLesson(
                    request: "More practice on \"\(lesson.title)\" — the next round, one step further. Already done: \(done). New challenges only.",
                    picked: false, fromTopic: false, nextRoundOf: lesson)
            case .new:
                let topic = answer?.topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if topic.isEmpty {
                    tutorNudge("They want another topic. Say you're saving today's lesson in their book, and ask what they want to practice next — they can also pick one from the button on their screen.")
                } else {
                    tutorNudge("They chose another topic: \"\(topic)\". Say you're saving today's lesson in their book and setting that one up — nothing else yet.")
                }
                saveTutorBookAndMoveOn(keepingFrom: turnId)
                if !topic.isEmpty {
                    let isNext = next.map { topic.localizedCaseInsensitiveCompare($0.topic.english) == .orderedSame } ?? false
                    startTutorLesson(request: topic, picked: false, fromTopic: false,
                                     topicId: isNext ? next?.topic.id : nil)
                }
            case .again:
                tutorRepeatAsked = true
                tutorNudge("They want to say it once more. Ask them to go ahead — the whole thing, in one go, no hints.")
            case .stop:
                tutorNudge("They're done for today. Say goodbye warmly in a few words; the call ends when they hang up. Don't start anything new.")
            case .unclear:
                tutorNudge("Answer what they said in one short line, then ask again, in other words: say it once more, more of this topic, or another topic?")
            }
        }
    }

    /// The finished lesson's talk becomes its own book now, while the call
    /// goes on: the turns up to the learner's "another topic" are saved and
    /// summarized in the background, and the rest of the call is a new
    /// session (the answer and the reply being written to it stay on screen
    /// and carry over).
    private func saveTutorBookAndMoveOn(keepingFrom firstKept: UUID?) {
        let cut = firstKept.flatMap { id in turns.firstIndex { $0.id == id } } ?? turns.count
        let bookTurns = Array(turns[..<cut])
        let lesson = tutorLesson
        guard bookTurns.contains(where: { $0.role == .user }) else { return }
        let bookId = sessionId
        let book = Session(
            id: bookId,
            userId: userId,
            targetLanguage: appState.targetLanguage,
            mode: .conversation,
            topic: topic.isEmpty ? nil : topic,
            startedAt: sessionStartedAt,
            endedAt: Date(),
            turns: tutorRoled(bookTurns),
            summary: nil,
            origin: sessionOrigin,
            originScenarioId: sessionScenarioId,
            counterpartId: sessionCounterpartId,
            tutorLesson: lesson?.record
        )
        if var l = lesson, !l.sessionIds.contains(bookId) {
            l.sessionIds.append(bookId)
            TutorLessonStore.save(l)
        }
        SessionStore.shared.save(book)
        Telemetry.log("tutor_book_saved", ["turns": String(bookTurns.count)])
        // The rest of the call is a fresh session.
        withAnimation(.easeInOut(duration: 0.25)) { tutorLesson = nil }
        tutorLastFixes = []
        tutorJustTicked = false
        tutorLastTry = ""
        tutorMissedThisChallenge = false
        tutorCleanOnce = false
        tutorRepeatAsked = false
        turns = Array(turns[cut...])
        sessionId = UUID()
        sessionStartedAt = Date()
        didSaveCurrentSession = false
        meter.stop()
        meter.start(sessionId: sessionId)
        sendTutorSystem()
        Task { @MainActor in
            do {
                _ = try await SessionSummarizer.summarize(session: book, appState: appState)
                refreshDashboard()
            } catch {
                // The draft stays on the shelf with "generate the review
                // material", like any summary that failed.
                Telemetry.log("tutor_book_summary_failed", ["error": (error as NSError).domain])
            }
        }
    }

    /// Leave the lesson: by voice (`said`, judged by `TutorJudge`) or from
    /// the strip's menu. It is never offered again; a topic named in the
    /// same breath ("let's do ordering instead") starts the next one.
    private func dropTutorLesson(said: String?, answeredBySelf: Bool = false) {
        guard var lesson = tutorLesson else { return }
        if lesson.isFinished, said == nil {
            // A finished lesson isn't dropped: it becomes its book, and the
            // tutor asks what's next.
            saveTutorBookAndMoveOn(keepingFrom: nil)
            realtime.nudge("The learner tapped to choose another topic. The app is saving the finished lesson in their book. Say so in a few words and ask what they want to practice next — they can also pick a topic from the button on their screen.")
            return
        }
        if !lesson.isFinished { lesson.droppedAt = Date() }
        TutorLessonStore.save(lesson)
        Telemetry.log("tutor_lesson_dropped", ["by": said == nil ? "menu" : "voice",
                                               "done": String(lesson.doneCount)])
        withAnimation(.easeInOut(duration: 0.25)) { tutorLesson = nil }
        tutorLastFixes = []
        tutorJustTicked = false
        tutorLastTry = ""
        tutorMissedThisChallenge = false
        tutorCleanOnce = false
        tutorRepeatAsked = false
        sendTutorSystem()
        if let said {
            // The tutor already agreed in its reply (the block's rule); the
            // words may also name the next topic.
            let asked = turns.last(where: { $0.role == .fluentSelf })?.transcript ?? ""
            startTutorLesson(request: said, askedWith: asked, picked: false, fromTopic: false,
                             afterOwnReply: answeredBySelf)
        } else {
            realtime.nudge("The learner tapped to choose another topic, and the app dropped today's lesson. Say sure in a few words and ask what they want to practice instead — they can also pick a topic from the button on their screen.")
        }
    }

    /// Every challenge is ticked: the final check opens (`TutorFinalCheck`).
    private func beginFinalCheck(_ lesson: inout TutorLesson) {
        guard lesson.check == nil || lesson.check?.passedAt != nil else { return }
        lesson.check = .init(startedAt: Date())
        Telemetry.log("tutor_challenges_done", ["of": String(lesson.challenges.count)])
        if let id = lesson.topicId, TutorCurriculum.topic(id) != nil {
            TutorProgressStore.update(language: appState.targetLanguage, topicId: id) {
                if $0.lessonDoneAt == nil { $0.lessonDoneAt = Date() }
            }
        }
    }

    /// The turn still reads what was judged. A turn the learner carried on
    /// after a pause is joined and judged again as a whole; the verdict on
    /// its first half must not answer it too.
    private func tutorStillSaid(_ turnId: UUID, _ said: String) -> Bool {
        turns.first(where: { $0.id == turnId })?.transcript == said
    }

    /// The tutor line the learner's turn ANSWERED: the last one before it.
    /// Never "the newest tutor line" — the check runs after the correction
    /// call, by when the tutor has usually already replied, so the judge
    /// read the reply as the question (device, 2026-10-28: a challenge-4
    /// answer was taken for the final check because the reply to it asked
    /// for the whole thing, and "not yet" played over that reply).
    private func tutorLine(answeredBy turnId: UUID) -> String {
        let end = turns.firstIndex(where: { $0.id == turnId }) ?? turns.count
        return turns[..<end].last(where: { $0.role == .fluentSelf })?.transcript ?? ""
    }

    /// One answer during the final check. The judge says whether it was an
    /// attempt at the whole thing and what it left out; the slips are the
    /// correction call's. The outcome is code, and the tutor is told what to
    /// say: a pass names every slip (praise only for a clean answer), a
    /// shaky pass is asked for once more first, a missing part is named and
    /// practiced. It can't be skipped (founder, 2026-10-28).
    private func tutorFinalCheckTry(turnId: UUID, said: String, ownLanguage: Bool = false, correction: Task<[TurnFix]?, Never>) {
        guard let lesson = tutorLesson, lesson.inFinalCheck else { return }
        let asked = tutorLine(answeredBy: turnId)
        let target = appState.targetLanguage
        if ownLanguage {
            // Not a try at the whole thing: the words they're missing.
            Telemetry.log("tutor_turn_help", ["own_language": "1", "check": "1"])
            tutorNudge("Final check: they said this in their own language — they couldn't find the \(LanguageCatalog.englishName(target)). Not a try and not a miss: give them the \(LanguageCatalog.englishName(target)) way to say what they meant, short, then ask them to say it all, in one go.")
            return
        }
        Task { @MainActor in
            async let judged = TutorFinalCheck.read(said, lesson: lesson, askedWith: asked,
                                                    targetLanguage: target)
            let fixes = await correction.value ?? []
            let slips = fixes.map { "\"\($0.was)\" → \"\($0.now)\"" }
            let verdict = await judged
            guard !isTornDown, tutorStillSaid(turnId, said), var now = tutorLesson,
                  now.id == lesson.id, now.inFinalCheck, var check = now.check else { return }
            guard let verdict else {
                tutorNudge("The app couldn't check that answer. Ask them, in a few words, to say it all once more, in one go.")
                return
            }
            let outcome = TutorFinalCheck.outcome(verdict, slips: slips.count,
                                                  onceMoreUsed: check.onceMoreUsed)
            guard outcome != .notAnAttempt else {
                // The turn is held for a note: answer it as what it was.
                if verdict.wants_example == true {
                    // Asked to be shown: show it, from their own lines.
                    let own = now.challenges.compactMap(\.line).map { "\"\($0)\"" }
                        .joined(separator: " ")
                    tutorNudge("They asked you to show them how the whole thing goes. Show it: say it as ONE natural answer, in \(LanguageCatalog.englishName(appState.targetLanguage)), built from their own lines in this lesson\(own.isEmpty ? "" : " (\(own))") with any slip fixed — like a model answer, no list of parts. Then ask them to say it themselves now, in one go.")
                    return
                }
                tutorNudge("Final check: that was not an attempt at the whole thing (a question, a remark, or one part only).\(slips.isEmpty ? "" : " Slips in it: \(slips.joined(separator: "; ")) — say that line back the right way first.") Answer what they said in a line, give no verdict on the whole, then ask them to say it all, in one go.")
                return
            }
            // A whole try with nothing on screen: the one tutor line that is
            // evidence of their level (founder, 2026-10-28). Stamped when the
            // talk is saved (`tutorRoled`).
            tutorCheckTurnIds.insert(turnId)
            check.tries += 1
            Telemetry.log("tutor_check_result", ["outcome": outcome.rawValue,
                                                 "try": String(check.tries),
                                                 "slips": String(slips.count),
                                                 "topic": now.topicId ?? ""])
            let slipList = slips.joined(separator: "; ")
            switch outcome {
            case .notAnAttempt:
                return
            case .notYet:
                check.onceMoreUsed = false
                now.check = check
                TutorLessonStore.save(now)
                tutorLesson = now
                let what = verdict.missing_note.map { "Missing or unclear: \($0)." } ?? ""
                tutorNudge("Final check result: NOT YET. \(what)\(slips.isEmpty ? "" : " Slips: \(slipList).") Tell them plainly, in a few words, what was missing — no \"great job\", nothing that sounds like a pass. Then practice just that part once: give them the line for it and ask them to say it. After that, ask for the whole thing again, in one go, with no hints.")
            case .onceMore:
                check.onceMoreUsed = true
                now.check = check
                TutorLessonStore.save(now)
                tutorLesson = now
                tutorNudge("Final check result: ONCE MORE. Every part was there and you understood it, but it wasn't clean yet.\(slips.isEmpty ? "" : " Slips: \(slipList).") Don't say they passed. Say you understood all of it\(slips.isEmpty ? "" : ", name each slip by saying it the right way, briefly"), and ask them to say the whole thing once more, in one go\(slips.isEmpty ? ", a little more smoothly" : ", with those fixed"). Don't call it great.")
            case .pass:
                check.passedAt = Date()
                check.line = said
                check.slips = slips
                now.check = check
                now.finishedAt = Date()
                TutorLessonStore.save(now)
                withAnimation(.easeInOut(duration: 0.3)) { tutorLesson = now }
                HapticEngine.success()
                Telemetry.log("tutor_lesson_finished", ["of": String(now.challenges.count),
                                                        "tries": String(check.tries)])
                var nextLine = ""
                if let id = now.topicId, TutorCurriculum.topic(id) != nil {
                    TutorProgressStore.update(language: appState.targetLanguage, topicId: id) {
                        if $0.passedAt == nil { $0.passedAt = Date() }
                        if $0.lessonDoneAt == nil { $0.lessonDoneAt = Date() }
                        $0.rounds += 1
                    }
                    Telemetry.log("tutor_topic_passed", ["topic": id])
                    if let next = TutorCurriculum.next(
                        progress: TutorProgressStore.all(language: appState.targetLanguage),
                        level: appState.proficiency, excluding: id) {
                        nextLine = " If they'd like another topic, suggest the next one on their curriculum: \"\(next.topic.english)\" (say it in their language)."
                    }
                }
                tutorJustTicked = false
                sendTutorSystem()
                if slips.isEmpty {
                    tutorNudge("Final check result: PASSED, nothing to fix. Tell them warmly that they passed — they can say it now, on their own. Then ask whether they want more of this or another topic.\(nextLine)")
                } else {
                    tutorNudge("Final check result: PASSED. They said every part and you understood them. Slips: \(slipList). Tell them they passed and that you understood all of it, then name each slip in a few words by saying it the right way (\"one small thing: …\"). Don't call it great, perfect or flawless. Then ask whether they'd like to say it once more, or move on.\(nextLine)")
                }
            }
        }
    }

    /// The call's turns with each learner line's tutor role stamped
    /// (founder, 2026-10-28): in a tutor call every learner line is a drill
    /// except a judged final-check try. A line already stamped (a resumed
    /// talk) keeps its role; a call that was never tutored is unchanged.
    private func tutorRoled(_ list: [Turn]) -> [Turn] {
        guard tutorWasOn || tutorThisCall else { return list }
        return list.map { t in
            guard t.role == .user else { return t }
            var t = t
            if tutorCheckTurnIds.contains(t.id) { t.tutorRole = .check }
            else if t.tutorRole == nil { t.tutorRole = .drill }
            return t
        }
    }

    /// A lesson is running (a challenge or the final check): every answer
    /// waits for the app's verdict.
    private var tutorJudging: Bool {
        if pronThisCall { return true }
        guard tutorThisCall, !tutorPlanning, let lesson = tutorLesson else { return false }
        return lesson.droppedAt == nil
    }

    /// The tutor judges a challenge's tries itself and answers at once, like
    /// free talk (2026-11-13, founder); the app checks behind it
    /// (`tutorReconcile`). The final check and what follows a lesson are
    /// still answered with the app's verdict.
    private var tutorSelfJudges: Bool {
        guard tutorThisCall, !tutorPlanning, let lesson = tutorLesson,
              lesson.droppedAt == nil, !lesson.isFinished, !lesson.inFinalCheck else { return false }
        return lesson.current != nil
    }

    /// Every learner turn waits at the gateway for the app's note.
    private var tutorHolds: Bool { tutorJudging && !tutorSelfJudges }

    private var tutorInFinalCheck: Bool {
        tutorThisCall && tutorLesson?.inFinalCheck == true
    }

    #if DEBUG
    /// Store screenshots: a staged talk on the real screen (`DebugCapture.callSeed`).
    private func applyCaptureSeed(_ seed: String) {
        let t = CaptureCallSeed.texts(for: appState.nativeLanguage)
        let now = Date()
        islandExpanded = false
        meter.clock.add(seed == "fix" ? 181 : 134)
        goalItems = [
            TalkGoalItem(key: "strength", text: "strength", isWord: true),
            TalkGoalItem(key: "come up", text: "come up", isWord: false),
            TalkGoalItem(key: "in one go", text: "in one go", isWord: false),
        ]
        if seed == "pair" {
            // Two whole lines: the learner's slip, and the fluent self saying it right.
            goalItems = []
            turns = [
                Turn(id: UUID(), role: .user, audioURL: nil,
                     transcript: "Yesterday I go to the office early, so I leave at four.",
                     durationMs: 4000, timestamp: now),
                Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                     transcript: "Oh, so you went in early yesterday and left at four? Nice!",
                     durationMs: 3000, timestamp: now),
                Turn(id: UUID(), role: .user, audioURL: nil,
                     transcript: "Yes. I am live in Seoul since three years.",
                     durationMs: 3000, timestamp: now),
                Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                     transcript: "Right, you've been living in Seoul for three years now.",
                     durationMs: 3000, timestamp: now),
            ]
            phoneCallActive = false
            isPausedForIdle = true
            return
        }
        if seed == "fix" {
            tutorThisCall = true
            tutorWasOn = true
            usedGoalKeys = ["come up"]
            tutorLesson = TutorLesson(
                id: UUID(), title: t.lesson, titleTarget: "Introducing yourself in a job interview",
                language: "en",
                challenges: t.goals.enumerated().map { i, g in
                    TutorLesson.Challenge(id: UUID(), goal: g, task: g, example: "",
                                          doneAt: i < 2 ? now : nil, line: nil)
                },
                createdAt: now)
            let said = "My background in problem solving helps me handle unexpected situation calmly."
            turns = [
                Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                     transcript: "Nice! And how would your strengths help you in this job?",
                     durationMs: 3000, timestamp: now),
                Turn(id: UUID(), role: .user, audioURL: nil, transcript: said, durationMs: 5000,
                     timestamp: now,
                     suggestion: TurnSuggestion(
                        alternative: "My background in problem solving helps me stay calm when unexpected situations come up.",
                        reason: t.reason,
                        fixes: [TurnFix(was: "helps me handle unexpected situation calmly",
                                        now: "helps me handle unexpected situations calmly", why: t.why)])),
                Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                     transcript: "Ah, so close, and the idea really comes across. We'd say: \"My background in problem-solving helps me stay calm when unexpected situations come up.\"",
                     durationMs: 6000, timestamp: now),
            ]
            phoneCallActive = false
            isPausedForIdle = true
        } else {
            coachReply = CoachReply(say: "I'm working on [an AI project] right now, and it's going really well.",
                                    meaning: t.coachMeaning, turnId: UUID())
            turns = [
                Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                     transcript: "Hey! How's your week going so far?",
                     durationMs: 2000, timestamp: now),
                Turn(id: UUID(), role: .user, audioURL: nil,
                     transcript: "Pretty busy, but in a good way.",
                     durationMs: 2000, timestamp: now),
                Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                     transcript: "Busy in a good way is the best kind. So what are you working on these days?",
                     durationMs: 4000, timestamp: now),
            ]
            phoneCallActive = true
            phase = .listening
        }
    }
    #endif

    private func sendTutorSystem() {
        guard RealtimeMode.isEnabled, phoneCallActive else { return }
        realtime.setSystem(systemPrompt() + realtimeStyleRules)
        // While a lesson runs the tutor answers only with the app's verdict,
        // so an answer is never met twice and the checklist never disagrees
        // with what the tutor says (device, 2026-10-28).
        realtime.setHoldReplies(tutorHolds)
    }

    /// The hello is out (or the learner spoke over it): from here the prompt
    /// knows the day, the hour and the talks before this one.
    private func giveClockAfterHello() {
        guard helloBeforeClock else { return }
        helloBeforeClock = false
        realtime.setSystem(systemPrompt() + realtimeStyleRules)
    }

    private func systemPrompt() -> String {
        // Pinned in onAppear; a prompt asked for before that still gets a
        // clock rather than none.
        if promptClock == nil { pinPromptClock() }
        if pronThisCall {
            return PronunciationNotes.systemPrompt(target: appState.targetLanguage,
                                                   level: appState.proficiency,
                                                   round: pronRound, planning: pronPlanning)
        }
        let composedTopic = topicBlurb.isEmpty ? topic : "\(topic). \(topicBlurb)"
        return ConversationEngine.conversationSystemPrompt(
            targetLanguage: appState.targetLanguage,
            nativeLanguage: appState.nativeLanguage,
            level: appState.proficiency,
            topPatterns: appState.learnerProfile.recurringMistakes,
            weakVocabAreas: appState.learnerProfile.weakVocabAreas,
            topic: composedTopic,
            persona: appState.persona,
            counterpart: counterpart,
            personHistory: personHistory,
            newsFacts: newsFacts,
            brief: sessionScenarioId.flatMap { sid in
                appState.scenarios.first { $0.id == sid }?.brief
            },
            firstMeeting: isFirstMeeting,
            clock: helloBeforeClock ? nil : promptClock,
            tutor: tutorThisCall,
            freeTalkCue: freeTalkCue,
            earlierToday: earlierToday,
            learnerPicksTopic: learnerPicksTopic,
            tutorLesson: tutorLesson,
            tutorJustTicked: tutorJustTicked,
            tutorLastFixes: tutorLastFixes,
            tutorPlanning: tutorPlanning,
            tutorSelfJudges: tutorSelfJudges,
            tutorRealGoal: tutorLesson.flatMap(realGoalLine(for:)),
            freeMode: isFreeMode,
            // Like the clock, the index joins after the hello: a list of
            // earlier talks beside "say hello" is a hello about one of them.
            pastTalks: helloBeforeClock ? []
                : TalkRecall.indexLines(recallIndex, now: promptClock?.now ?? Date()),
            recalledTalks: recalledTalks.map {
                TalkRecall.record(of: $0, about: recallQueries[$0.id] ?? "", now: promptClock?.now ?? Date())
            }
        )
    }

    /// What the island calls Free talk (2026-11-12): no person, no scene,
    /// not tutor or pronunciation. Its prompt is facts only
    /// (`ConversationEngine.freeTalkPrompt`), with no style rules after it.
    private var isFreeMode: Bool {
        counterpart == nil && sessionScenarioId == nil && !tutorThisCall && !pronThisCall
    }

    /// The live call's style rules, left off in free mode.
    private var realtimeStyleRules: String {
        isFreeMode ? "" : Self.callStyleRules
    }
}

// MARK: - Subviews

/// Where the end of the transcript sits relative to the top of the feed's
/// viewport. Compared against the viewport height to answer one question:
/// is the learner still reading the live end of the call, or did they scroll
/// back into it? See `ConversationView.followTail`.
private struct FeedTailOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TurnView: View {
    let turn: Turn
    let nativeLanguage: String
    /// False when the app language IS the target — "Meaning" would translate
    /// a line into the language it is already in.
    /// The grammar focus's name when this turn's correction is that slip
    /// coming back (coach mode) — the card wears it as a badge.
    var focusRepeatLabel: String? = nil
    var translates = true
    /// The learner's own switch (`CallSettings`). The card is still BUILT and
    /// still saved — this only decides whether it is drawn mid-call, so the
    /// summary, the drill cards and the talk's book are untouched by it.
    var showsCorrections = true
    /// The other side's label — the person or role on a cast call.
    var otherName: String = chrome("Future self")
    /// A pronunciation take: the word or sentence on screen, shown in place
    /// of the transcript (`ConversationView.pronReadTexts`).
    var readText: String? = nil

    @State private var translation: String?
    @State private var showing = false
    @State private var loading = false

    /// Speaker separation (side, fill, name label) comes from `DialogueLine`
    /// — the same component Watch and the conversation archive use — so the
    /// three surfaces stay in sync when the style changes.
    private var speaker: DialogueSpeaker { turn.role == .user ? .user : .other }

    var body: some View {
        DialogueLine(speaker: speaker,
                     name: turn.role == .user ? chrome("You") : otherName,
                     scale: .call) {
            // The learner's line goes up the instant they stop talking — it is
            // the text they were already watching build on screen, so there is
            // nothing to wait for. Better transcriptions (the recognizer's
            // rescored pass, then Gemini's audio-grounded one) land later and
            // edit this in place; a placeholder + swap made a background
            // refinement look like a step the learner had to sit through.
            // Only a genuinely EMPTY line has nothing to show yet.
            if turn.transcript.isEmpty && turn.transcriptPending {
                Text(explain("Writing down what you said…"))
                    .opacity(0.6)
                    .italic()
            } else if turn.role == .user, let readText {
                Text(readText)
            } else if turn.role == .user {
                FuriganaText(turn.transcript, rubyFont: .caption2) {
                    Text(turn.transcript)
                        // For the learner's line only: a better transcription
                        // replacing the first one. A fluent-self reply streams in
                        // dozens of deltas, and an animation per delta fought the
                        // feed's bottom anchor — the bubble grew with a wobble
                        // (2026-10-08).
                        .animation(.easeInOut(duration: 0.2), value: turn.transcript)
                }
            } else {
                // The fluent self's line: each word the reveal adds fades in
                // rather than popping (founder, 2026-10-15, "like Grok") —
                // opacity only, so the layout and the bottom anchor are
                // untouched. With furigana the line is laid out in units, and
                // the fade gives way to it.
                FuriganaText(turn.transcript, rubyFont: .caption2) {
                    FadeInText(text: turn.transcript)
                }
            }
        } accessory: {
            // Nothing to translate or correct until there is a line.
            if turn.transcript.isEmpty {
                EmptyView()
            } else {
            VStack(alignment: speaker.alignment, spacing: 6) {
                if translates {
                Button(action: toggleMeaning) {
                    HStack(spacing: 4) {
                        if loading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "character.bubble")
                        }
                        Text(showing ? "Hide meaning" : "Meaning")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                }

                if showing, let t = translation {
                    Text(t)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The card appears only after the fluent self is AUDIBLE:
                // `Turn.suggestion` for a live turn is set by
                // `flushDeferredTurnWork` (or directly, once the voice is
                // already out) — never while the reply is still loading.
                // Painting it earlier read as "it corrects me, then answers"
                // on every turn, whatever the transcript-swap fixes did.
                if turn.role == .user, showsCorrections, let suggestion = turn.suggestion {
                    SuggestionChip(suggestion: suggestion, original: turn.transcript,
                                   nativeLanguage: nativeLanguage,
                                   focusRepeatLabel: focusRepeatLabel)
                }
            }
            }
        }
        // A line the learner disowned mid-call ("that wasn't me"): dimmed, as
        // on the transcript page, so they can see it was taken out.
        .opacity(turn.role == .user && turn.excludedFromScoring ? 0.45 : 1)
        // A late transcription upgrade rewrites the line under a translation
        // that was fetched for the OLD wording. Drop it and, if the learner is
        // looking at it, fetch the meaning of what the bubble now says.
        .onChange(of: turn.transcript) { _, _ in
            translation = nil
            if showing { showing = false; toggleMeaning() }
        }
    }

    private func toggleMeaning() {
        if showing { showing = false; return }
        showing = true
        guard translation == nil else { return }
        if let c = Translator.cached(readText ?? turn.transcript, to: nativeLanguage) {
            translation = c
            return
        }
        loading = true
        Task {
            let t = await Translator.translate(readText ?? turn.transcript, to: nativeLanguage)
            translation = t
            loading = false
            if t == nil { showing = false }
        }
    }
}

/// Text whose newly APPENDED characters fade in over `fade`. Characters on
/// screen when it appears, and a line rewritten rather than extended, show at
/// once — only growth fades. Opacity only, never size: the bubble's height
/// still follows the text the instant it grows. Android twin: `FadeInText`
/// in TalkScreen.kt.
private struct FadeInText: View {
    let text: String
    private static let fade: TimeInterval = 0.32

    @State private var shown = ""
    /// When each Character appeared (0 = was already there).
    @State private var born: [TimeInterval] = []
    @State private var animating = false
    @State private var stopTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !animating)) { ctx in
            Text(attributed(now: ctx.date.timeIntervalSinceReferenceDate))
        }
        .onAppear {
            shown = text
            born = Array(repeating: 0, count: text.count)
        }
        .onChange(of: text) { _, new in
            let now = Date().timeIntervalSinceReferenceDate
            if new.hasPrefix(shown) {
                born += Array(repeating: now, count: max(0, new.count - shown.count))
            } else {
                born = Array(repeating: 0, count: new.count)
            }
            shown = new
            animating = true
            stopTask?.cancel()
            stopTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((Self.fade + 0.05) * 1_000_000_000))
                if !Task.isCancelled { animating = false }
            }
        }
    }

    private func attributed(now: TimeInterval) -> AttributedString {
        let chars = Array(text)
        guard born.count == chars.count else { return AttributedString(text) }
        var out = AttributedString()
        var i = 0
        while i < chars.count {
            let b = born[i]
            var j = i + 1
            while j < chars.count, born[j] == b { j += 1 }
            var run = AttributedString(String(chars[i..<j]))
            if b != 0 {
                let p = min(1, max(0, (now - b) / Self.fade))
                let alpha = 1 - (1 - p) * (1 - p)   // ease-out
                if alpha < 1 { run.foregroundColor = Color.primary.opacity(alpha) }
            }
            out += run
            i = j
        }
        return out
    }
}

struct SuggestionChip: View {
    let suggestion: TurnSuggestion
    let original: String
    let nativeLanguage: String
    var focusRepeatLabel: String? = nil

    @State private var reasonNative: String?
    @State private var showing = false
    @State private var loading = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
                .font(.footnote)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if let focusRepeatLabel {
                    GrammarFocusRepeatBadge(label: focusRepeatLabel)
                        .padding(.bottom, 2)
                }
                Text(highlightedCorrection(suggestion.alternative, original: original, baseFont: .subheadline))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let fixes = suggestion.fixes, !fixes.isEmpty {
                    TurnFixRows(fixes: fixes)
                        .padding(.top, 2)
                }

                Button(action: toggle) {
                    HStack(spacing: 4) {
                        if loading { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "character.bubble") }
                        Text(showing ? "Hide" : "Explain in my language")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                if showing, let r = reasonNative {
                    Text(r)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func toggle() {
        if showing { showing = false; return }
        showing = true
        guard reasonNative == nil else { return }
        if let c = Translator.cachedExplanation(original: original, alternative: suggestion.alternative,
                                                to: nativeLanguage) {
            reasonNative = c
            return
        }
        loading = true
        Task {
            let t = await Translator.explainCorrection(original: original, alternative: suggestion.alternative,
                                                       to: nativeLanguage)
            reasonNative = t
            loading = false
            if t == nil { showing = false }
        }
    }
}

private struct PartialTurnView: View {
    let text: String

    /// The in-progress user line — same slot and fill as the finished turn it
    /// becomes, so nothing jumps sideways when the final transcript lands.
    var body: some View {
        DialogueLine(speaker: .user, name: chrome("You"), scale: .call) {
            // Dimmed by OPACITY, not `.secondary`: a caller's style replaces
            // the bubble's text colour, and on mono's solid ink bubble the
            // system secondary grey all but vanished into the fill.
            Text(text.isEmpty ? "Listening…" : text)
                .opacity(0.6)
                .italic(text.isEmpty)
        }
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            let barCount = 24
            let spacing: CGFloat = 4
            let barWidth = (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let position = Float(i) / Float(barCount - 1)
                    let center: Float = 0.5
                    let distance = abs(position - center) * 2          // 0 at center, 1 at edges
                    let envelope = max(0.15, 1 - distance * distance)  // bell-ish
                    let height = CGFloat(max(0.08, level * envelope)) * geo.size.height
                    Capsule()
                        .fill(Color.themeAccent)
                        .frame(width: barWidth, height: height)
                        .opacity(0.5 + Double(level) * 0.5)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.08), value: level)
        }
    }
}

// MARK: - Sheets

private struct TopicPickerSheet: View {
    @Binding var topic: String
    @Binding var topicBlurb: String
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [SuggestedTopic] = []
    @State private var loading = false
    @State private var error: String?
    @State private var customTopic: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if loading && suggestions.isEmpty {
                        HStack { ProgressView(); Text("Finding scenarios from your life…").foregroundStyle(.secondary) }
                    } else if suggestions.isEmpty {
                        Text(explain("Tap Refresh to generate scenarios."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(suggestions) { item in
                            Button {
                                topic = item.title
                                topicBlurb = item.blurb
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.title)
                                            .foregroundStyle(.primary)
                                            .font(.body)
                                        Spacer()
                                        if item.title == topic {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                    if !item.blurb.isEmpty {
                                        Text(item.blurb)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } header: {
                    Text("Suggested for you")
                } footer: {
                    if let e = error {
                        Text(e).foregroundStyle(.red)
                    } else {
                        Text(explain("Grounded in your profile — name, city, work, family, interests."))
                    }
                }

                Section("Your own") {
                    TextField("Type a topic", text: $customTopic)
                        .onSubmit { applyCustom() }
                    Button("Use this topic") { applyCustom() }
                        .disabled(customTopic.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("What to practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await regenerate() }
                    } label: {
                        if loading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(loading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Read from cache first; only hit Gemini when truly empty
                // (first time ever) or after an explicit Refresh tap.
                if suggestions.isEmpty {
                    let cached = appState.topicSuggestions
                    if !cached.isEmpty {
                        suggestions = cached
                    } else {
                        await regenerate()
                    }
                }
            }
        }
        .fittingDetents([.medium, .large])
    }

    private func applyCustom() {
        let trimmed = customTopic.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        topic = trimmed
        topicBlurb = ""
        dismiss()
    }

    private func regenerate() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let fresh = try await TopicEngine.suggest(
                persona: appState.persona,
                targetLanguage: appState.targetLanguage
            )
            suggestions = fresh
            appState.updateTopicSuggestions(fresh)
        } catch {
            self.error = explain("Couldn't fetch topics: \(error.localizedDescription)")
        }
    }
}

/// Inline recovery row shown under the last user turn when the reply failed.
/// Two personalities: a network/Gemini/TTS blip gets a Retry; running out of
/// credits gets the paywall — retrying a 402 can never succeed, so offering
/// only Retry there reads as "the app is broken".
struct RetryReplyRow: View {   // internal: DebugCaptureHarness renders it
    var outOfCredits: Bool = false
    let onRetry: () -> Void
    var onGetCredits: () -> Void = {}

    var body: some View {
        if outOfCredits {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.slash.fill")
                        .foregroundStyle(.secondary)
                    Text(explain("You're out of credits, so your future self can't reply."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button("See plans", action: onGetCredits)
                        .accentProminent()
                        .controlSize(.small)
                    Button("Retry", action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
                Text(explain("Couldn\'t get a response."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Post-talk wrap-up — now just the ONE session detail page
/// (`ConversationDetailView`) in post-talk mode, so what you see right after
/// a talk and what Practice opens later are the same page. The session was
/// saved before this sheet is presented; the page reads it back from the
/// store. The summary parameter only drives the sheet's item identity.
private struct SummarySheet: View {
    let summary: SessionSummary
    let sessionId: UUID
    let onDone: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var session: Session?

    var body: some View {
        NavigationStack {
            if let session {
                ConversationDetailView(
                    session: session,
                    postTalk: .init(onDone: onDone))
            } else {
                // Unreachable in practice: endSession saves before presenting.
                ProgressView()
            }
        }
        .onAppear {
            if var s = SessionStore.shared.load().first(where: { $0.id == sessionId }) {
                // Belt and braces: endSession saves a summary-less DRAFT before
                // the summary call. If the row read back is that draft, the
                // page would lose its score/words/expressions sections — the
                // summary we were handed is always the freshest.
                s.summary = summary
                session = s
            }
        }
    }
}

// MARK: - Identifiable conformance for sheet(item:)

extension SessionSummary: Identifiable {
    public var id: String { overallNote }
}


// MARK: - Bottom bar attachment

extension View {
    /// Attaches a bottom bar the way the system attaches the tab bar, so the
    /// content scrolling under it gets the SAME treatment the Talk home gets
    /// beneath its tabs: on iOS 26 a `safeAreaBar`, which is what makes the
    /// scroll view draw its soft scroll-edge effect under the bar (a plain
    /// `safeAreaInset` gets none). Earlier OSes get a hand-drawn wash of the
    /// page colour over the last few points above the bar.
    ///
    /// Two hand-drawn attempts preceded this (2026-09-03): an alpha mask on
    /// the feed, which SwiftUI's safe-area maths parked 50–100 pt above the
    /// pill, and a gradient in the bar's background, which was in the right
    /// place but was still ours and not the system's. Every conversation
    /// surface with a pinned bottom bar goes through here — the call's mic
    /// pill and the talk book's replay controls — so the dissolve is one
    /// implementation, and a bar attached this way must NOT carry a
    /// background of its own.
    @ViewBuilder
    func fadingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            // The wash rides under the system effect too (2026-11-17): on a
            // learner's iOS 26/27 phone the soft edge effect drew NOTHING,
            // and a tall call bar (caption, translation, hint, pill) sat
            // straight on top of the transcript, both unreadable. Where the
            // system effect works the wash is the same page colour it fades
            // to, so nothing changes there.
            self
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    bar().background(alignment: .top) { BottomBarWash() }
                }
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                bar().background(alignment: .top) { BottomBarWash() }
            }
        }
    }
}

/// Stand-in for the scroll-edge effect (and, since 2026-11-17, its backing
/// on iOS 26+ where the system effect can fail to draw): page colour under the
/// bar (and on down through the home indicator), with a gradient into
/// transparency reaching `fadeHeight` ABOVE the bar's top edge — the
/// negative padding is what lets it overhang, which pins the fade to the bar
/// by construction.
private struct BottomBarWash: View {
    static let fadeHeight: CGFloat = 36

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color(.systemBackground).opacity(0),
                                    Color(.systemBackground)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fadeHeight)
            Color(.systemBackground)
        }
        .padding(.top, -Self.fadeHeight)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}
