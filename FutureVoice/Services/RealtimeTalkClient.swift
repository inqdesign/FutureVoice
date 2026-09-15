import AVFoundation
import Foundation

/// Client for the realtime Talk gateway (Cloudflare Worker + Durable Object,
/// `gateway/` in this repo). ONE WebSocket per call: mic PCM goes up
/// continuously, reply PCM comes down, and every turn decision — when the
/// learner stopped talking, when they spoke over the reply — is made
/// server-side.
///
/// This is deliberately NOT a variant of `ConversationView`'s pipeline. That
/// one is a per-turn HTTP machine (VAD tiers, speculative replies, chunked
/// ASR, deferred work) whose whole complexity exists to shave a wait this
/// path doesn't have. Measured 2026-08-31: speech-end → cloned voice 2.1–3.0 s
/// here against ~6.5 s p50 there. Nothing here writes to `SessionStore`,
/// `DrillStore` or the meter yet — it is the latency spike, behind a DEBUG
/// door, and the learning loop is Phase 3.
///
/// ## The one thing that makes this feel like a phone call
///
/// Mic capture and reply playback share a SINGLE `AVAudioEngine` whose input
/// node has voice processing (VPIO) on. That gives the echo canceller a real
/// render reference, so the fluent self's voice coming out of the speaker is
/// subtracted from what the mic hears. Without it, playing on the speaker
/// makes the reply interrupt ITSELF: the gateway hears the voice, calls it a
/// barge-in, and cuts the line mid-sentence (exactly what the Mac test
/// harness needs earphones to avoid).
///
/// `LiveTranscriber` carries a warning against attaching a source to the
/// mixer to feed VPIO's output bus — it read the output format before
/// `engine.start()`, when a Bluetooth link is still on A2DP, and the format
/// went stale the moment opening the mic flipped it to HFP. That warning is
/// about a SILENT source added for no benefit; here the player is the point.
/// The staleness is handled by building the graph only after the session is
/// active (so the route has already settled) and by using the engine's own
/// output format for the connection rather than a hardcoded one.
@MainActor
final class RealtimeTalkClient: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case connecting
        /// Mic is streaming; nobody is speaking.
        case listening
        /// The learner is audibly mid-utterance (interim transcript moving).
        case hearing
        /// Their turn is committed and the reply is being written — the
        /// only silence in the call, and the one the thinking indicator
        /// belongs to.
        case thinkingReply
        /// The fluent self is speaking.
        case speaking
        case failed(String)
    }

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let isUser: Bool
        var text: String
    }

    @Published private(set) var state: State = .idle {
        didSet { if oldValue != state { Self.step("state \(oldValue) → \(state)") } }
    }
    /// Live transcript of the utterance in progress (empty between turns).
    @Published private(set) var partial = ""
    @Published private(set) var lines: [Line] = []
    /// Speech-end → first reply audio, in ms, for the last completed turn.
    /// The number this whole path exists to move.
    @Published private(set) var lastLatencyMs: Int?
    /// Server-side speech seconds so far (what Phase 3 will bill).
    @Published private(set) var speechSeconds = 0
    /// Bytes of mic audio actually put on the wire. The one number that
    /// separates "the mic is dead" from "the gateway isn't answering" — a
    /// silent call with this climbing is a server problem, and with this at
    /// zero it never left the phone.
    @Published private(set) var micBytesSent = 0
    /// 0…1 level for the mic pill, from whichever side is currently audible.
    @Published private(set) var level: Float = 0
    /// Set when the gateway ends the call on a spent allowance —
    /// "insufficient_credits" or "daily_cap_reached". The view reads it from
    /// the failed state to raise the right wall instead of an error alert.
    @Published private(set) var wallCode: String?
    /// Why the last call failed, as a short code — "socket", "reply",
    /// "route", "mic_silent", or the gateway's own code. Every failure goes
    /// through `fail(_:_:)`, which also writes it to telemetry: until
    /// 2026-09-12 a call on this path could end for any of nine reasons and
    /// not one of them left a record anywhere.
    @Published private(set) var lastFailureCode: String?
    /// How many non-fatal `warning` events the gateway sent this call.
    private(set) var warningsThisCall = 0

    // MARK: Turn hand-off
    //
    // The call screen owns the session, the transcript and everything the
    // learning loop is built on; this client only produces turns for it.
    // Audio comes with them because Practice needs it: the learner's own take
    // for listen-back, the fluent self's line for replay and shadowing.

    /// A committed learner turn: text, their own audio, duration in ms.
    var onUserTurn: ((String, URL?, Int) -> Void)?
    /// The fluent self has STARTED a line — its bubble belongs on screen
    /// now, empty, because the voice is about to be heard. Carries the
    /// context id so later events find the same bubble.
    var onReplyBegan: ((String) -> Void)?
    /// More of that line was written; the bubble grows as it is spoken.
    var onReplyDelta: ((String, String) -> Void)?
    /// The line is over (finished or talked over): its audio and duration.
    var onReplyFinished: ((String, String, URL?, Int) -> Void)?

    /// Mic PCM since the last committed turn, at the MIC'S OWN rate — the
    /// 16 kHz uplink is transport quality, and saving it was why a learner's
    /// replayed voice sounded so much worse than the old path's native
    /// capture (reported 2026-09-01). Capped at ~2 min so a monologue cannot
    /// grow it without bound.
    private var userPCM = Data()
    private var userPCMRate: Double = 48_000
    private var maxUserPCMBytes: Int { Int(userPCMRate) * 2 * 60 * 2 }
    /// Reply PCM for the line currently playing, at `replySampleRate`.
    private var replyPCM = Data()
    /// Text of the line playing, so the turn is handed over complete when its
    /// audio ends.
    private var replyText = ""
    /// The reply context on screen right now, shared by began/delta/finished.
    private var replyContext: String?

    // MARK: Echo gate
    //
    // The fluent self plays out of the SPEAKER while the mic is open, so its
    // own voice comes back in. iOS voice processing cancels most of it, but
    // not all — enough survived to be transcribed as the learner's turn and
    // answered ("did you say box?", reported 2026-09-01). The call was talking
    // to itself.
    //
    // So while a line is playing, the mic is measured against the echo it is
    // hearing and only audio clearly LOUDER than that goes upstream. The
    // learner's mouth is centimetres from the mic and the echo is a speaker
    // bouncing off a room; that gap is what separates them. Everything below
    // the bar is forwarded as silence rather than dropped, so the
    // transcriber's stream stays continuous.
    private var echoFloor: Float = 0
    private var echoLearnedFrames = 0
    /// ~0.4 s of playback measured before the gate starts judging: at the top
    /// of a line the learner has not started talking yet, so whatever the mic
    /// hears then IS the echo.
    private static let echoLearnFrames = 4
    /// How much louder than the echo a voice must be to count as the learner
    /// speaking. ~5 dB — enough to reject a cancelled speaker, low enough that
    /// talking over the fluent self still works.
    private static let echoMargin: Float = 1.8
    /// The echo does not stop with the audio: the room's tail and the last
    /// buffers keep arriving. Hold the gate briefly past the end of a line.
    private var echoHoldUntil = Date.distantPast

    /// Where the gateway lives. Overridable at runtime so a device on the same
    /// Wi-Fi can be pointed at `wrangler dev` (Me → Realtime call → long-press
    /// isn't a thing; set `futurevoice.realtimeGatewayURL` in defaults).
    static var gatewayURL: URL {
        let stored = UserDefaults.standard.string(forKey: "futurevoice.realtimeGatewayURL")
        let raw = (stored?.isEmpty == false ? stored! : Self.defaultGateway)
        return URL(string: raw) ?? URL(string: Self.defaultGateway)!
    }
    private static let defaultGateway =
        "wss://futurevoice-gateway.futurevoice-gateway.workers.dev/call"

    // MARK: Transport

    private var socket: URLSessionWebSocketTask?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        // A call is idle-quiet only between turns; the mic keeps the socket
        // busy, so this only matters for a wedged connection.
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // MARK: Audio

    // `var`, not `let`: every `startAudio` builds a FRESH graph. Reusing the
    // engine across a route change crashed the app — plugging earphones in
    // mid-call flips the link A2DP→HFP, and `installTap` on the old engine's
    // half-reconfigured voice-processing unit raises an ObjC exception no
    // Swift catch can reach (crash 2026-09-01, CreateRecordingTap). This is
    // the same per-start-fresh-engine rule LiveTranscriber has always lived
    // by, learned here the same way.
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()

    /// What the mic tap needs, readable from the AUDIO THREAD without hopping
    /// to the main actor — the hop is exactly what made the first version
    /// read recycled buffers. Written on the main actor at start/stop, read
    /// on the audio thread per buffer, so every access takes the lock.
    private final class MicUplink: @unchecked Sendable {
        private let lock = NSLock()
        private var converter: AVAudioConverter?
        private var format: AVAudioFormat?
        private var socket: URLSessionWebSocketTask?

        func set(converter: AVAudioConverter?, format: AVAudioFormat?,
                 socket: URLSessionWebSocketTask?) {
            lock.lock(); defer { lock.unlock() }
            self.converter = converter
            self.format = format
            self.socket = socket
        }

        func current() -> (AVAudioConverter, AVAudioFormat, URLSessionWebSocketTask)? {
            lock.lock(); defer { lock.unlock() }
            guard let converter, let format, let socket else { return nil }
            return (converter, format, socket)
        }

        // --- echo gate, read per mic buffer on the audio thread ---
        private var gateActive = false
        private var gateFloor: Float = 0
        private var gateLearned = 0
        /// Playback has actually reached the player for this line. Until
        /// then nothing is learned: `audio_start` arrives a TTS round trip
        /// before the first audible sample, and a floor measured in that
        /// gap is the ROOM, not the echo — so every line's echo cleared the
        /// margin, and only a converged echo canceller hid that.
        private var gatePlaying = false
        /// The whole line is forwarded as silence — no learning, no judging.
        private var gateHalfDuplex = false

        /// Open or close the gate. Called when a line starts and ends playing.
        func setEchoGate(active: Bool, halfDuplex: Bool = false) {
            lock.lock(); defer { lock.unlock() }
            if active && !gateActive {
                gateFloor = 0
                gateLearned = 0
                gatePlaying = false
                gateHalfDuplex = halfDuplex
            }
            if !active { gateHalfDuplex = false }
            gateActive = active
        }

        /// The first reply buffer of the line was handed to the player.
        func markPlaybackStarted() {
            lock.lock(); defer { lock.unlock() }
            gatePlaying = true
        }

        func echoGate() -> (active: Bool, playing: Bool, halfDuplex: Bool,
                            floor: Float, learnedFrames: Int) {
            lock.lock(); defer { lock.unlock() }
            return (gateActive, gatePlaying, gateHalfDuplex, gateFloor, gateLearned)
        }

        /// Fold one buffer of echo into the floor. Called for the learn
        /// window AND for every later buffer judged to be echo, so the floor
        /// follows the line's loudest echo instead of its first 0.4 s.
        func learnEcho(rms: Float, counts: Bool) {
            lock.lock(); defer { lock.unlock() }
            gateFloor = max(gateFloor, rms)
            if counts { gateLearned += 1 }
        }
    }
    private let mic = MicUplink()
    private var converter: AVAudioConverter?
    private var uplinkFormat: AVAudioFormat?
    private var playbackFormat: AVAudioFormat?
    private var engineRunning = false
    /// Live for the length of the call — see `observeRouteChanges`.
    private var routeObserver: NSObjectProtocol?
    private var isRebuildingAudio = false
    /// A device event arrived mid-rebuild — run one more pass when done.
    private var routeRebuildPending = false
    /// Output port the running engine was built on — the reference that lets
    /// `.routeConfigurationChange`/`.override` events trigger a rebuild only
    /// when the route actually moved (see observeRouteChanges).
    private var builtOutput = ""
    private var routePollTask: Task<Void, Never>?
    private var pollRebuildStrikes = 0
    private var pollMismatchTicks = 0
    /// Tap buffers since the CURRENT engine build — written on the audio
    /// thread, read by the per-build tap watchdog. The original mic watchdog
    /// guards only the call's FIRST build; a REBUILD can also come up with a
    /// tap that never fires (observed 2026-09-01: poll rebuild onto HFP,
    /// engine running, tap installed at 24 kHz, zero buffers — the call
    /// simply froze), and by then `micBytesSent` is already nonzero, so only
    /// a per-build counter can see it.
    nonisolated(unsafe) private static var buffersSinceBuild = 0
    private var buildEpoch = 0
    private var tapWatchdogStrikes = 0
    private var lastAudioBuildAt = Date.distantPast
    /// Reply PCM is 16-bit LE at whatever rate `audio_start` announced.
    private var replySampleRate: Double = 22050
    /// Loudness, borrowed wholesale from `AudioPlayer`'s streaming path.
    /// Without it this screen plays RAW PCM at whatever level ElevenLabs
    /// happened to render, into a `.playAndRecord` session with voice
    /// processing on — which is the quietest output profile the app has.
    /// Talk sounds right because `AudioPlayer` levels every stream; this one
    /// did not, and the fluent self came out far too quiet (device, 2026-09-01).
    private var streamLevel = AudioLoudness.StreamingLevelEstimator()
    /// Compensation for the route the call is actually on (HFP/A2DP/speaker).
    private var routeBoost: Float = 1
    /// The learner's own call-volume preference, the same one Talk honours.
    private var userGain: Float = 1
    /// Current smoothed gain, seeded per voice like the buffered path.
    private var streamGain: Float = 1

    /// Buffers scheduled but not yet played — non-zero means audio is pending,
    /// which is how playback end is noticed without a completion per chunk.
    private var pendingBuffers = 0
    /// Reply buffers that have finished PLAYING on this call — see the
    /// completion handler in `playReplyChunk`.
    private var playedBuffers = 0
    /// Reply audio bytes the gateway has sent on this call. Together with
    /// `playedBuffers` this is "a line is in the air": one says the voice is
    /// arriving, the other that it is being heard, and neither is the queue
    /// depth, which a wedged engine keeps climbing forever.
    private var replyBytesReceived = 0
    /// The server said the line is complete; the moment the local queue
    /// drains after this is when the learner's turn actually begins.
    private var serverAudioEnded = false
    /// Lines the fluent self has started on THIS call — the first one on the
    /// speaker is half-duplex (see `audio_start`).
    private var linesStarted = 0
    /// The greeting, already synthesized and sitting in `PhraseAudioStore`,
    /// decoded and waiting for `ready`. See `playLocalOpener`.
    private var localOpener: (text: String, buffer: AVAudioPCMBuffer, rate: Double)?

    private var isTornDown = false

    // MARK: - Lifecycle

    /// Open the call: audio session, engine, socket, `start` handshake.
    ///
    /// `fallbackVoiceId` is used if the gateway refuses the first voice. That
    /// happens for a real reason: the clone id on THIS install may belong to a
    /// user id this session isn't (a debug build that just minted an anonymous
    /// session, a re-install), and the gateway enforces voice ownership the
    /// same way the TTS edge function does. Retrying on a preset keeps the
    /// spike testable instead of dead-ending on a deepfake guard doing its job.
    func connect(voiceId: String, language: String, system: String,
                 opener: String? = nil,
                 openerAudio: URL? = nil,
                 history: [(role: String, text: String)] = [],
                 fallbackVoiceId: String? = nil) async {
        // A failed call is re-enterable (the view's Try again); a live one is
        // not — reconnecting under it would leave two sockets and two mics.
        switch state {
        case .idle, .failed: break
        default: return
        }
        isTornDown = false
        wallCode = nil
        lastFailureCode = nil
        warningsThisCall = 0
        state = .connecting
        linesStarted = 0
        localOpener = nil
        playedBuffers = 0
        replyBytesReceived = 0
        tapWatchdogStrikes = 0
        pendingRetry = fallbackVoiceId.map {
            Retry(voiceId: $0, language: language, system: system,
                  opener: opener, history: history)
        }
        do {
            // ASK FOR THE MIC FIRST. Without permission iOS does not fail
            // here — the input node still reports a format and the tap still
            // fires, delivering SILENCE. The call then looks perfectly
            // healthy and simply never hears anything, which is exactly how
            // it presented on the first device test. A debug build has its
            // own bundle id and therefore its own permission, so "Talk
            // already works on this phone" proves nothing.
            Self.step("connect: asking for mic")
            guard await Self.requestMicPermission() else {
                fail("mic_permission", "Microphone access is off for this app. Settings → nawana → Microphone.")
                return
            }
            Self.step("connect: mic granted")
            let token = try await Self.accessToken()
            Self.step("connect: got token")
            do { try startAudio() } catch {
                // Launch-time races (another component touching the session
                // mid-build) can stop the engine under the first attempt —
                // one settle-and-retry saves the call instead of failing it.
                Self.step("connect: startAudio threw (\(error)) — retrying once")
                stopAudio()
                try? await Task.sleep(nanoseconds: 600_000_000)
                try startAudio()
            }
            Self.step("connect: audio up")
            // The greeting the launcher already synthesized (see
            // `FreeTalkOpeners.warmAudio`) is on disk in the learner's own
            // voice. Play it from there and the gateway is never asked for
            // it: the line starts when `ready` lands instead of a further
            // ElevenLabs round trip later, and the pool warm-up finally pays
            // for itself on this path too. The text still goes up as HISTORY,
            // so the model knows what it just said.
            var startOpener = opener
            var startHistory = history
            if let openerAudio, let opener, !opener.isEmpty,
               let decoded = Self.decodeOpener(openerAudio) {
                localOpener = (opener, decoded.buffer, decoded.rate)
                startHistory.append((role: "model", text: opener))
                startOpener = nil
                Self.step("opener: playing the cached take locally")
            }
            try openSocket(token: token, voiceId: voiceId,
                           language: language, system: system,
                           opener: startOpener, history: startHistory)
            Self.step("connect: socket opened")
            // CONCURRENTLY with the gateway's own start-up, never before it.
            // The gateway spends 2.7–3.6 s on `start` → `ready` (verify, voice
            // ownership, allowance pre-flight, the transcriber's handshake)
            // and the opener cannot be spoken before that — so the mic's own
            // pre-flight is free as long as it runs inside that window, and
            // pure added wait if it runs in front of it. Measured 2026-09-13:
            // in front, tap → first word was 8.0 s; inside, the same repair
            // costs nothing.
            Task { await self.waitForLiveMic() }
            startMicWatchdog()
        } catch {
            Self.step("connect FAILED: \(error)")
            fail("audio_start", error.localizedDescription)
            teardown()
        }
    }

    /// Mic only — this path never uses on-device speech recognition (the
    /// gateway transcribes), so it must not ask for it.
    private static func requestMicPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            if AVAudioApplication.shared.recordPermission == .granted { return true }
            return await AVAudioApplication.requestRecordPermission()
        }
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission == .granted { return true }
        return await withCheckedContinuation { cont in
            session.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    /// Don't ask the gateway to speak until the microphone is proven alive.
    ///
    /// Measured on device 2026-09-13, earphones connecting as the call opened:
    /// the audio stack was built three times in the first five seconds, and
    /// the build the OPENER landed on had a tap that never fired. The only
    /// cure for that build was another rebuild — which happened, 2.1 s into
    /// the greeting, and took the greeting with it (a reply chunk arriving
    /// while the engine is down is dropped from playback). The learner heard
    /// nothing at all, twice in a row.
    ///
    /// A rebuild HERE costs silence nobody is listening to: it runs inside the
    /// gateway's own 2.7–3.6 s start-up, before the opener can be spoken. It
    /// is deliberately started and NOT awaited for that reason — in front of
    /// the socket it was 2.7 s of pure wait on the first word (measured
    /// 2026-09-13, tap → voice 8.0 s). Bounded at roughly 2.5 s; past that
    /// the call runs on and the watchdogs take over, because a call that
    /// never starts is worse than one whose first line is deaf.
    private func waitForLiveMic() async {
        for attempt in 1...2 {
            for _ in 0..<12 {
                if Self.buffersSinceBuild > 0 {
                    if attempt > 1 { Self.step("pre-flight: mic alive after rebuild") }
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
                if isTornDown { return }
            }
            guard attempt == 1 else { break }
            // A line is already in the air — the gateway was faster than this
            // repair. Rebuilding now would drop the greeting's audio, which is
            // the very thing this exists to protect; hand it to the tap
            // watchdog, which waits the line out and then rebuilds in silence.
            guard state != .speaking, replyBytesReceived == 0 else {
                Self.step("pre-flight: a line is already playing — leaving it to the watchdog")
                return
            }
            Self.step("pre-flight: no mic buffers — rebuilding before the call opens")
            stopAudio()
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !isTornDown else { return }
            do { try startAudio() } catch {
                Self.step("pre-flight: rebuild failed \(error)")
                return
            }
        }
        Self.step("pre-flight: opening the call with a silent tap — watchdog owns it now")
    }

    /// How long a call may go without putting ONE mic byte on the wire
    /// before it is called deaf. Generous on purpose: this is the last word,
    /// not the recovery — `armTapWatchdog` has already rebuilt the stack up
    /// to three times by the time it runs out.
    private static let micDeadlineSeconds: TimeInterval = 12

    /// A tap that never fires is invisible: the engine reports running, the
    /// socket is up, and the call simply never hears anything (device,
    /// 2026-09-01). This is the CALL-level deadline for exactly that — one
    /// number, and NO recovery of its own.
    ///
    /// It used to restart the whole audio stack twice, at 1.5 s and at 3 s,
    /// and that is what a learner met on 2026-09-13: the opener's text on
    /// screen, no voice at all, then "the call dropped" five seconds in
    /// (three times on build 45, every one of them `mic_bytes=0`). Each
    /// restart tears the session down, and a reply chunk that arrives while
    /// the engine is down is DROPPED from playback (`playReplyChunk`) — so
    /// the churn ate precisely the line the call opens with, while a cold
    /// voice-processing unit that needed more than 1.5 s to deliver its
    /// first buffer was killed twice before it could. Two watchdogs restarting
    /// the same stack on two different clocks could also interleave, each
    /// undoing the other's build.
    ///
    /// Recovery now belongs to `armTapWatchdog` alone: one owner, per build,
    /// and never while the fluent self is audible.
    private func startMicWatchdog() {
        Task { @MainActor [weak self] in
            var waited: TimeInterval = 0
            var lastPlayed = 0
            var lastBytes = 0
            while waited < Self.micDeadlineSeconds {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                waited += 1
                guard let self, !self.isTornDown else { return }
                if self.micBytesSent > 0 { return }
                // A line in the air is not a deaf call: the first one is
                // half-duplex by design (see `audio_start`), so an empty
                // uplink is expected for as long as it plays. Don't spend the
                // deadline on the greeting — measured as audio ARRIVING or
                // being HEARD, never as queue depth, which a wedged engine
                // keeps climbing forever.
                if self.playedBuffers > lastPlayed || self.replyBytesReceived > lastBytes {
                    lastPlayed = self.playedBuffers
                    lastBytes = self.replyBytesReceived
                    waited = 0
                }
            }
            guard let self, !self.isTornDown, self.micBytesSent == 0 else { return }
            self.fail("mic_silent", "The microphone isn't sending any audio. Close and reopen the call.")
        }
    }

    private struct Retry {
        let voiceId: String; let language: String; let system: String
        let opener: String?; let history: [(role: String, text: String)]
    }
    private var pendingRetry: Retry?

    /// The JWT the gateway verifies once, at session start — same source the
    /// edge-function clients use.
    ///
    /// Falls back to opening an ANONYMOUS session when there is none. A debug
    /// build has its own bundle id and therefore its own auth storage, so it
    /// starts signed out even when the App Store build on the same phone is
    /// signed in — and "Auth session missing" is a dead end for a spike whose
    /// whole point is to be launched and talked to. Anonymous is a first-class
    /// state in this app (the voice is heard before the sign-up), so this
    /// borrows the same door rather than inventing one.
    private static func accessToken() async throws -> String {
        if let existing = try? await SupabaseProvider.shared.auth.session {
            return existing.accessToken
        }
        return try await SupabaseProvider.shared.auth.signInAnonymously().accessToken
    }

    /// The one way a call fails. Sets the state the view reacts to AND
    /// leaves the record the console reads — a failure nobody can see later
    /// is the launch-week bug in one sentence.
    private func fail(_ code: String, _ message: String) {
        lastFailureCode = code
        var props = audioFacts()
        props["code"] = code
        props["message"] = String(message.prefix(200))
        props["turns"] = String(lines.count)
        props["mic_bytes"] = String(micBytesSent)
        Telemetry.log("talk_rt_failed", props)
        state = .failed(message)
    }

    /// What the audio stack looked like at the moment it gave up.
    ///
    /// A call that ends deaf leaves nothing else behind: the `step` trace is
    /// DEBUG-only, so the three `mic_silent` rows of 2026-09-13 could say
    /// that no byte went upstream and not one thing about WHY — whether the
    /// tap fired at all, which mic the route was on, or whether anything was
    /// even playing. Every field here is free to read and is the difference
    /// between a diagnosis and another guess.
    private func audioFacts() -> [String: String] {
        let session = AVAudioSession.sharedInstance()
        return [
            "engine_up": engineRunning ? "1" : "0",
            "engine_running": engine.isRunning ? "1" : "0",
            "tap_buffers": String(Self.buffersSinceBuild),
            "builds": String(buildEpoch),
            "route_in": session.currentRoute.inputs.first?.portType.rawValue ?? "none",
            "route_out": session.currentRoute.outputs.first?.portType.rawValue ?? "none",
            "in_ch": String(session.inputNumberOfChannels),
            "sample_rate": String(Int(session.sampleRate)),
            "other_audio": session.isOtherAudioPlaying ? "1" : "0",
            "queued_buffers": String(pendingBuffers),
            "played_buffers": String(playedBuffers),
        ]
    }

    /// Speak the call's FIRST line, arriving after the call is already up.
    ///
    /// A scenario or a Find-people call has no greeting when it dials: Gemini
    /// writes it. Waiting for that before connecting put the model's 2–4 s in
    /// front of the gateway's own start-up rather than alongside it — 6–8 s of
    /// silence after the tap (measured 2026-09-13). The call opens without an
    /// opener now, and this is how the line gets said when it lands.
    ///
    /// Cached audio wins, exactly as `start.opener` does: the app plays its own
    /// take and tells the gateway to record it without speaking. Otherwise the
    /// gateway says it.
    func say(_ text: String, audio: URL? = nil) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isTornDown, !line.isEmpty, linesStarted == 0 else { return }
        if let audio, let decoded = Self.decodeOpener(audio) {
            localOpener = (line, decoded.buffer, decoded.rate)
            // `ready` may have been and gone already — then play it now; if the
            // call is still connecting, `ready` will.
            if case .connecting = state {} else { playLocalOpener() }
            sendControl(["type": "say", "text": line, "alreadySpoken": true])
            return
        }
        sendControl(["type": "say", "text": line])
    }

    /// Hang up: tells the gateway, then tears the local side down.
    func hangUp() {
        guard !isTornDown else { return }
        sendControl(["type": "end"])
        teardown()
    }

    private func teardown() {
        // The last line's audio is still sitting in `replyPCM` when the
        // learner taps End mid-playback (or right after): `audio_end` will
        // never arrive on a socket about to close, and without this flush
        // that turn is the one Replay silently skips — always the call's
        // closing line (reported 2026-09-01).
        handOverReply()
        isTornDown = true
        routePollTask?.cancel()
        routePollTask = nil
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        stopAudio()
        if case .failed = state {} else { state = .idle }
        partial = ""
        level = 0
    }

    deinit {
        // `teardown` is main-actor; the socket and engine own themselves well
        // enough that a plain cancel is the right non-isolated cleanup.
        socket?.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - Audio graph

    private func startAudio() throws {
        // Fresh graph every time — see the `engine` declaration.
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        let session = AVAudioSession.sharedInstance()
        // Same category/options as a Talk call: whatever the learner is
        // wearing is the mic (`recordOptions` includes HFP), and output is
        // routed after the fact so headphones win over the speaker.
        // `.defaultToSpeaker` is the ONLY way this screen can be loud.
        //
        // Talk gets away without it because it never records and plays at the
        // same time: `AudioPlayer` re-points the route to the speaker before
        // each spoken line. A full-duplex call cannot do that — every route
        // change stops the running engine (measured twice, 2026-09-01), and
        // without one the voice-processing unit keeps the output on the
        // RECEIVER, i.e. the earpiece, which is the "almost inaudible" the
        // learner reported. Put in the CATEGORY it is set once, before the
        // engine exists, and nothing afterwards has to touch the route.
        //
        // ...but ONLY when nothing is plugged in. `.defaultToSpeaker` is
        // documented to yield to a connected accessory, and the rest of this
        // app trusts that (`applyOutputRoute` overrides to `.none` when there
        // is external output). This path cannot afford to find out it was
        // wrong: it has no way to correct the route later, because every
        // route change stops the running engine. So the option is added only
        // when the learner is on the built-in speaker to begin with, and a
        // connected earphone never meets it at all.
        // ALWAYS `recordOptions` — the learner's phone-mic preference is
        // deliberately not honoured on this path. That preference buys
        // "built-in mic + hi-fi A2DP output", a combination that only exists
        // when recording and playback take turns; recorded and played AT ONCE
        // (which is this whole path), iOS drops the A2DP output and the reply
        // lands on the receiver or the open speaker — with earphones in the
        // learner's ears (2026-09-01, twice). A full-duplex call with
        // earphones is HFP or it is inaudible, so it is HFP: mic and output
        // both on the earphone, like every phone call ever made.
        try session.setCategory(.playAndRecord, mode: .default,
                                options: AudioSessionRouting.recordOptions)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        // Pin the input to MONO before the engine is built.
        //
        // Activating the session does not settle its input configuration: on
        // an iPhone the mic array first presents as multi-channel and only
        // collapses to one channel once something asks. Measured on device
        // (2026-09-01): the first setup saw `inCh=4` and its tap never fired;
        // the watchdog's restart saw `inCh=1` and worked immediately, same
        // code both times. Asking for mono here makes the first attempt land
        // in the configuration that works, instead of relying on a retry.
        try? session.setPreferredInputNumberOfChannels(1)
        // Activating the session is not enough to settle its INPUT: the iPhone
        // mic array first presents as 4 channels, and a graph built against
        // that state produces a tap that never fires — silently. Asking for
        // mono does not take effect immediately either. What does work, every
        // time, is a deactivate/reactivate cycle: the watchdog's restart hit
        // `inCh=1` and worked on all four occasions the first attempt saw
        // `inCh=4` and did not (device, 2026-09-01). Do that cycle here, once,
        // instead of shipping a call that needs its own watchdog to start.
        if session.inputNumberOfChannels != 1 {
            Self.step("audio: input settling (inCh=\(session.inputNumberOfChannels)) — cycling session")
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try? session.setPreferredInputNumberOfChannels(1)
        }
        // With an earphone connected the call must live ENTIRELY on it —
        // HFP mic and HFP output. Half-measures don't exist here: A2DP is
        // not honoured as an output while voice processing records, so a
        // built-in-mic + earphone-output split lands the audio on the
        // RECEIVER, where nobody hears it (log 2026-09-01: earphones on the
        // route, `out=Receiver`). Talk avoids this by never recording and
        // playing at once; a full-duplex call doesn't have that escape.
        // iOS did not engage HFP on its own here (input stayed the built-in
        // 4-mic array), so it is asked for explicitly — unlike the app's
        // other surfaces, where the no-setPreferredInput rule stands.
        // "Is an earphone CONNECTED" — not "is it on the route this instant".
        // The two disagree exactly when it matters: our own rebuild releases
        // the HFP link while it cycles the session, and a Bluetooth profile
        // switch fires a spurious oldDeviceUnavailable whose rebuild then saw
        // an earphone-free route and pinned the speaker — with the earphones
        // still in the learner's ears (observed 2026-09-01). `availableInputs`
        // lists the paired device regardless of the route's momentary state.
        var bluetoothMic = session.availableInputs?.first { $0.portType == .bluetoothHFP }
        if let mic = bluetoothMic {
            try? session.setPreferredInput(mic)
            if session.currentRoute.inputs.first?.portType != .bluetoothHFP {
                // Offered but not engaged: an in-ear reattach lists the HFP
                // mic in `availableInputs` while the live session refuses to
                // move onto it (observed 2026-09-01 — input stayed built-in,
                // output fell to the RECEIVER). The same deactivate/
                // reactivate cycle that settles the input channel count also
                // lets the route re-form around the earphone.
                Self.step("audio: HFP offered but not engaged — cycling session")
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                try? session.setPreferredInput(mic)
            }
            if session.currentRoute.inputs.first?.portType != .bluetoothHFP {
                // Still refused. A Receiver call is the one truly broken
                // outcome (nobody hears anything) — fall back to the loud,
                // working configuration instead of shipping a half-route:
                // treat the earphone as absent so the speaker branch below
                // pins `.defaultToSpeaker`.
                Self.step("audio: HFP refused — falling back to speaker")
                bluetoothMic = nil
                AudioSessionRouting.preferBuiltInMic(session)
            }
        }
        Self.step("audio: inputs=\(session.availableInputs?.map(\.portType.rawValue) ?? []) "
            + "in=\(session.currentRoute.inputs.first?.portType.rawValue ?? "none")")

        // Only NOW is the route real: a Bluetooth earphone joins it at
        // activation, not before. The first version checked before activating,
        // saw no external output, forced the speaker — and the learner sat in
        // earphones while the reply played into the room (2026-09-01, log:
        // `external out=false defaultToSpeaker=true` with AirPods in). A
        // category change here is safe; the engine doesn't exist yet.
        if !AudioSessionRouting.hasExternalOutput(session), bluetoothMic == nil {
            // `recordOptions`, NOT `conversationOptions`: the latter honours
            // the phone-mic preference and returns a set WITHOUT
            // `.allowBluetooth` — and a session that doesn't allow HFP is one
            // AirPods can't join mid-call at all: in-ear attach fired no
            // event and never appeared in `availableInputs`, so neither the
            // observer nor the poll could ever see it (device log
            // 2026-09-01). Same reason the first setCategory above ignores
            // the preference on this path.
            var options = AudioSessionRouting.recordOptions
            options.insert(.defaultToSpeaker)
            try session.setCategory(.playAndRecord, mode: .default, options: options)
        }
        Self.step("audio: external out=\(AudioSessionRouting.hasExternalOutput(session)) "
            + "route=\(session.currentRoute.outputs.first?.portType.rawValue ?? "none")")

        let input = engine.inputNode
        // Echo cancellation is not optional on this path — see the type's
        // note. AGC is left ON (unlike LiveTranscriber, which turns it off to
        // protect the learner's own recording): nothing here is replayed to
        // them, and levelling helps the server's endpointing.
        do { try input.setVoiceProcessingEnabled(true) } catch {
            // Some routes refuse it. The call still works; on the speaker it
            // will barge-in on itself, which is why the view warns.
        }
        // Keep noise suppression, drop the AGC — LiveTranscriber's hard-won
        // rule, and it applies here for the same reason it applies there:
        // the learner LISTENS to this capture in Practice, and AGC riding
        // the level makes their own voice play back thin and pumping. The
        // first version left it on ("nothing here is replayed to them"),
        // which stopped being true the day listen-back was wired.
        if #available(iOS 17.0, *) {
            input.isVoiceProcessingAGCEnabled = false
        }
        // AFTER the toggle: VPIO re-negotiates the input format — and on a
        // COLD session it lands on the raw 4-mic array, the exact state whose
        // tap never fires. This became EVERY call's first build once the
        // classic warm-up stopped pre-arming the session (2026-09-03: 1–2
        // watchdog restarts per call, opener text with no voice, one call
        // failed outright). The same deactivate/reactivate cycle that settles
        // the channel count pre-VPIO settles it here too — done NOW, before
        // the engine exists, instead of 1.5 s later by the watchdog.
        if session.inputNumberOfChannels != 1 {
            Self.step("audio: post-VPIO inCh=\(session.inputNumberOfChannels) — cycling session")
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try? session.setPreferredInputNumberOfChannels(1)
        }
        let probeFormat = input.outputFormat(forBus: 0)
        Self.step("audio: session sr=\(session.sampleRate) inCh=\(session.inputNumberOfChannels) "
            + "inputAvail=\(session.isInputAvailable) probe=\(probeFormat.sampleRate)/\(probeFormat.channelCount)")
        guard probeFormat.sampleRate > 0, probeFormat.channelCount > 0 else {
            throw RealtimeError.audioUnavailable
        }

        // The wire format the gateway (and Gemini) expects.
        guard let uplink = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: 16000, channels: 1,
                                         interleaved: true) else {
            throw RealtimeError.audioUnavailable
        }
        uplinkFormat = uplink
        // The converter is built from the format the tap is ACTUALLY installed
        // with, which is only known after the graph is wired — see below.

        engine.attach(player)
        // The player is connected with the REPLY's format, not the mixer's.
        // `scheduleBuffer` requires the buffer's format to match the one the
        // node was connected with, and it enforces that with an ObjC
        // exception that no Swift `try` can catch — connecting with `nil`
        // (i.e. the mixer's 48 kHz) and then scheduling 22.05 kHz audio
        // aborted the app on the first spoken word (crash 2026-08-31).
        // `audio_start` announces the real rate before any audio arrives, so
        // `ensurePlaybackFormat` re-connects if it ever differs.
        connectPlayer(rate: replySampleRate)

        // Prepare BEFORE reading the input format and installing the tap.
        // Connecting the player above touches `mainMixerNode`, which wires
        // mainMixer → output and makes the engine renegotiate the graph — and
        // with voice processing on, input and output are the SAME unit, so
        // the input node's format can change underneath a tap installed
        // earlier. That is exactly what happened on device (2026-09-01):
        // every setup step logged success, the engine reported running, and
        // the tap block was never called once. Read the format last, install
        // the tap last.
        // Order here is load-bearing and was established by measurement, not
        // reasoning (device, 2026-09-01):
        //
        //   prepare() → install tap → start()   ✅ buffers flow
        //   prepare() → start() → install tap   ❌ tap NEVER fires, 4/4 runs
        //
        // With voice processing on, the running unit's render callback is
        // configured at start; a tap added afterwards is simply never called,
        // and nothing anywhere reports an error. So the tap goes on BEFORE
        // the engine runs, and a tap that still produces nothing is recovered
        // by restarting the whole audio stack, never by re-tapping a live
        // engine (see `startMicWatchdog`).
        engine.prepare()
        try installMicTap()
        try engine.start()
        // NOTHING touches the route from here on. Even the bare port override
        // (`overrideOutputAudioPort`) changes the route, and a route change
        // stops a running AVAudioEngine — measured twice on device
        // (2026-09-01), each time as `engine running=false out=Speaker`: the
        // right output, no audio at all. The route is settled BEFORE the
        // engine is built (see the reassert above); afterwards it is only
        // ever observed, never set.
        Self.step("audio: engine running=\(engine.isRunning) "
            + "out=\(session.currentRoute.outputs.first?.portType.rawValue ?? "none")")
        if !engine.isRunning {
            // Something stopped it between prepare and here — start once more
            // before giving up, now that the route has stopped moving.
            try engine.start()
            Self.step("audio: engine restarted running=\(engine.isRunning)")
        }
        guard engine.isRunning else { throw RealtimeError.audioUnavailable }
        observeRouteChanges()
        startRoutePoll()
        streamLevel = AudioLoudness.StreamingLevelEstimator()
        routeBoost = pow(10, AudioSessionRouting.playbackBoostDB() / 20)
        userGain = AudioPlayer.talkVoiceVolume
        streamGain = 1
        player.play()
        engineRunning = true
        builtOutput = session.currentRoute.outputs.first?.portType.rawValue ?? "none"
        lastAudioBuildAt = Date()
        Self.buffersSinceBuild = 0
        armTapWatchdog()
        // The tap is live from here — hand the audio thread what it needs.
        mic.set(converter: converter, format: uplinkFormat, socket: socket)
    }

    /// Rebuild the audio stack when the route changes under the call.
    ///
    /// Plugging in earphones mid-call — or pulling them out — reshapes the
    /// graph iOS handed us: the engine stops, and on this path a stopped
    /// engine is a call that has gone deaf and mute with nothing on screen
    /// saying so. The whole stack is torn down and rebuilt because that is
    /// the only recovery that works here (a live engine cannot be re-tapped,
    /// and the route cannot be corrected while it runs).
    private func observeRouteChanges() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            guard let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.isTornDown, self.engineRunning else { return }
                let nowOut = AVAudioSession.sharedInstance().currentRoute.outputs
                    .first?.portType.rawValue ?? "none"
                Self.step("route event (\(raw)) out=\(nowOut) built=\(self.builtOutput)")
                switch reason {
                case .newDeviceAvailable, .oldDeviceUnavailable:
                    // A device joined or left — always rebuild (the route may
                    // not have moved YET; the settle sleep below waits for it).
                    break
                case .routeConfigurationChange, .override:
                    // AirPods that are already paired switch in and out of the
                    // ear with NO device event at all (observed 2026-09-01:
                    // in-ear attach fired nothing we listened for, audio
                    // stayed on the speaker). But our OWN setCategory/override
                    // calls land here too, which is how listening to
                    // `.override` once made every rebuild trigger the next.
                    // The tiebreaker: only a route that no longer matches the
                    // one the engine was built on may trigger.
                    guard nowOut != self.builtOutput else { return }
                default:
                    return
                }
                // NO cooldown for genuine device events. Earphones attach in
                // stages: the first event's rebuild routinely lands before
                // the device is on the route (observed: it saw `route=
                // Speaker`, pinned the speaker, and the arrival event a
                // second later was swallowed by a 2 s cooldown — earphones
                // in, audio on the speaker). A rebuild already running just
                // marks the route dirty and reruns once at the end:
                // serialized, so no loop, and the LAST event wins.
                if self.isRebuildingAudio {
                    self.routeRebuildPending = true
                    return
                }
                self.isRebuildingAudio = true
                defer { self.isRebuildingAudio = false }
                repeat {
                    self.routeRebuildPending = false
                    Self.step("route changed (\(reason.rawValue)) — rebuilding audio")
                    self.stopAudio()
                    // Let the route SETTLE before building on it: Bluetooth
                    // joins the route seconds after the notification, and a
                    // graph built mid-transition was today's crash.
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard !self.isTornDown else { return }
                    do { try self.startAudio() } catch {
                        // The seconds right after a Bluetooth detach leave the
                        // session in a transient state where setCategory can
                        // throw (observed 2026-09-01 — one throw ended a call
                        // that a second attempt would have saved). One more
                        // try after a beat before declaring the call lost.
                        Self.step("route rebuild: startAudio threw (\(error)) — retrying once")
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !self.isTornDown else { return }
                        do { try self.startAudio() } catch {
                            self.fail("route", "The audio route changed and the call couldn't recover.")
                            return
                        }
                    }
                } while self.routeRebuildPending && !self.isTornDown
            }
        }
    }

    /// Every engine build gets 2 s to produce its first tap buffer, or the
    /// whole stack is rebuilt — the per-build version of the mic watchdog.
    /// A build whose tap never fires reports `running=true` and looks
    /// perfectly healthy in every other signal; only the absence of buffers
    /// says the call has gone deaf (a poll rebuild onto a fresh HFP link did
    /// exactly this, 2026-09-01, and froze the call).
    private func armTapWatchdog() {
        buildEpoch += 1
        let epoch = buildEpoch
        Task { @MainActor [weak self] in
            // RECURRING, not one-shot: a tap can also produce a few buffers
            // and then die, and the first version of this watchdog checked
            // once and stood down forever — the very next freeze sailed past
            // it (2026-09-01). Progress since the LAST check is the test.
            var lastCount = 0
            var lastPlayed = 0
            var lastBytes = 0
            // The FIRST check gets longer. A cold voice-processing unit —
            // every call's first build since the classic warm-up stopped
            // pre-arming the session — can take over two seconds to hand out
            // its first buffer, and rebuilding it then is how a healthy call
            // was turned into a silent one (2026-09-13).
            var due: UInt64 = 3_000_000_000
            while true {
                try? await Task.sleep(nanoseconds: due)
                guard !Task.isCancelled, let self, !self.isTornDown,
                      self.buildEpoch == epoch, self.engineRunning else { return }
                let count = Self.buffersSinceBuild
                // A build that has never produced a buffer is the dangerous
                // state, and the rebuild that cures it has to wait out the
                // line playing over it — so once a line ends, take the next
                // look quickly rather than leaving the call deaf for another
                // two seconds.
                due = count == 0 ? 1_000_000_000 : 2_000_000_000
                if count > lastCount {
                    lastCount = count
                    self.tapWatchdogStrikes = 0
                    continue
                }
                // NEVER tear the stack down while a line is in the air. A
                // rebuild drops every reply chunk that lands while the engine
                // is down, so a mic problem would be paid for with the one
                // thing that IS working — and the call's first line is
                // half-duplex anyway, so there is nothing upstream to lose by
                // waiting for it to finish. Measured on device 2026-09-13:
                // this watchdog fired 2.1 s into the opener, rebuilt the
                // stack, and the learner heard no greeting at all.
                //
                // "In the air" is audio ARRIVING or being HEARD since the last
                // check — never the queue depth, which a wedged engine keeps
                // climbing forever. Both stop when the line does, so the
                // rebuild this defers happens a beat later, in silence.
                if self.playedBuffers > lastPlayed || self.replyBytesReceived > lastBytes {
                    lastPlayed = self.playedBuffers
                    lastBytes = self.replyBytesReceived
                    continue
                }
                guard self.tapWatchdogStrikes < 3 else {
                    self.fail("mic_silent", "The microphone isn't sending any audio. Close and reopen the call.")
                    return
                }
                self.tapWatchdogStrikes += 1
                Self.step("tap watchdog: no buffers in 2s (strike \(self.tapWatchdogStrikes)) — restarting audio")
                self.stopAudio()
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !self.isTornDown else { return }
                do { try self.startAudio() } catch {
                    self.fail("route", "The microphone stopped after an audio route change.")
                }
                return // the restart armed its own watchdog for the new epoch
            }
        }
    }

    /// Backup for the route events iOS DOESN'T send: putting already-paired
    /// AirPods back in the ear mid-call fires no notification at all while a
    /// playAndRecord session is active (device log 2026-09-01 — zero route
    /// events across the whole attempt, audio stayed on the speaker). The
    /// connected-device list still updates, so poll it: a Bluetooth mic that
    /// is available while the engine was built without it (or vice versa)
    /// means the world changed under us and the stack rebuilds exactly as a
    /// route event would have it do. Safe from ping-pong because
    /// `availableInputs` tracks in-ear state on AirPods — removal empties it
    /// (verified in the same log) — and `builtOutput` converges on whatever
    /// the rebuild actually got.
    private func startRoutePoll() {
        guard routePollTask == nil else { return }
        routePollTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self, !self.isTornDown else { return }
                guard self.engineRunning, !self.isRebuildingAudio else { continue }
                let session = AVAudioSession.sharedInstance()
                let btAvailable = session.availableInputs?
                    .contains { $0.portType == .bluetoothHFP } ?? false
                let builtOnBT = self.builtOutput == AVAudioSession.Port.bluetoothHFP.rawValue
                guard btAvailable != builtOnBT else {
                    self.pollRebuildStrikes = 0
                    self.pollMismatchTicks = 0
                    continue
                }
                // TWO consecutive ticks before acting. A Bluetooth device can
                // flicker into `availableInputs` for a moment (a case lid, a
                // passing pairing) — one tick of that tore down a perfectly
                // working speaker call and rebuilt it into the deaf inCh=4
                // state (2026-09-01). A real attach stays available; 2 s of
                // patience costs the transition little and never wrecks a
                // healthy call for a ghost.
                self.pollMismatchTicks += 1
                guard self.pollMismatchTicks >= 2 else { continue }
                // ONE try, then hold. A rebuild that fails to engage the
                // earphone leaves this condition true forever — uncapped, the
                // poll re-rebuilt every 2 s and the call spent itself
                // restarting (observed 2026-09-01, stuck on the Receiver).
                // And more than one try buys nothing: across every logged
                // attach, the in-poll rebuild NEVER engaged a link that was
                // still forming — what always worked was the
                // `.newDeviceAvailable` that iOS fires seconds later, once
                // the HFP link is real (possible at all because the category
                // keeps `.allowBluetooth` on the speaker path). Each failed
                // try costs ~2 s of silence mid-call, so the poll is a
                // safety net for "HFP fully formed but no event came", not a
                // battering ram.
                guard self.pollRebuildStrikes < 1 else { continue }
                self.pollRebuildStrikes += 1
                Self.step("route poll: bluetooth avail=\(btAvailable) built=\(self.builtOutput) — rebuilding audio")
                self.isRebuildingAudio = true
                self.stopAudio()
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !self.isTornDown else { self.isRebuildingAudio = false; return }
                do { try self.startAudio() } catch {
                    // Same transient-throw window as the event path — one
                    // retry before the call is declared lost.
                    Self.step("route poll: startAudio threw (\(error)) — retrying once")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !self.isTornDown else { self.isRebuildingAudio = false; return }
                    do { try self.startAudio() } catch {
                        self.isRebuildingAudio = false
                        self.fail("route", "The audio route changed and the call couldn't recover.")
                        return
                    }
                }
                self.isRebuildingAudio = false
            }
        }
    }

    /// Run one raise-prone AVFAudio call. Returns false (and logs WHICH
    /// call) instead of letting the NSException kill the process — three
    /// crashes on 2026-09-01 were this exact class, each from a different
    /// call site, and guarding them one at a time was losing the war.
    @discardableResult
    private static func avGuard(_ label: String, _ block: () -> Void) -> Bool {
        var raised: NSError?
        FVCatchException(block, &raised)
        if let raised {
            Self.step("avfaudio RAISED in \(label): \(raised.localizedDescription)")
            return false
        }
        return true
    }

    /// (Re)install the mic tap against the graph's CURRENT input format,
    /// rebuilding the converter to match. Safe to call on a running engine —
    /// that is in fact the only time it should be called.
    @discardableResult
    private func installMicTap() throws -> AVAudioFormat {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let uplink = uplinkFormat else {
            throw RealtimeError.audioUnavailable
        }
        converter = AVAudioConverter(from: format, to: uplink)
        mic.set(converter: converter, format: uplink, socket: socket)
        // `installTap` RAISES (ObjC) when the voice-processing unit is mid-
        // renegotiation — a route flip, a restart racing the HAL. Raised, it
        // killed the app twice today; caught, it is just a failed attempt the
        // watchdog retries or the view surfaces with a Try again.
        var tapError: NSError?
        FVCatchException({
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                self?.handleMicBuffer(buffer)
            }
        }, &tapError)
        if let tapError {
            Self.step("audio: installTap RAISED — \(tapError.localizedDescription)")
            throw RealtimeError.audioUnavailable
        }
        Self.step("audio: tap installed at \(format.sampleRate)/\(format.channelCount)")
        return format
    }

    /// Decode a cached greeting into one PCM buffer the player can take.
    ///
    /// `AVAudioFile.processingFormat` is float32, deinterleaved, at the file's
    /// own rate — the same shape `connectPlayer` uses — so a mono take needs
    /// no conversion. Anything else (a stereo file, an unreadable one) returns
    /// nil and the caller simply lets the gateway speak the line as before.
    private static func decodeOpener(_ url: URL) -> (buffer: AVAudioPCMBuffer, rate: Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        guard format.channelCount == 1, format.commonFormat == .pcmFormatFloat32,
              file.length > 0, file.length < 48000 * 60,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard buffer.frameLength > 0 else { return nil }
        return (buffer, format.sampleRate)
    }

    /// Speak the greeting from the phrase cache, the moment the gateway says
    /// the call is up.
    ///
    /// Measured 2026-09-13: tap → first word was 4.4 s on a healthy call, of
    /// which ~1 s was the gateway asking ElevenLabs for a line the phone had
    /// already had on disk since the Talk tab was opened. The allowance
    /// pre-flight still runs in front of this — `ready` is what triggers it —
    /// so a spent month is still told before the fluent self says a word.
    ///
    /// Everything else about the line is identical to a streamed one: the same
    /// echo gate, the same loudness law, the same hand-off to the call screen
    /// with its audio, so Replay and the book see no difference.
    private func playLocalOpener() {
        guard let opener = localOpener, engineRunning else { return }
        localOpener = nil
        let buffer = opener.buffer
        guard let samples = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)

        linesStarted += 1
        let context = "opener-\(UUID().uuidString)"
        replyContext = context
        replyText = opener.text
        replyPCM = Data()
        onReplyBegan?(context)
        onReplyDelta?(context, "\u{0}" + opener.text)

        // Same rule as `audio_start`: the call's first line on the open
        // speaker is half-duplex, because the echo canceller has not heard
        // the voice yet and cannot cancel what it has never heard.
        let halfDuplex = builtOutput == AVAudioSession.Port.builtInSpeaker.rawValue
        mic.setEchoGate(active: true, halfDuplex: halfDuplex)
        state = .speaking
        replySampleRate = opener.rate
        ensurePlaybackFormat(rate: opener.rate)

        // The same loudness law every streamed line goes through — without it
        // the greeting plays at whatever level ElevenLabs rendered it, next to
        // replies that are levelled ("인사말만 크고 나머지는 안 들리던" in reverse).
        updateStreamGain(samples: samples, count: frames)
        if streamGain != 1 {
            for i in 0..<frames {
                samples[i] = max(-0.985, min(0.985, samples[i] * streamGain))
            }
        }
        // Keep the take for Replay, in the Int16 form `handOverReply` expects.
        var ints = [Int16](repeating: 0, count: frames)
        for i in 0..<frames {
            ints[i] = Int16(max(-32768, min(32767, samples[i] * 32767))).littleEndian
        }
        replyPCM = ints.withUnsafeBufferPointer { Data(buffer: $0) }

        pendingBuffers += 1
        mic.markPlaybackStarted()
        serverAudioEnded = true   // nothing more is coming for this line
        let scheduled = Self.avGuard("scheduleOpener") {
            self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingBuffers = max(0, self.pendingBuffers - 1)
                    self.playedBuffers += 1
                    guard self.replyContext == context else { return }
                    self.level = 0
                    self.closeEchoGateAfterTail()
                    if self.state == .speaking { self.state = .listening }
                    self.handOverReply()
                }
            }
        }
        if !scheduled {
            // The player refused it — fall back to the state the call would
            // have been in, and let the learner speak first.
            pendingBuffers = max(0, pendingBuffers - 1)
            state = .listening
            mic.setEchoGate(active: false)
            handOverReply()
        }
    }

    /// Connect (or re-connect) the player node at `rate`. The engine resamples
    /// into the mixer, so any rate is playable — what matters is that the
    /// connection format and the scheduled buffers agree.
    private func connectPlayer(rate: Double) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: rate, channels: 1,
                                         interleaved: false) else { return }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        playbackFormat = format
    }

    /// The gateway announced the reply's sample rate. Re-wire only when it
    /// actually changed, and never mid-line: this runs on `audio_start`,
    /// before the first chunk of that reply.
    private func ensurePlaybackFormat(rate: Double) {
        guard engineRunning, playbackFormat?.sampleRate != rate else { return }
        player.stop()
        pendingBuffers = 0
        connectPlayer(rate: rate)
        player.play()
    }

    private func stopAudio() {
        guard engineRunning else { return }
        engineRunning = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        engine.detach(player)
        mic.set(converter: nil, format: nil, socket: nil)
        converter = nil
        pendingBuffers = 0
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Convert one mic buffer to 16 kHz s16le and put it on the wire.
    ///
    /// Everything that touches `buffer` happens HERE, synchronously, on the
    /// audio thread: a tap's buffer is only valid for the duration of the
    /// callback, and the engine reuses its storage the moment it returns.
    /// The first version hopped to the main actor and read it there, which
    /// reads recycled audio. `URLSessionWebSocketTask.send` is thread-safe,
    /// so the wire write stays here too; only the meter — a single Float —
    /// crosses over.
    private nonisolated func handleMicBuffer(_ buffer: AVAudioPCMBuffer) {
        // Counted FIRST, before the uplink is even required: this number
        // answers "is the microphone alive", and `connect` asks it before the
        // socket exists (see the pre-flight there). Counting it after the
        // guard made a live tap indistinguishable from a dead one for the
        // whole setup window.
        Self.buffersSinceBuild += 1
        if !Self.sawFirstBuffer {
            Self.sawFirstBuffer = true
            Self.step("tap: FIRST buffer \(buffer.frameLength)@\(Int(buffer.format.sampleRate))")
        }
        guard let (converter, uplink, socket) = mic.current() else {
            Self.trace("tap: no uplink yet")
            return
        }
        // Native-quality copy for listen-back, made BEFORE the 16 kHz
        // transport conversion. The tap's own buffer is the best this mic
        // gets; everything downstream of it is for the wire.
        var nativeCopy: Data? = nil
        let nativeRate = buffer.format.sampleRate
        if let floats = buffer.floatChannelData?[0] {
            let count = Int(buffer.frameLength)
            var ints = [Int16](repeating: 0, count: count)
            for i in 0..<count {
                ints[i] = Int16(max(-32768, min(32767, floats[i] * 32767)))
            }
            nativeCopy = ints.withUnsafeBufferPointer { Data(buffer: $0) }
        }
        Self.trace("tap: in=\(buffer.frameLength)@\(Int(buffer.format.sampleRate))")
        let ratio = uplink.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: uplink, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0,
              let channel = out.int16ChannelData else {
            Self.trace("convert failed: err=\(error?.localizedDescription ?? "nil") out=\(out.frameLength)")
            return
        }
        let frames = Int(out.frameLength)
        var sum: Double = 0
        for i in 0..<frames {
            let v = Double(channel[0][i]) / 32768.0
            sum += v * v
        }
        let rms = Float((sum / Double(frames)).squareRoot())
        let db = 20 * log10(max(Double(rms), 0.00001))
        let norm = Float(max(0, min(1, (db + 50) / 45)))

        // While the fluent self is audible, decide whether this buffer is the
        // learner or the speaker coming back. `gateState` is read on the audio
        // thread, so it lives in the same lock as the uplink.
        let gate = mic.echoGate()
        var muted = false
        if gate.active {
            if gate.halfDuplex || !gate.playing {
                // Half-duplex line, or the voice hasn't reached the player
                // yet: nothing to measure against, forward silence.
                muted = true
            } else if gate.learnedFrames < Self.echoLearnFrames {
                mic.learnEcho(rms: rms, counts: true)
                muted = true
            } else {
                muted = rms < gate.floor * Self.echoMargin
                // Echo under the bar raises the bar for the rest of the
                // line. Only judged-echo feeds the floor, so a real barge-in
                // never mutes its own continuation.
                if muted { mic.learnEcho(rms: rms, counts: false) }
            }
        }
        if muted {
            // Silence, not a gap: the transcriber is streaming and a hole in
            // the timeline is worse than quiet.
            socket.send(.data(Data(count: frames * MemoryLayout<Int16>.size))) { _ in }
        } else {
            socket.send(.data(Data(bytes: channel[0], count: frames * MemoryLayout<Int16>.size))) { _ in }
        }
        let bytes = frames * MemoryLayout<Int16>.size
        let copy = Data(bytes: channel[0], count: bytes)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.micBytesSent += bytes
            // The pill follows whoever is actually audible. While a reply
            // plays it shows the reply — except when the mic frame passed the
            // echo gate, which means the LEARNER is talking (over it, or in
            // the tail right after it): their own voice must light the pixels
            // from its first word, not from the moment the server catches up
            // (reported 2026-09-01: "no reaction at the start").
            if !muted || self.state != .speaking { self.level = norm }
            // Keep the learner's own take for listen-back in Practice —
            // every frame that went upstream as REAL audio, and none that
            // went as silence. The first cut fenced on "a line is playing"
            // instead, which also dropped the learner TALKING OVER that line
            // and the 0.4 s after it — with a fast speaker, that is the
            // first words of their answer, and Replay opened mid-sentence
            // (reported 2026-09-01). The per-frame verdict already separates
            // their voice from the echo; recording follows it exactly.
            if !muted, let nativeCopy, self.userPCM.count < self.maxUserPCMBytes {
                // A rebuild used to wipe this buffer outright, and the call's
                // first utterance overlaps the early watchdog churn often
                // enough that Replay's first You take came back empty
                // (reported 2026-09-01). Only a real RATE change forces a
                // reset — same-rate rebuilds keep every word; mixing rates
                // would corrupt the WAV, so there the newer take wins.
                if nativeRate != self.userPCMRate, !self.userPCM.isEmpty {
                    self.userPCM = Data()
                }
                self.userPCM.append(nativeCopy)
                self.userPCMRate = nativeRate
            }
        }
    }

    // MARK: - Socket

    private func openSocket(token: String, voiceId: String,
                            language: String, system: String,
                            opener: String?,
                            history: [(role: String, text: String)]) throws {
        let task = session.webSocketTask(with: Self.gatewayURL)
        socket = task
        mic.set(converter: converter, format: uplinkFormat, socket: task)
        task.resume()
        receiveNext()
        var payload: [String: Any] = [
            "type": "start",
            "token": token,
            "voiceId": voiceId,
            "language": language,
            "system": system,
        ]
        if let opener, !opener.isEmpty { payload["opener"] = opener }
        if !history.isEmpty {
            payload["history"] = history.map { ["role": $0.role, "text": $0.text] }
        }
        sendControl(payload)
    }

    private func sendControl(_ payload: [String: Any]) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    private func receiveNext() {
        socket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, !self.isTornDown else { return }
                switch result {
                case .failure(let error):
                    self.fail("socket", error.localizedDescription)
                    self.teardown()
                case .success(let message):
                    switch message {
                    case .data(let data):   self.playReplyChunk(data)
                    case .string(let text): self.handleEvent(text)
                    @unknown default:       break
                    }
                    self.receiveNext()
                }
            }
        }
    }

    // MARK: - Events

    private var turnCommittedAt: Date?

    private func handleEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        // Every inbound event, once per kind per second — the other half of
        // the picture: mic bytes leaving the phone prove nothing about what
        // the gateway made of them.
        Self.trace("event: \(type)")
        switch type {
        case "ready":
            Self.step("gateway: ready")
            state = .listening
            playLocalOpener()
        case "user_partial":
            let text = json["text"] as? String ?? ""
            // Every interim, stamped: how far behind the mouth the on-screen
            // line runs is exactly the thing being debugged (2026-09-04).
            if text != partial { Self.step("partial(\(text.count)): \(text.suffix(40))") }
            partial = text
            if state != .speaking { state = partial.isEmpty ? .listening : .hearing }
        case "user_turn":
            let said = json["text"] as? String ?? ""
            Self.step("heard: \(said)")
            if !said.isEmpty {
                let pcm = userPCM
                userPCM = Data()
                let rate = userPCMRate
                let trimmed = Self.trimSilence(pcm: pcm, sampleRate: rate)
                let url = Self.saveWAV(pcm: trimmed, sampleRate: rate)
                let ms = Int(Double(trimmed.count / 2) / rate * 1000)
                onUserTurn?(said, url, ms)
            } else {
                userPCM = Data()
            }
            partial = ""
            turnCommittedAt = Date()
            if !said.isEmpty { lines.append(Line(isUser: true, text: said)) }
            state = said.isEmpty ? .listening : .thinkingReply
        case "audio_start":
            Self.step("reply audio starting")
            streamLevel = AudioLoudness.StreamingLevelEstimator()
            replyPCM = Data()
            replyText = ""
            // The bubble goes up WITH the voice, not after it. Waiting for
            // `audio_end` put the fluent self's text on screen only once
            // the line had finished playing — heard first, read seconds
            // later (reported 2026-09-01).
            if let context = json["context"] as? String {
                replyContext = context
                onReplyBegan?(context)
            }
            // The FIRST line of a call on the open speaker is half-duplex.
            // Measured 2026-09-11 (device, speakerphone): the opener's own
            // words came back as the learner's turn ("What is the best
            // thing that is…"), cut the line and got answered — and the
            // very next reply on the same call leaked nothing. The echo
            // canceller is adaptive: it has cancelled nothing until it has
            // heard the speaker, so the first line of every call is the one
            // it cannot yet remove, and the level gate alone (learning on
            // room noise, see `gatePlaying`) never stood a chance against
            // it. Nobody needs to interrupt a greeting; a learner in
            // earphones keeps full duplex from the first word.
            linesStarted += 1
            let halfDuplex = linesStarted == 1
                && builtOutput == AVAudioSession.Port.builtInSpeaker.rawValue
            if halfDuplex { Self.step("echo gate: first line on speaker — half-duplex") }
            mic.setEchoGate(active: true, halfDuplex: halfDuplex)
            replySampleRate = json["sampleRate"] as? Double ?? 22050
            ensurePlaybackFormat(rate: replySampleRate)
            // The line is appended empty and filled by the deltas, so the
            // learner watches the reply arrive rather than waiting for it.
            lines.append(Line(isUser: false, text: ""))
            serverAudioEnded = false
            state = .speaking
        case "reply_delta":
            let delta = json["text"] as? String ?? ""
            if let idx = lines.lastIndex(where: { !$0.isUser }) {
                lines[idx].text += delta
            }
            replyText += delta
            if let context = replyContext { onReplyDelta?(context, delta) }
        case "reply":
            if let full = json["text"] as? String {
                replyText = full
                if let idx = lines.lastIndex(where: { !$0.isUser }) {
                    lines[idx].text = full
                }
                // The authoritative text, in case deltas were coalesced.
                if let context = replyContext { onReplyDelta?(context, "\u{0}" + full) }
            }
        case "audio_end":
            Self.step("audio_end (queued=\(pendingBuffers))")
            // "Sent" is not "heard": chunks are still draining through the
            // player. The turn flips to listening when the QUEUE empties —
            // flipping here put the You bubble up while the fluent self was
            // still mid-sentence, or (with a long buffer) confusingly late.
            serverAudioEnded = true
            if pendingBuffers == 0, state == .speaking { state = .listening }
            handOverReply()
            // Close the gate only when the SPEAKER has finished — "sent" is
            // not "heard" here either. With chunks still queued, closing on
            // this event left the reply's last seconds playing UNGATED, and
            // on speakerphone their echo came back as a phantom learner turn
            // the fluent self then answered (reported 2026-09-02, build 29).
            // A drained queue closes it below, in the playback completion.
            if pendingBuffers == 0 { closeEchoGateAfterTail() }
        case "interrupted":
            // Drop everything queued: the learner is talking over it, and the
            // gateway has already stopped generating. Anything still in the
            // player is a voice arguing with them.
            Self.avGuard("interrupt.stop") { self.player.stop() }
            pendingBuffers = 0
            // `play()` RAISES if the engine died underneath us (a route blip
            // mid-line); a failed resume is recovered by the next line's
            // rebuild, a raise is a crash.
            Self.avGuard("interrupt.play") { self.player.play() }
            state = .hearing
            handOverReply()
            // A barge-in means the learner IS talking — the gate would only
            // stand in their way now.
            mic.setEchoGate(active: false)
        case "stats":
            speechSeconds = json["speechSeconds"] as? Int ?? speechSeconds
        case "rotating":
            break   // the gateway reconnects upstream on its own
        case "warning":
            // The call survived something — a retried reply, a dropped TTS
            // line. Nothing to show; everything to record.
            warningsThisCall += 1
            Telemetry.log("talk_rt_warning", [
                "code": json["code"] as? String ?? "",
                "message": String((json["message"] as? String ?? "").prefix(200)),
            ])
        case "ended":
            // The gateway's last word. The only per-session record this path
            // produces — the reply and the voice never touch the usage
            // ledger — so it goes straight to client_events for the console.
            let voice = (json["voiceFirstMs"] as? [Int] ?? []).sorted()
            let p50 = voice.isEmpty ? nil : voice[voice.count / 2]
            let gaps = (json["mergeGapMs"] as? [Int] ?? []).sorted()
            let gapP50 = gaps.isEmpty ? nil : gaps[gaps.count / 2]
            Telemetry.log("talk_rt_session", [
                "reason": json["reason"] as? String ?? "",
                "turns": String(json["turns"] as? Int ?? 0),
                "speech_s": String(json["speechSeconds"] as? Int ?? 0),
                "duration_ms": String(json["durationMs"] as? Int ?? 0),
                "voice_first_p50_ms": p50.map(String.init) ?? "",
                "voice_first_max_ms": voice.last.map(String.init) ?? "",
                "voice_samples": String(voice.count),
                "warnings": String(json["warnings"] as? Int ?? 0),
                "lines": String(lines.count),
                // Turn-taking evidence (gateway 2026-09-15): how often the
                // fluent self talked over the learner, how often the hold
                // window caught a continuation, and how long this learner's
                // own mid-thought pauses ran. Absent from an older gateway.
                "cutoffs": String(json["cutoffs"] as? Int ?? 0),
                "merges": String(json["merges"] as? Int ?? 0),
                "merge_gap_p50_ms": gapP50.map(String.init) ?? "",
                "merge_gap_max_ms": gaps.last.map(String.init) ?? "",
            ])
        case "error":
            Self.step("gateway error: \(json)")
            let code = json["code"] as? String ?? ""
            let message = json["message"] as? String ?? "gateway error"
            if code == "voice_forbidden", let retry = pendingRetry {
                pendingRetry = nil
                teardown()
                state = .idle
                Task { await connect(voiceId: retry.voiceId, language: retry.language,
                                     system: retry.system, opener: retry.opener,
                                     history: retry.history) }
                return
            }
            // The gateway meters the call server-side (gateway/src/billing.ts)
            // and says WHICH wall ended it. Remember the code so the view can
            // raise the same sheet the classic meter's 402 would have —
            // a spent day is a sheet, never a bare error alert.
            if code == "insufficient_credits" || code == "daily_cap_reached"
                || code == "fair_use_limit" {
                wallCode = code
            }
            fail(code.isEmpty ? "gateway" : code, message)
            teardown()
        default:
            break
        }
    }

    // MARK: - Playback

    /// Same law as `AudioPlayer.updateStreamGain`: measure the speech RMS,
    /// aim at the app's loudness target, jump straight to it inside the first
    /// syllable and ramp gently after that so nothing pumps mid-sentence.
    /// Keep the gate shut for the room's tail. The speaker stops before the
    /// reverberation does, and the last buffers are still in flight.
    /// The queue ran dry but the server never said the line was over.
    /// Measured 2026-09-11 (device, speakerphone): the opener's `audio_end`
    /// never arrived, so the state sat on `speaking` and — now that the
    /// first line is half-duplex — the mic stayed muted for the rest of the
    /// call. A line whose audio has all been HEARD and nothing new has
    /// arrived for a beat is over whatever the server says: close the gate
    /// and hand the turn over. A late `audio_end` after this is harmless
    /// (both paths are idempotent).
    private static let drainFallbackSeconds: TimeInterval = 1.2
    private var drainFallbackTask: Task<Void, Never>?

    private func armDrainFallback() {
        drainFallbackTask?.cancel()
        let context = replyContext
        drainFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.drainFallbackSeconds * 1_000_000_000))
            guard let self, !Task.isCancelled, !self.isTornDown else { return }
            guard self.pendingBuffers == 0, self.state == .speaking,
                  self.replyContext == context, !self.serverAudioEnded else { return }
            Self.step("audio_end never came — queue drained \(Self.drainFallbackSeconds)s ago, ending line locally")
            self.serverAudioEnded = true
            self.closeEchoGateAfterTail()
            self.state = .listening
            self.handOverReply()
        }
    }

    private func closeEchoGateAfterTail() {
        // The room keeps speaking after the speaker stops. On the open
        // speaker that reverberation is loud and long enough to clear the
        // gate's margin, so it gets a longer tail than an earphone route.
        let tail = builtOutput == AVAudioSession.Port.builtInSpeaker.rawValue ? 0.7 : 0.4
        echoHoldUntil = Date().addingTimeInterval(tail)
        let deadline = echoHoldUntil
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(tail * 1_000_000_000))
            guard let self, self.echoHoldUntil <= deadline else { return }
            self.mic.setEchoGate(active: false)
        }
    }

    /// Hand the finished (or interrupted) fluent-self line to the call
    /// screen, with the audio that was actually heard. Idempotent: a line is
    /// handed over once, whether it ended on its own or was talked over.
    private func handOverReply() {
        guard let context = replyContext else { return }
        let pcm = replyPCM
        let text = replyText
        replyPCM = Data()
        replyText = ""
        replyContext = nil
        guard !text.isEmpty else { return }
        let url = Self.saveWAV(pcm: pcm, sampleRate: replySampleRate)
        let ms = Int(Double(pcm.count / 2) / replySampleRate * 1000)
        onReplyFinished?(context, text, url, ms)
    }

    /// Cut the quiet off both ends of a take.
    ///
    /// Even with the gate, a recording starts when the fluent self stops and
    /// ends when the server decides the turn is over — roughly a second of
    /// room at each end that the learner did not fill. Listening back to your
    /// own sentence should start with the sentence.
    ///
    /// The threshold is relative to the take's own peak, so it works at any
    /// distance from the mic; a quarter second of lead-in is kept so nothing
    /// clips the first consonant.
    nonisolated static func trimSilence(pcm: Data, sampleRate: Double) -> Data {
        let samples = pcm.count / MemoryLayout<Int16>.size
        guard samples > 0 else { return pcm }
        let window = max(1, Int(sampleRate * 0.02))          // 20 ms
        let lead = Int(sampleRate * 0.35)
        var peak: Float = 0
        var energies: [Float] = []
        pcm.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Int16.self)
            var index = 0
            while index < samples {
                let end = min(index + window, samples)
                var sum: Float = 0
                for i in index..<end {
                    let v = abs(Float(Int16(littleEndian: ptr[i])) / 32768.0)
                    sum += v * v
                    peak = max(peak, v)
                }
                energies.append((sum / Float(end - index)).squareRoot())
                index = end
            }
        }
        guard peak > 0.01 else { return pcm }   // nothing but room: keep as is
        // 4% of the take's own peak: an opening word spoken at half the
        // volume of the loudest one must still count as speech — at 8%
        // quiet sentence-openers were being cut off with the silence.
        let bar = max(peak * 0.04, 0.004)
        guard let firstLoud = energies.firstIndex(where: { $0 >= bar }),
              let lastLoud = energies.lastIndex(where: { $0 >= bar }) else { return pcm }
        let start = max(0, firstLoud * window - lead)
        let end = min(samples, (lastLoud + 1) * window + lead)
        guard end > start else { return pcm }
        return pcm.subdata(in: (start * 2)..<(end * 2))
    }

    /// PCM → a WAV file in the caches directory. The caller moves it into the
    /// stores that own it (`TurnAudioStore`, `PhraseAudioStore`); anything
    /// left behind is a cache file the system may reclaim, which is the right
    /// fate for audio nobody kept.
    private static func saveWAV(pcm: Data, sampleRate: Double) -> URL? {
        guard !pcm.isEmpty else { return nil }
        let wav = AudioLoudness.wavData(fromPCM16: pcm, sampleRate: Int(sampleRate))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rt-\(UUID().uuidString).wav")
        do { try wav.write(to: url); return url } catch { return nil }
    }

    private func updateStreamGain(samples: UnsafePointer<Float>, count: Int) {
        streamLevel.accumulate(samples, count: count)
        guard let speech = streamLevel.speechRMS else { return }
        let desired = AudioLoudness.gain(forSpeechRMS: speech) * routeBoost * userGain
        if streamLevel.voicedCount < 7_200 {   // ~0.3 s of voice
            streamGain = desired
            return
        }
        let maxStep: Float = pow(10, 1.5 / 20)   // ≤1.5 dB per chunk
        streamGain = desired > streamGain
            ? min(desired, streamGain * maxStep)
            : max(desired, streamGain / maxStep)
    }

    private func playReplyChunk(_ data: Data) {
        guard data.count >= 2 else { return }
        if let committed = turnCommittedAt {
            lastLatencyMs = Int(Date().timeIntervalSince(committed) * 1000)
            turnCommittedAt = nil
        }
        // The RECORDING is transport-side and must not depend on the player:
        // chunks arriving while the engine is down (a route rebuild, the
        // early watchdog churn) used to vanish from `replyPCM` along with
        // their playback, which is why Replay's first fluent-self line came
        // back silent (reported 2026-09-01). Capture first, then play what
        // the graph can take.
        replyPCM.append(data)
        replyBytesReceived += data.count
        guard engineRunning else { return }
        // Schedule in EXACTLY the format the node is connected with. A
        // mismatch is an uncatchable ObjC exception, so a chunk that arrives
        // before `audio_start` re-wired the graph is dropped, not risked.
        guard let format = playbackFormat, format.sampleRate == replySampleRate else { return }
        let frames = data.count / MemoryLayout<Int16>.size
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<frames {
                out[i] = Float(Int16(littleEndian: samples[i])) / 32768.0
            }
        }
        updateStreamGain(samples: out, count: frames)
        if streamGain != 1 {
            for i in 0..<frames {
                out[i] = max(-0.985, min(0.985, out[i] * streamGain))
            }
        }
        pendingBuffers += 1
        mic.markPlaybackStarted()
        let scheduled = Self.avGuard("scheduleBuffer") {
            self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingBuffers = max(0, self.pendingBuffers - 1)
                    // Monotonic, and the only honest proof that audio is
                    // reaching the speaker: a wedged engine still accepts
                    // scheduled buffers (`pendingBuffers` climbs) and plays
                    // none of them, so the watchdogs below measure progress
                    // here rather than in the queue depth.
                    self.playedBuffers += 1
                    if self.pendingBuffers == 0, self.serverAudioEnded {
                        // The last scheduled audio has been HEARD — only now
                        // may the echo gate come down (plus the room's tail).
                        self.closeEchoGateAfterTail()
                    }
                    if self.pendingBuffers == 0, self.state == .speaking {
                        self.level = 0
                        // If the server already closed the line, it is the
                        // learner's turn now.
                        if self.serverAudioEnded { self.state = .listening }
                        else { self.armDrainFallback() }
                    }
                }
            }
        }
        if !scheduled { pendingBuffers = max(0, pendingBuffers - 1) }
        // Rough playback level for the pill while the fluent self speaks.
        if state == .speaking {
            var sum: Float = 0
            for i in 0..<frames { sum += out[i] * out[i] }
            let rms = (sum / Float(frames)).squareRoot()
            let db = 20 * log10(max(rms, 0.00001))
            level = max(0, min(1, (db + 50) / 45))
        }
    }
}

