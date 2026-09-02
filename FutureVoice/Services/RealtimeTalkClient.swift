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

        /// Open or close the gate. Called when a line starts and ends playing.
        func setEchoGate(active: Bool) {
            lock.lock(); defer { lock.unlock() }
            if active && !gateActive {
                gateFloor = 0
                gateLearned = 0
            }
            gateActive = active
        }

        func echoGate() -> (active: Bool, floor: Float, learnedFrames: Int) {
            lock.lock(); defer { lock.unlock() }
            return (gateActive, gateFloor, gateLearned)
        }

        /// Fold one buffer of pure echo into the floor.
        func learnEcho(rms: Float) {
            lock.lock(); defer { lock.unlock() }
            gateFloor = max(gateFloor, rms)
            gateLearned += 1
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
    /// The server said the line is complete; the moment the local queue
    /// drains after this is when the learner's turn actually begins.
    private var serverAudioEnded = false

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
        state = .connecting
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
                state = .failed("Microphone access is off for this app. Settings → nawana → Microphone.")
                return
            }
            Self.step("connect: mic granted")
            let token = try await Self.accessToken()
            Self.step("connect: got token")
            try startAudio()
            Self.step("connect: audio up")
            try openSocket(token: token, voiceId: voiceId,
                           language: language, system: system,
                           opener: opener, history: history)
            Self.step("connect: socket opened")
            startMicWatchdog()
        } catch {
            Self.step("connect FAILED: \(error)")
            state = .failed(error.localizedDescription)
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

    /// A tap that never fires is invisible: the engine reports running,
    /// the socket is up, and the call simply never hears anything (device,
    /// 2026-09-01). Re-install once with the CURRENT format before giving
    /// up, then say so out loud rather than sitting there looking healthy.
    private func startMicWatchdog() {
        Task { @MainActor [weak self] in
            for attempt in 1...2 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, !self.isTornDown, self.engineRunning else { return }
                if self.micBytesSent > 0 { return }
                // A live engine cannot be re-tapped (see `startAudio`), so the
                // only recovery is to tear the audio stack down and build it
                // again — which also releases a session another process (or a
                // SIGKILLed previous run) may still be holding.
                Self.step("watchdog: no mic buffers (attempt \(attempt)) — restarting audio")
                self.stopAudio()
                do { try self.startAudio() } catch {
                    Self.step("watchdog: restart failed \(error)")
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !self.isTornDown, self.micBytesSent == 0 else { return }
            self.state = .failed("The microphone isn't sending any audio. Close and reopen the call.")
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
        // AFTER the toggle: VPIO re-negotiates the input format.
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
                            self.state = .failed("The audio route changed and the call couldn't recover.")
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
            while true {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self, !self.isTornDown,
                      self.buildEpoch == epoch, self.engineRunning else { return }
                let count = Self.buffersSinceBuild
                if count > lastCount {
                    lastCount = count
                    self.tapWatchdogStrikes = 0
                    continue
                }
                guard self.tapWatchdogStrikes < 3 else {
                    self.state = .failed("The microphone isn't sending any audio. Close and reopen the call.")
                    return
                }
                self.tapWatchdogStrikes += 1
                Self.step("tap watchdog: no buffers in 2s (strike \(self.tapWatchdogStrikes)) — restarting audio")
                self.stopAudio()
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !self.isTornDown else { return }
                do { try self.startAudio() } catch {
                    self.state = .failed("The microphone stopped after an audio route change.")
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
                        self.state = .failed("The audio route changed and the call couldn't recover.")
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
        Self.buffersSinceBuild += 1
        if !Self.sawFirstBuffer {
            Self.sawFirstBuffer = true
            Self.step("tap: FIRST buffer \(buffer.frameLength)@\(Int(buffer.format.sampleRate))")
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
            if gate.learnedFrames < Self.echoLearnFrames {
                mic.learnEcho(rms: rms)
                muted = true
            } else {
                muted = rms < gate.floor * Self.echoMargin
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
                    self.state = .failed(error.localizedDescription)
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
        case "user_partial":
            partial = json["text"] as? String ?? ""
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
            mic.setEchoGate(active: true)
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
            // "Sent" is not "heard": chunks are still draining through the
            // player. The turn flips to listening when the QUEUE empties —
            // flipping here put the You bubble up while the fluent self was
            // still mid-sentence, or (with a long buffer) confusingly late.
            serverAudioEnded = true
            if pendingBuffers == 0, state == .speaking { state = .listening }
            handOverReply()
            closeEchoGateAfterTail()
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
            if code == "insufficient_credits" || code == "daily_cap_reached" {
                wallCode = code
            }
            state = .failed(message)
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
    private func closeEchoGateAfterTail() {
        echoHoldUntil = Date().addingTimeInterval(0.4)
        let deadline = echoHoldUntil
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
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
        let scheduled = Self.avGuard("scheduleBuffer") {
            self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingBuffers = max(0, self.pendingBuffers - 1)
                    if self.pendingBuffers == 0, self.state == .speaking {
                        self.level = 0
                        // The last scheduled audio has been HEARD — if the
                        // server already closed the line, it is the learner's
                        // turn now.
                        if self.serverAudioEnded { self.state = .listening }
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
    nonisolated static func step(_ message: String) {
        #if DEBUG
        print("[realtime] \(message)")
        #endif
    }

    nonisolated static func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        let now = Date().timeIntervalSince1970
        traceLock.lock()
        let due = now - lastTraceAt > 1.0
        if due { lastTraceAt = now }
        traceLock.unlock()
        if due { print("[realtime] \(message())") }
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
    static let key = "futurevoice.realtimeTalk"
    /// Realtime is the DEFAULT since 2026-09-02 (device-verified the day
    /// before, billing server-side). The setting is now an opt-OUT: a learner
    /// who prefers the classic per-turn call turns it off in Me. An account
    /// that explicitly chose either way keeps its choice — only the
    /// never-touched key changed meaning.
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum RealtimeError: LocalizedError {
    case audioUnavailable
    var errorDescription: String? {
        switch self {
        case .audioUnavailable: return "Couldn't open the microphone."
        }
    }
}
