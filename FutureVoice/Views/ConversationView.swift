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
    @StateObject private var player = AudioPlayer()

    @State private var topic = ""
    @State private var topicBlurb = ""
    @State private var turns: [Turn] = []
    @State private var phase: Phase = .idle
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
    /// Viewport height of the feed, read from a background overlay so it
    /// costs no layout. Paired with the bottom sentinel's offset to answer
    /// "is the end of the transcript on screen".
    @State private var feedViewportHeight: CGFloat = 0
    /// The last failure was a 402 — the user is out of credits. Retry is
    /// pointless until they top up, so the recovery UI leads with the paywall.
    @State private var outOfCredits = false
    /// Wall-clock talk metering (4.5 cr/min via `talk-tick`). Started when
    /// the call seat opens, stopped on end/teardown; its 402 ends the call
    /// gracefully through the same out-of-credits alert as a turn failure.
    @StateObject private var meter = TalkMeter()
    @State private var showingPaywall = false
    /// Today's talk allowance is spent. Its own SHEET, not the error alert —
    /// a finished day is not something going wrong.
    @State private var dailyCapReached = false
    /// This account is on Light, so there IS somewhere to go when the pool
    /// runs out. Resolved at call start so the sheet's button is there the
    /// moment the wall lands. False on Plus: nothing left to sell, and the
    /// answer really is next month.
    @State private var canUpgradePlan = false
    /// The plan's own pool in whole minutes, from the account snapshot.
    /// Never hardcoded: the number is a plan setting on the server and a
    /// stale constant here would misstate what they bought.
    @State private var poolMinutes: Int?
    /// When the pool refills, for the sheet's "back on the 14th" line.
    @State private var renewalLabel = ""
    /// What the cap sheet was dismissed FOR. A sheet can't raise the next
    /// sheet while it is closing, so the choice is recorded and acted on in
    /// `onDismiss`.
    @State private var capChoice: CapChoice?
    /// Set while the exit is on its way to the Practice tab — staged only
    /// once the call screen is actually gone (see `close`).
    @State private var routeToPracticeOnClose = false
    /// Which tier the paywall should open on, when a caller named one.
    @State private var paywallTier: String?

    private enum CapChoice { case upgrade, review }
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
         resumeSession: Session? = nil,
         onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        self.initialOpener = initialOpener
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
    private static let vadShortSeconds: Double   = 0.8
    private static let vadDefaultSeconds: Double = 1.6
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
    @State private var sessionPauseFloor: Double = 0
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
    /// The most `stopAndSend` may wait for outstanding chunk transcripts
    /// before falling back to the on-device text: a bounded wait for the
    /// RIGHT text, priced against an instant reply to possibly-wrong text.
    /// `chunk_wait_ms` records what it actually costs per turn.
    ///
    /// 1.5 → 0.35 on 2026-08-21, measured on device: the tail chunk's round
    /// trip runs ~1.3 s PAST the turn's end, so at 1.5 s this wait sat in
    /// front of the Gemini call on every turn and still came back `late` on
    /// long utterances — 1.5 s of the ~6.3 s speech-end→voice gap, sometimes
    /// bought for nothing. At 0.35 s it only harvests chunks that are
    /// essentially done; anything slower falls back to the on-device guess
    /// for the REPLY while the transcript still gets corrected (chunk flush
    /// or whole-turn ASR, both post-voice). This deliberately re-accepts
    /// replies-from-ASR-guess on most turns: the learner's complaint was the
    /// wait, and the wait was this.
    ///
    /// 0.35 → 0.1 same day: at 0.35 every measured turn still came back
    /// `late` (chunk_wait_ms 385–393, all of it wasted) because the tail's
    /// RTT is ~1.3 s past turn end. 0.1 s is a harvest window, not a wait —
    /// it collects an assembly that is already done and gives up on the rest.
    private static let chunkAssemblyDeadlineSeconds: Double = 0.1

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
    @State private var userSpeechStartedAt: Date?
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

    /// Live lookup, not a copy — resolves through appState so edits to the
    /// person elsewhere are picked up, and resume restores it from the saved
    /// session's counterpartId with no extra plumbing.
    private var counterpart: Counterpart? {
        sessionCounterpartId.flatMap { id in appState.counterparts.first { $0.id == id } }
    }

    /// Who speaks the reply audio. A person-talk uses THAT person's preset
    /// voice — the partner is the stranger, not the fluent self. Everything
    /// else keeps the user's clone.
    private var activeVoiceId: String? {
        counterpart?.voicePresetId ?? appState.voiceCloneId
    }

    private let userId = ProfileStore.localUserId

    enum Phase: Equatable {
        case idle
        case listening      // mic open, partial STT streaming
        case thinking       // Gemini reply in flight
        case speaking       // ElevenLabs TTS playing
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
    private func isBillableMoment() -> Bool {
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
                if !goalItems.isEmpty {
                    TalkGoalChipsRow(items: goalItems, used: usedGoalKeys) { item in
                        goalDetail = item
                    }
                    Divider().opacity(0.15)
                }
                feed
                Divider().opacity(0.15)
                bottomBar
            }
            .background(Color(.systemBackground))
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
                    if phase == .listening { stopListeningDiscardingChunks() }
                    if phase == .listening || phase == .thinking { phase = .idle }
                    if meter.wallReason == .dailyCapReached {
                        dailyCapReached = true
                    } else {
                        outOfCredits = true
                        error = explain("Your talk time is used up. This call is saved — you can pick it up again any time.")
                    }
                }
                // Silence isn't billed — see `isBillableMoment`. Set before
                // start(): the ticker polls it from its first second.
                meter.isBillable = { isBillableMoment() }
                meter.start(sessionId: sessionId)
                lastActivityAt = Date()   // the call starts occupied
                // Put the call on the lock screen. Play/pause there are the
                // same two things the mic button does, so a call that outlives
                // the screen can still be hung up without unlocking.
                CallNowPlaying.begin(
                    title: callDisplayTitle,
                    onResume: { Task { if !phoneCallActive, !isTornDown { await handleMicTap() } } },
                    onPause: { Task { if phoneCallActive { await pauseCall() } } }
                )
                HapticEngine.phoneCallStarted()
                Analytics.capture("conversation_started", [
                    "origin": sessionOrigin.rawValue,
                    "resumed": isResuming
                ])
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
            .sheet(item: $goalDetail) { item in
                TalkGoalSheet(item: item, used: usedGoalKeys.contains(item.key))
                    .environmentObject(appState)
            }
            .sheet(item: summaryBinding) { s in
                SummarySheet(summary: s, sessionId: sessionId,
                             onDone: endAndClose)
                    .environmentObject(appState)
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                if outOfCredits {
                    Button("See plans") { error = nil; showingPaywall = true }
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
                    paywallTier = "unlimited"
                    showingPaywall = true
                case .review:  leaveForPractice()
                case nil:      break
                }
                capChoice = nil
            }) {
                DailyAllowanceSheet(
                    kind: .talk,
                    canUpgrade: canUpgradePlan,
                    allowance: poolMinutes,
                    renewsOn: renewalLabel,
                    onReview: { capChoice = .review },
                    onUpgrade: { capChoice = .upgrade })
            }
            .sheet(isPresented: $showingPaywall, onDismiss: { paywallTier = nil }) {
                // Reached here from an out-of-credits failure → no trial pitch.
                // Opened FROM the spent-day sheet it carries the tier that
                // sheet named, so "Go Unlimited" doesn't land on Daily.
                PaywallView(preselectTier: paywallTier)
            }
            .sheet(item: $feedbackContext, onDismiss: {
                if dismissAfterFeedback { dismissAfterFeedback = false; close() }
            }) { ctx in
                FeedbackSheet(context: ctx)
            }
            .sheet(isPresented: $askingMicChoice, onDismiss: resumeAfterMicChoice) {
                MicChoiceSheet { _ in }
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
            .task { goalItems = TalkGoalPicker.pick() }
            .task {
                let account = await AccountStatus.fetch()
                canUpgradePlan = account.isLightPlan
                poolMinutes = account.monthlyCapSeconds.map { $0 / 60 }
                renewalLabel = account.renewalLabel
            }
            // A real phone call, Siri, or an alarm takes the audio session
            // away and stops the engine WITHOUT going through `live.stop()`.
            // Nothing used to notice: the call stayed on screen, deaf, until
            // the learner tapped the mic twice.
            .onReceive(NotificationCenter.default.publisher(
                for: AVAudioSession.interruptionNotification)) { note in
                handleAudioInterruption(note)
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
            LevelHeaderTitle(title: topic.isEmpty ? "Let's talk" : topic,
                             level: appState.proficiency,
                             surface: .talk,
                             minutesLeft: meter.minutesRemaining.flatMap { $0 <= 10 ? $0 : nil })
                .environmentObject(appState)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                // A talk with unsaved turns doesn't just vanish on a stray ✕
                // tap — closing is gated behind an explicit choice between
                // saving (the End flow: summary + drills) and discarding.
                // Only the USER's turns count: if all that happened is the
                // fluent self's opener, there's nothing worth saving.
                if turns.contains(where: { $0.role == .user }) && !didSaveCurrentSession {
                    confirmingDiscard = true
                } else {
                    close()
                }
            } label: {
                Label("Close", systemImage: "xmark")
            }
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
                .disabled(phase != .idle)
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
                SummaryProgressView(progress: summaryProgress, facts: talkFacts)
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
                    ForEach(turns) { turn in
                        // No implicit morph between adjacent turns — each
                        // bubble fades in / out cleanly. Prevents the
                        // previous bubble's text from being visible inside
                        // the next one during insertion animation.
                        TurnView(turn: turn, nativeLanguage: appState.nativeLanguage)
                            .id(turn.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if phase == .listening {
                        // Separate id from ThinkingIndicator + explicit opacity
                        // transition so SwiftUI doesn't morph one view's text
                        // into another. The previous shared id caused the
                        // user's partial transcript to briefly bleed into the
                        // "Future self is thinking…" bubble during the swap.
                        PartialTurnView(text: live.transcript)
                            .id("partial-listening")
                            .transition(.opacity)
                    } else if phase == .thinking && (turns.last?.role == .user) {
                        ThinkingIndicator()
                            .id("partial-thinking")
                            .transition(.opacity)
                    } else if let fid = failedTurnId, turns.last?.id == fid {
                        RetryReplyRow(outOfCredits: outOfCredits,
                                      onRetry: retryReply,
                                      onGetCredits: { showingPaywall = true })
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
            }
            .coordinateSpace(name: Self.feedSpace)
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
            .onChange(of: turns.count) { _, _ in scroll(proxy) }
            .onChange(of: phase)       { _, _ in scroll(proxy) }
            .onChange(of: live.transcript) { _, _ in scroll(proxy) }
        }
    }

    private static let partialId = "partial-indicator"
    private static let bottomId  = "feed-bottom"
    private static let feedSpace = "conversation-feed"
    /// How near the end still counts as being at the end. A live partial
    /// bubble grows a line at a time, so an exact test would drop following
    /// on the learner's own next word.
    private static let tailSlack: CGFloat = 64

    private func scroll(_ proxy: ScrollViewProxy) {
        guard followTail else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomId, anchor: .bottom)
        }
    }

    // MARK: - Bottom bar (mic + level)

    private var bottomBar: some View {
        VStack(spacing: 10) {
            // The pixel grid lives INSIDE the pill, not across the screen.
            // The shader paints the whole surface theme-aware in a pure-blue
            // mosaic: airy white with blue pixels in light mode, near-black
            // with sky pixels in dark.
            Button { Task { await handleMicTap() } } label: {
                ZStack {
                    Futureself(mode: glowMode, level: voiceLevel)
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

            Text(micHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: 16)
                .animation(nil, value: phase)
        }
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        // No background — the mic floats above the feed and the tab bar gets
        // a clean gap below it, so users don't read mic + tabs as one chunk.
        .onChange(of: live.level) { _, new in
            guard phase == .listening else { return }
            voiceLevel = new
        }
        .onChange(of: player.level) { _, new in
            guard phase == .speaking else { return }
            voiceLevel = new
        }
        .onChange(of: phase) { _, _ in voiceLevel = 0 }
    }

    private var glowMode: Futureself.Mode {
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
        if phoneCallActive {
            switch phase {
            case .listening: return explain("Listening — tap to hang up")
            case .thinking:  return "Thinking"
            case .speaking:  return explain("Future self speaking — tap to hang up")
            case .idle:      return "Hang up"
            }
        }
        if isPausedForIdle { return explain("Call paused — tap to pick it back up") }
        return turns.isEmpty ? "Start phone-call mode" : "Resume phone-call mode"
    }

    /// With the pill glyph-free while on call, this line is the ONE place
    /// that says tapping hangs up — every in-call state must name it.
    private var micHint: String {
        if phoneCallActive {
            switch phase {
            case .listening: return explain("Listening · pause to send · tap to stop")
            case .thinking:  return "Thinking… · tap to stop"
            case .speaking:  return "Speaking… · tap to stop"
            case .idle:      return explain("On call · tap to stop")
            }
        }
        // A call that put itself down says so. Without this the screen looks
        // identical to one the learner stopped on purpose, and the only clue
        // that three minutes passed is that nothing is happening.
        if isPausedForIdle { return explain("Paused — tap to pick it back up") }
        return turns.isEmpty ? "Tap to start a phone-call" : "Tap to continue"
    }

    // MARK: - Bindings

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
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
    /// Coarse on purpose: nothing here needs to be precise to the second. It
    /// also bounds the overshoot — the pause lands within a tick of the bar.
    private static let idleWatchTickSeconds: Double = 5

    /// True when the watchdog was the one that stopped the call — the only
    /// difference it makes is the hint under the pill, so a learner coming
    /// back to a quiet screen reads "paused" instead of wondering what broke.
    @State private var isPausedForIdle = false
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
                // The same predicate the meter bills on — so the call pauses
                // on exactly the silence it charges nothing for.
                if isBillableMoment() { lastActivityAt = Date(); continue }
                guard Date().timeIntervalSince(lastActivityAt) >= Self.idlePauseSeconds else { continue }
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

    /// What the lock screen calls this call. The same words the toolbar shows.
    private var callDisplayTitle: String {
        topic.isEmpty ? explain("Let's talk") : topic
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
    /// turn still says the same words. Gemini calls are free (rate-capped),
    /// so a discarded speculation costs the learner nothing.
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
        userSpeechStartedAt = nil
    }

    /// Encode one cut piece and put its transcription in flight. Fully
    /// background — nothing awaits it until `adoptChunkTranscript`'s bounded
    /// wait at turn end.
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
                let listened = userSpeechStartedAt.map { Date().timeIntervalSince($0) } ?? 0
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
                ]
                turnEndedSpeakingAt = Date()
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
        phase = .thinking
        // The opener plays before any mic session exists — arm the call's
        // audio session or the greeting streams into `.soloAmbient` (muted by
        // the ring switch on most phones). Detached: `setActive` can block
        // for hundreds of ms, and inline it lands exactly on the open-morph
        // frames. It runs while the opener text is fetched; awaited below
        // before anything plays.
        let audioSessionReady = Task.detached(priority: .userInitiated) {
            AudioSessionRouting.warmUpForConversation()
        }
        do {
            let opener: String
            if let initialOpener, !initialOpener.isEmpty {
                // Answered the daily call: the voicemail already said its
                // piece. Anything generated here would talk over a question
                // the learner is mid-way through answering.
                opener = initialOpener
            } else if topicIsNews, let fromPool = openNewsConversation() {
                opener = fromPool
            } else if isFirstMeeting {
                // They've never spoken. A rotating "good to hear you" is a
                // greeting between people who know each other — this call
                // opens by admitting it's the first one and asking who they
                // are (the FIRST CALL block runs the rest of it). Bundled, so
                // the first greeting of all never waits on Gemini, and the
                // pool is written in the background for later sessions.
                opener = FreeTalkOpeners.introOpener(language: appState.targetLanguage)
                if !FreeTalkOpeners.shared.hasPool(
                    language: appState.targetLanguage,
                    personaName: appState.persona?.displayName) {
                    let language = appState.targetLanguage
                    let personaName = appState.persona?.displayName
                    let proficiency = appState.proficiency
                    Task.detached(priority: .utility) {
                        _ = try? await FreeTalkOpeners.shared.generatePool(
                            language: language, personaName: personaName,
                            proficiency: proficiency)
                    }
                }
            } else if topic.isEmpty, counterpart == nil,
                      let canned = FreeTalkOpeners.shared.next(
                          language: appState.targetLanguage,
                          personaName: appState.persona?.displayName) {
                // Free talk: greetings are interchangeable, so rotate a stored
                // pool instead of paying a Gemini call per session — and since
                // the texts repeat verbatim, the TTS content cache makes the
                // voice free after each line's first play.
                opener = canned
            } else if topic.isEmpty, counterpart == nil {
                // First free talk (or language/persona changed — no pool
                // yet): the bundled line opens the call NOW instead of
                // holding the greeting hostage to a live Gemini call; the
                // pool is written in the background for every later session.
                opener = FreeTalkOpeners.fallbackOpener(language: appState.targetLanguage)
                let language = appState.targetLanguage
                let personaName = appState.persona?.displayName
                let proficiency = appState.proficiency
                Task.detached(priority: .utility) {
                    _ = try? await FreeTalkOpeners.shared.generatePool(
                        language: language, personaName: personaName,
                        proficiency: proficiency)
                }
            } else if let sid = sessionScenarioId,
                      let stored = appState.nextScenarioOpener(for: sid) {
                // Scenario talk with a stored opener pool: rotate — instant
                // start, no Gemini call, and the line's TTS is already in the
                // phrase cache after its first play.
                opener = stored
            } else {
                opener = try await generateOpener()
            }
            // The screen may have closed while the opener was being fetched.
            guard !isTornDown else { return }
            // Session must be armed before playback OR the mic fallback below.
            await audioSessionReady.value
            // Speak the opener in the active voice — a call starts with the
            // other side TALKING, not a line to read. Repeated openers for
            // the same phrasing hit the content cache, and the idempotency
            // key keeps a re-open from billing ElevenLabs twice.
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
            if error.isDailyCapReached { dailyCapReached = true; return }
            outOfCredits = error.isOutOfCredits
            self.error = error.localizedDescription
        }
    }

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
            userSpeechStartedAt = Date()
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
        let elapsedMs = Int((Date().timeIntervalSince(userSpeechStartedAt ?? Date())) * 1000)
        userSpeechStartedAt = nil

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
        didSaveCurrentSession = false
        creditGoalChips(turnId: userTurn.id)

        // Hold every rewrite of this bubble from HERE, not from inside
        // `requestReply`. The chunk wait below and the recognizer's rescored
        // pass both land in this window, and while nothing was armed they
        // painted their corrections before the reply had even been asked for.
        deferredTurnWork = DeferredTurnWork(turnId: turnId)
        if let chunk = chunkState, chunk.nextIndex > 0 {
            await adoptChunkTranscript(chunk, turnId: turnId, guess: finalText)
        }
        await requestReply(forUserTurn: userTurn.id)
    }

    /// Bounded wait for the in-flight chunk transcripts; when EVERY piece
    /// resolved, the assembled audio-grounded text replaces the on-device
    /// guess BEFORE the reply is generated — the whole point of the pipeline.
    /// Any gap (a failed call, a piece still in flight at the deadline) falls
    /// back to today's behavior: on-device text now, whole-turn correction
    /// later.
    private func adoptChunkTranscript(_ chunk: ChunkASRState, turnId: UUID,
                                      guess: String) async {
        let started = Date()
        let deadline = started.addingTimeInterval(Self.chunkAssemblyDeadlineSeconds)
        while !chunk.isSettled, !chunk.hasFailure, Date() < deadline, !isTornDown {
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        let waitedMs = Int(Date().timeIntervalSince(started) * 1000)
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
                "status": error.elevenLabsStatus ?? "",
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
                        nativeLanguage: appState.nativeLanguage),
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
            let result = try await ElevenLabsClient.shared.synthesizeStreaming(
                voiceId: voiceId, text: prefix,
                modelId: ElevenLabsClient.conversationModelId,
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
                "status": error.elevenLabsStatus ?? "",
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
            let result = try await ElevenLabsClient.shared.synthesizeStreaming(
                voiceId: voiceId, text: rest,
                modelId: ElevenLabsClient.conversationModelId,
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
    ///   • it is a SECOND ElevenLabs render of audio we already have, which is
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
        // Content-addressed cache hit avoids re-billing ElevenLabs for repeated
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
            let result = try await ElevenLabsClient.shared.synthesizeStreaming(
                voiceId: voiceId, text: text,
                modelId: ElevenLabsClient.conversationModelId,
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
                "status": error.elevenLabsStatus ?? "",
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

        let (newAudio, newTimings) = try await ElevenLabsClient.shared
            .synthesizeWithTimestamps(voiceId: voiceId, text: text,
                                      modelId: ElevenLabsClient.conversationModelId,
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

    private func endSession() async {
        guard !turns.isEmpty else { return }
        phoneCallActive = false
        // The call is over — summary generation isn't talk time, and the lock
        // screen must stop showing a call that has hung up.
        meter.stop()
        CallNowPlaying.end()
        cancelSilenceTimer()
        cancelIdleWatch()
        // If a call is still live, stop the mic/playback so the overlay isn't
        // fighting an open recording while the summary generates.
        if phase == .listening {
            stopListeningDiscardingChunks()
        }
        if phase == .speaking { player.stop() }
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
        // Persist the raw conversation FIRST. The summary call below can fail
        // (network, credits, malformed JSON) and turns live only in memory —
        // without this draft save a failed summary used to lose the whole
        // session. `SessionSummarizer` overwrites this row (same id) once the
        // analysis lands; until then the talk sits in Practice with a
        // "generate the review material" button instead of dead-ending here.
        // The draft save below overwrites a resumed talk's previous analysis
        // (summary: nil is what marks the row "needs analysis") — capture it
        // first so the summarizer can MERGE with it instead of losing it.
        let priorSummary = SessionStore.shared.load()
            .first { $0.id == sessionId }?.summary
        let draft = Session(
            id: sessionId,
            userId: userId,
            targetLanguage: appState.targetLanguage,
            mode: .conversation,
            topic: topic.isEmpty ? nil : topic,
            startedAt: sessionStartedAt,
            endedAt: Date(),
            turns: turns,
            summary: nil,
            origin: sessionOrigin,
            originScenarioId: sessionScenarioId,
            counterpartId: sessionCounterpartId
        )
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
                + explain("Your conversation is saved. Open it under Practice to generate its review material again.")
            phase = .idle
        }
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
        if let onClose { onClose() } else { dismiss() }
        // Staged AFTER the screen is gone, never before: the Practice tab
        // lives UNDER this overlay, and a route consumed while the call is
        // still fading would present the review deck on top of it.
        if routeToPracticeOnClose {
            routeToPracticeOnClose = false
            appState.pendingPracticeRoute = .studying
        }
    }

    /// "Go to Practice" from the spent-day sheet. The call can't continue
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
        cancelSilenceTimer()
        cancelIdleWatch()
        // The transcription runs on its own clock and can outlive the screen —
        // it must not keep uploading (or write into `turns`) after the call
        // has been hung up.
        transcribeTask?.cancel()
        transcribeTask = nil
        turnAudioEncode?.task.cancel()
        splitSpeech = nil
        _ = live.stop()
        discardChunkPipeline()
        if let stale = live.lastChunkRecordingURL {
            try? FileManager.default.removeItem(at: stale)
        }
        player.stop()
        phase = .idle
    }

    private func startNewSession() {
        failedTurnId = nil
        summary = nil
        sessionId = UUID()
        sessionStartedAt = Date()
        turns = []
        didSaveCurrentSession = false
        phase = .idle
        if !topic.isEmpty {
            phoneCallActive = true   // stay in phone-call mode for continuity
            meter.start(sessionId: sessionId)   // fresh session, fresh tick keys
            // endSession took the last call off the lock screen; this is a new
            // one and has to put itself back.
            CallNowPlaying.begin(
                title: callDisplayTitle,
                onResume: { Task { if !phoneCallActive, !isTornDown { await handleMicTap() } } },
                onPause: { Task { if phoneCallActive { await pauseCall() } } }
            )
            Task { await openConversation() }
        }
    }

    /// Done from the summary sheet → leave the talk seat entirely, back to the
    /// Talk home. Summary is already saved to History.
    private func endAndClose() {
        summary = nil
        phoneCallActive = false
        cancelSilenceTimer()
        // First-ever finished conversation → ask for feedback before leaving;
        // the sheet's onDismiss completes the exit.
        if FeedbackPrompt.shouldShow(.firstTalk) {
            FeedbackPrompt.markShown(.firstTalk)
            dismissAfterFeedback = true
            feedbackContext = .firstTalk
        } else {
            close()
        }
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
        appState.persona?.metAt == nil && topic.isEmpty && counterpart == nil
    }

    private func systemPrompt() -> String {
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
            newsFacts: newsFacts,
            firstMeeting: isFirstMeeting
        )
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

    @State private var translation: String?
    @State private var showing = false
    @State private var loading = false

    /// Speaker separation (side, fill, name label) comes from `DialogueLine`
    /// — the same component Watch and the conversation archive use — so the
    /// three surfaces stay in sync when the style changes.
    private var speaker: DialogueSpeaker { turn.role == .user ? .user : .other }

    var body: some View {
        DialogueLine(speaker: speaker,
                     name: turn.role == .user ? "You" : "Future self",
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
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text(turn.transcript)
                    .animation(.easeInOut(duration: 0.2), value: turn.transcript)
            }
        } accessory: {
            // Nothing to translate or correct until there is a line.
            if turn.transcript.isEmpty {
                EmptyView()
            } else {
            VStack(alignment: speaker.alignment, spacing: 6) {
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
                if turn.role == .user, let suggestion = turn.suggestion {
                    SuggestionChip(suggestion: suggestion, original: turn.transcript,
                                   nativeLanguage: nativeLanguage)
                }
            }
            }
        }
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
        if let c = Translator.cached(turn.transcript, to: nativeLanguage) {
            translation = c
            return
        }
        loading = true
        Task {
            let t = await Translator.translate(turn.transcript, to: nativeLanguage)
            translation = t
            loading = false
            if t == nil { showing = false }
        }
    }
}

private struct SuggestionChip: View {
    let suggestion: TurnSuggestion
    let original: String
    let nativeLanguage: String

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
                Text(highlightedCorrection(suggestion.alternative, original: original, baseFont: .subheadline))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
        DialogueLine(speaker: .user, name: "You", scale: .call) {
            Text(text.isEmpty ? "Listening…" : text)
                .foregroundStyle(.secondary)
                .italic(text.isEmpty)
        }
    }
}

private struct ThinkingIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("Future self is thinking…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .fill(Color.accentColor)
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
        .presentationDetents([.medium, .large])
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
            self.error = "Couldn't fetch topics: \(error.localizedDescription)"
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
                        .buttonStyle(.borderedProminent)
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