extension RealtimeTalkClient {
    /// One line per second at most — the tap fires ~20x/s and an
    /// unthrottled print would bury the very thing being looked for.
    /// Unthrottled: setup happens once per call, and losing one of these
    /// lines to a rate limiter is how "it just does nothing" stays unsolved.
    /// Wall-clock stamp for the DEBUG console. The device console adds none,
    /// and "the transcript showed up late" is unreadable without one.
    nonisolated private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    nonisolated private static func stamp() -> String { stampFormatter.string(from: Date()) }

    nonisolated static func step(_ message: String) {
        #if DEBUG
        print("[realtime \(stamp())] \(message)")
        #endif
    }

    nonisolated static func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        let now = Date().timeIntervalSince1970
        traceLock.lock()
        let due = now - lastTraceAt > 1.0
        if due { lastTraceAt = now }
        traceLock.unlock()
        if due { print("[realtime \(stamp())] \(message())") }
        #endif
    }
    nonisolated(unsafe) static var sawFirstBuffer = false
    nonisolated(unsafe) private static var lastTraceAt: TimeInterval = 0
    private static let traceLock = NSLock()
}

/// Whether Talk runs on the realtime gateway instead of the per-turn HTTP
/// pipeline. Off by default: the gateway is measurably faster and can be
/// talked over, but it is new, and the old path is the one five months of
/// learners have used. The toggle lives in Me → Speed test.
enum RealtimeMode {
    /// Realtime is the ONLY call path since 2026-09-05, and the opt-out
    /// toggle in Me is gone.
    ///
    /// It was a DEFAULT with an escape hatch (2026-09-02), which is the right
    /// shape for a new transport — until the hatch turns out to be broken.
    /// Off, a learner got the classic per-turn call, and that path
    /// ends turns on its own VAD tiers: it cut the learner off mid-sentence
    /// (reported 2026-09-04, and the tiers had been tuned down twice on
    /// latency telemetry that structurally cannot see a turn ending early).
    /// The same learner reported the call's time not being tracked there.
    /// A setting whose job is "use this if the new one misbehaves" cannot
    /// itself be the worse call.
    ///
    /// The stored key is deliberately IGNORED rather than read once and
    /// migrated: an account that turned realtime off is on the broken path
    /// right now, and the point of this change is to bring it back.
    ///
    /// The classic path's code is untouched and still compiles — every
    /// `if RealtimeMode.isEnabled` in `ConversationView` keeps its `else`.
    /// It is now unreachable, and deleting it is its own change, worth
    /// making only after the realtime path has run a while without anyone
    /// wishing they could turn it off.
    static let isEnabled = true
}

enum RealtimeError: LocalizedError {
    case audioUnavailable
    var errorDescription: String? {
        switch self {
        case .audioUnavailable: return "Couldn't open the microphone."
        }
    }
}
