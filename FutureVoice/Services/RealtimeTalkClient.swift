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
        /// The fluent self is speaking.
        case speaking
        case failed(String)
    }

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let isUser: Bool
        var text: String
    }

    @Published private(set) var state: State = .idle
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

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

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
    }
    private let mic = MicUplink()
    private var converter: AVAudioConverter?
    private var uplinkFormat: AVAudioFormat?
    private var playbackFormat: AVAudioFormat?
    private var engineRunning = false
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
                 fallbackVoiceId: String? = nil) async {
        // A failed call is re-enterable (the view's Try again); a live one is
        // not — reconnecting under it would leave two sockets and two mics.
        switch state {
        case .idle, .failed: break
        default: return
        }
        isTornDown = false
        state = .connecting
        pendingRetry = fallbackVoiceId.map {
            Retry(voiceId: $0, language: language, system: system)
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
                           language: language, system: system)
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

    private struct Retry { let voiceId: String; let language: String; let system: String }
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
        isTornDown = true
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
        // Headphones still win: `.defaultToSpeaker` only decides where audio
        // goes when nothing is plugged in.
        var options = AudioSessionRouting.conversationOptions
        options.insert(.defaultToSpeaker)
        try session.setCategory(.playAndRecord, mode: .default, options: options)
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
        if MicPreferenceStore.forcesBuiltInMic {
            AudioSessionRouting.preferBuiltInMic(session)
        }

        let input = engine.inputNode
        // Echo cancellation is not optional on this path — see the type's
        // note. AGC is left ON (unlike LiveTranscriber, which turns it off to
        // protect the learner's own recording): nothing here is replayed to
        // them, and levelling helps the server's endpointing.
        do { try input.setVoiceProcessingEnabled(true) } catch {
            // Some routes refuse it. The call still works; on the speaker it
            // will barge-in on itself, which is why the view warns.
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
        streamLevel = AudioLoudness.StreamingLevelEstimator()
        routeBoost = pow(10, AudioSessionRouting.playbackBoostDB() / 20)
        userGain = AudioPlayer.talkVoiceVolume
        streamGain = 1
        player.play()
        engineRunning = true
        // The tap is live from here — hand the audio thread what it needs.
        mic.set(converter: converter, format: uplinkFormat, socket: socket)
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
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.handleMicBuffer(buffer)
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
        socket.send(.data(Data(bytes: channel[0], count: frames * MemoryLayout<Int16>.size))) { _ in }

        var sum: Double = 0
        for i in 0..<frames {
            let v = Double(channel[0][i]) / 32768.0
            sum += v * v
        }
        let db = 20 * log10(max((sum / Double(frames)).squareRoot(), 0.00001))
        let norm = Float(max(0, min(1, (db + 50) / 45)))
        let bytes = frames * MemoryLayout<Int16>.size
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.micBytesSent += bytes
            if self.state != .speaking { self.level = norm }
        }
    }

    // MARK: - Socket

    private func openSocket(token: String, voiceId: String,
                            language: String, system: String) throws {
        let task = session.webSocketTask(with: Self.gatewayURL)
        socket = task
        mic.set(converter: converter, format: uplinkFormat, socket: task)
        task.resume()
        receiveNext()
        sendControl([
            "type": "start",
            "token": token,
            "voiceId": voiceId,
            "language": language,
            "system": system,
        ])
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
            partial = ""
            turnCommittedAt = Date()
            if !said.isEmpty { lines.append(Line(isUser: true, text: said)) }
            state = .listening
        case "audio_start":
            Self.step("reply audio starting")
            streamLevel = AudioLoudness.StreamingLevelEstimator()
            replySampleRate = json["sampleRate"] as? Double ?? 22050
            ensurePlaybackFormat(rate: replySampleRate)
            // The line is appended empty and filled by the deltas, so the
            // learner watches the reply arrive rather than waiting for it.
            lines.append(Line(isUser: false, text: ""))
            state = .speaking
        case "reply_delta":
            let delta = json["text"] as? String ?? ""
            if let idx = lines.lastIndex(where: { !$0.isUser }) {
                lines[idx].text += delta
            }
        case "reply":
            if let full = json["text"] as? String,
               let idx = lines.lastIndex(where: { !$0.isUser }) {
                lines[idx].text = full
            }
        case "audio_end":
            if state == .speaking { state = .listening }
        case "interrupted":
            // Drop everything queued: the learner is talking over it, and the
            // gateway has already stopped generating. Anything still in the
            // player is a voice arguing with them.
            player.stop()
            pendingBuffers = 0
            player.play()
            state = .hearing
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
                                     system: retry.system) }
                return
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
        guard engineRunning, data.count >= 2 else { return }
        if let committed = turnCommittedAt {
            lastLatencyMs = Int(Date().timeIntervalSince(committed) * 1000)
            turnCommittedAt = nil
        }
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
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingBuffers = max(0, self.pendingBuffers - 1)
                if self.pendingBuffers == 0, self.state == .speaking {
                    self.level = 0
                }
            }
        }
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

enum RealtimeError: LocalizedError {
    case audioUnavailable
    var errorDescription: String? {
        switch self {
        case .audioUnavailable: return "Couldn't open the microphone."
        }
    }
}
