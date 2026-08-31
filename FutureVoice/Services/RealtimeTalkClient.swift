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
    private var converter: AVAudioConverter?
    private var uplinkFormat: AVAudioFormat?
    private var playbackFormat: AVAudioFormat?
    private var engineRunning = false
    /// Reply PCM is 16-bit LE at whatever rate `audio_start` announced.
    private var replySampleRate: Double = 22050
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
            let token = try await Self.accessToken()
            try startAudio()
            try openSocket(token: token, voiceId: voiceId,
                           language: language, system: system)
        } catch {
            state = .failed(error.localizedDescription)
            teardown()
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
        try session.setCategory(.playAndRecord, mode: .default,
                                options: AudioSessionRouting.conversationOptions)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        AudioSessionRouting.applyOutputRoute(session)
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
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw RealtimeError.audioUnavailable }

        // The wire format the gateway (and Gemini) expects.
        guard let uplink = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: 16000, channels: 1,
                                         interleaved: true) else {
            throw RealtimeError.audioUnavailable
        }
        uplinkFormat = uplink
        converter = AVAudioConverter(from: inputFormat, to: uplink)

        engine.attach(player)
        // Connect with the engine's own output format so the graph agrees
        // with the route that just settled; reply buffers at 22.05 kHz are
        // resampled by the mixer.
        let mixFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        playbackFormat = mixFormat
        engine.connect(player, to: engine.mainMixerNode, format: nil)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handleMicBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        player.play()
        engineRunning = true
    }

    private func stopAudio() {
        guard engineRunning else { return }
        engineRunning = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        engine.detach(player)
        converter = nil
        pendingBuffers = 0
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Convert one mic buffer to 16 kHz s16le and put it on the wire.
    /// Runs on the audio thread — no main-actor work, no allocation beyond
    /// the conversion buffer.
    private nonisolated func handleMicBuffer(_ buffer: AVAudioPCMBuffer) {
        Task { @MainActor [weak self] in
            guard let self, let converter = self.converter,
                  let uplink = self.uplinkFormat, self.socket != nil else { return }
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
                  let channel = out.int16ChannelData else { return }
            let byteCount = Int(out.frameLength) * MemoryLayout<Int16>.size
            let data = Data(bytes: channel[0], count: byteCount)
            self.updateLevel(from: channel[0], frames: Int(out.frameLength))
            self.socket?.send(.data(data)) { _ in }
        }
    }

    /// Mic RMS → the same 0…1 curve the rest of the app's meters use, so the
    /// pill behaves the way it does everywhere else.
    private func updateLevel(from samples: UnsafeMutablePointer<Int16>, frames: Int) {
        guard frames > 0, state != .speaking else { return }
        var sum: Double = 0
        for i in 0..<frames {
            let v = Double(samples[i]) / 32768.0
            sum += v * v
        }
        let rms = (sum / Double(frames)).squareRoot()
        let db = 20 * log10(max(rms, 0.00001))
        level = Float(max(0, min(1, (db + 50) / 45)))
    }

    // MARK: - Socket

    private func openSocket(token: String, voiceId: String,
                            language: String, system: String) throws {
        let task = session.webSocketTask(with: Self.gatewayURL)
        socket = task
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
        switch type {
        case "ready":
            state = .listening
        case "user_partial":
            partial = json["text"] as? String ?? ""
            if state != .speaking { state = partial.isEmpty ? .listening : .hearing }
        case "user_turn":
            let said = json["text"] as? String ?? ""
            partial = ""
            turnCommittedAt = Date()
            if !said.isEmpty { lines.append(Line(isUser: true, text: said)) }
            state = .listening
        case "audio_start":
            replySampleRate = json["sampleRate"] as? Double ?? 22050
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

    private func playReplyChunk(_ data: Data) {
        guard engineRunning, data.count >= 2 else { return }
        if let committed = turnCommittedAt {
            lastLatencyMs = Int(Date().timeIntervalSince(committed) * 1000)
            turnCommittedAt = nil
        }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: replySampleRate,
                                         channels: 1, interleaved: false) else { return }
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

enum RealtimeError: LocalizedError {
    case audioUnavailable
    var errorDescription: String? {
        switch self {
        case .audioUnavailable: return "Couldn't open the microphone."
        }
    }
}
