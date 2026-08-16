import AVFoundation
import Foundation

/// Records mic audio to a 16kHz mono PCM WAV file — the format Whisper and
/// ElevenLabs expect. Phase 1 keeps this simple: tap-to-start, tap-to-stop.
/// Phase 2 should add VAD so the user doesn't have to hold a button.
@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var levels: Float = 0   // 0…1, for waveform UI
    /// Friendly description of the mic currently in use. Surfaced in the
    /// onboarding UI so the user can spot Bluetooth / weird routing before
    /// they record a useless clone sample.
    @Published private(set) var inputDescription: String = ""

    /// True while ambient monitoring runs (no keepable file, meters only).
    @Published private(set) var isMonitoring = false
    /// Slow ambient loudness, dBFS (≈ −60…0), ~0.6 s time constant — the
    /// "how noisy is this room" reading behind the quiet-spot verdict, as
    /// opposed to `levels` which is fast enough to ride syllables.
    @Published private(set) var ambientDBFS: Float = -60
    /// Last measured echo tail in milliseconds: how long a clap took to decay
    /// 20 dB below its peak. Short (< ~220 ms) = dry, soft room; long = open,
    /// reverberant space that would smear the clone. nil until a clap lands.
    @Published private(set) var echoTailMs: Double?

    /// Clap-tail tracker for the echo check (monitoring only). Timestamps are
    /// SAMPLE-CLOCK seconds (frames seen ÷ sample rate), never wall clock —
    /// decay timing must not inherit main-thread jitter.
    private enum EchoPhase {
        case armed                                    // waiting for a transient
        case tracking(peak: Float, peakAt: Double)    // clap detected, watching decay
        case cooling(until: Double)                   // ignore the clap's own settle
    }
    private var echoPhase: EchoPhase = .armed
    /// Previous 10 ms window's level — the rise-rate gate that separates a
    /// clap (near-instant jump) from speech/rustle (slow ramp).
    private var lastWindowDB: Float = -60
    private var meterTick = 0

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var monitorEngine: AVAudioEngine?

    /// Serial frame counter owned by the tap closure — the monitoring time
    /// base. Tap callbacks arrive on one thread in order, so no locking.
    private final class FrameClock { var frames: Double = 0 }

    /// Two-quality recording. STT-bound user speech can stay at 16 kHz / 16-bit
    /// since Whisper and SFSpeechRecognizer expect that anyway. Voice CLONING
    /// samples should go higher — ElevenLabs IVC noticeably benefits from
    /// 44.1 kHz / 24-bit input and our previous default was hurting quality.
    enum Quality {
        case sttOptimal       // 16 kHz mono 16-bit PCM WAV
        case voiceCloneHigh   // 44.1 kHz mono 24-bit PCM WAV
    }

    /// Asks for microphone permission. Returns true if granted.
    func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    /// Everything a recording needs EXCEPT the first sample: session
    /// category/route, the built-in mic, the file, and `prepareToRecord()`.
    /// Returns the destination URL; nothing is captured until `beginPrepared`.
    ///
    /// Exists because Shadow has to have the mic warm before its 3-2-1 (a
    /// learner speaking on the beat must not lose their first word) while the
    /// FILE must start ON the beat — it is both the scored audio and the
    /// attempt the learner plays back, and 2.4s of countdown in front of it is
    /// wrong in both roles. Session activation and file setup are the slow
    /// parts (hundreds of ms); `record()` on a prepared recorder is not.
    @discardableResult
    func prepare(quality: Quality = .sttOptimal) throws -> URL {
        try configureAndPrepare(quality: quality).url
    }

    /// Start capturing on a recorder already built by `prepare`.
    func beginPrepared() throws {
        guard let rec = recorder, !isRecording else { return }
        guard rec.record() else { throw AudioRecorderError.recordFailed }
        isRecording = true
        startMetering()
    }

    /// Starts a new recording. Returns the destination file URL.
    @discardableResult
    func start(quality: Quality = .sttOptimal) throws -> URL {
        let prepared = try configureAndPrepare(quality: quality)
        guard prepared.recorder.record() else { throw AudioRecorderError.recordFailed }
        isRecording = true
        startMetering()
        return prepared.url
    }

    private func configureAndPrepare(
        quality: Quality
    ) throws -> (recorder: AVAudioRecorder, url: URL) {
        if isMonitoring { stopMonitoring() }   // hand the mic over cleanly
        let session = AVAudioSession.sharedInstance()
        // `.measurement` flattens the iOS processing chain so we capture the
        // mic as-is for cloning — important to avoid the "compressed phone
        // call" sound that ElevenLabs IVC otherwise picks up.
        let mode: AVAudioSession.Mode = (quality == .voiceCloneHigh) ? .measurement : .spokenAudio

        // For voice cloning, REFUSE Bluetooth mic. iOS routes Bluetooth mic
        // input over HFP — 8 kHz mono telephony quality. ElevenLabs IVC clones
        // exactly what it hears, so a Bluetooth-captured sample produces a
        // clone that doesn't sound like the speaker at all. Built-in iPhone
        // mic only, and the speaker for output since it never plays back
        // during capture.
        //
        // `.sttOptimal` (shadowing) follows the LEARNER's choice instead
        // (2026-08-15, `MicPreferenceStore`) — by default the worn earphone
        // mic, because the mic at their mouth beats a wider-band mic across
        // the room. Reading the preference HERE rather than taking it as a
        // parameter is deliberate: this recorder runs alongside
        // LiveTranscriber's engine tap on the SAME session and re-sets the
        // category, so if the two ever disagreed this one would silently win.
        let forceBuiltIn = (quality == .voiceCloneHigh) || MicPreferenceStore.forcesBuiltInMic
        let options: AVAudioSession.CategoryOptions = (quality == .voiceCloneHigh)
            ? [.defaultToSpeaker]
            : (forceBuiltIn ? AudioSessionRouting.builtInMicCaptureOptions
                            : AudioSessionRouting.recordOptions)
        try session.setCategory(.playAndRecord, mode: mode, options: options)
        try session.setActive(true)
        if quality == .sttOptimal { AudioSessionRouting.applyOutputRoute(session) }

        if forceBuiltIn { AudioSessionRouting.preferBuiltInMic(session) }

        let url = Self.makeFileURL()
        let settings: [String: Any]
        switch quality {
        case .sttOptimal:
            settings = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
            ]
        case .voiceCloneHigh:
            // 16-bit (not 24-bit): the upload is peak-normalized to 16-bit PCM
            // anyway, and 24-bit pushed ~1 min takes near ElevenLabs' 11 MB
            // limit on the fallback path. 44.1k/16-bit mono is ideal for IVC.
            settings = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
            ]
        }

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        // Creates the file and allocates buffers now, so the caller's
        // `record()` is the cheap part and the file's t=0 is where they said.
        rec.prepareToRecord()

        recorder = rec
        inputDescription = Self.describeInput(session: session)
        return (rec, url)
    }

    /// Human-readable string for the currently-active mic.
    private static func describeInput(session: AVAudioSession) -> String {
        guard let port = session.currentRoute.inputs.first else { return "Unknown input" }
        switch port.portType {
        case .builtInMic:        return "iPhone built-in mic"
        case .bluetoothHFP:      return "Bluetooth (8 kHz — low quality)"
        case .bluetoothA2DP:     return "Bluetooth A2DP"
        case .bluetoothLE:       return "Bluetooth LE"
        case .headsetMic:        return "Wired headset mic"
        case .usbAudio:          return "USB audio"
        case .lineIn:            return "Line in"
        case .airPlay:           return "AirPlay"
        default:                 return port.portName
        }
    }

    // MARK: - Ambient monitoring (quiet-spot finder)

    /// Meters the room WITHOUT keeping audio: an AVAudioEngine input tap
    /// computes true RMS over ~10 ms windows stamped on the sample clock, so
    /// `ambientDBFS`/`echoTailMs` measure the ROOM — not AVAudioRecorder's
    /// meter ballistics (whose own release time used to dominate the clap
    /// tail and read every room, even a closet, as echoey), and not
    /// main-thread timer jitter. Nothing is written to disk.
    ///
    /// Async because session activation talks to audiod (hundreds of ms,
    /// worse on first activation + speaker rerouting) — it runs off the main
    /// actor so the quiet-spot step's transition never blocks on it.
    func startMonitoring() async throws {
        // Never fight a real recording, and never double-start the engine.
        guard recorder == nil, monitorEngine == nil else { return }
        try await Task.detached(priority: .userInitiated) {
            try Self.activateMonitoringSession()
        }.value
        // The spot step may have been left (or a real recording started)
        // while the session spun up — don't start a stale meter.
        guard recorder == nil, monitorEngine == nil, !Task.isCancelled else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { throw AudioRecorderError.recordFailed }

        let clock = FrameClock()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Audio thread: slice the buffer into ~10 ms RMS windows with
            // sample-clock timestamps, then hand the batch to the main actor
            // in one hop. The hop adds latency but never timing error — the
            // timestamps ride along.
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            let base = clock.frames / sampleRate
            clock.frames += Double(n)
            let win = max(1, Int(sampleRate * 0.01))
            var readings: [(db: Float, t: Double)] = []
            var i = 0
            while i < n {
                let count = min(win, n - i)
                var sum: Float = 0
                for j in i..<(i + count) { sum += ch[j] * ch[j] }
                let rms = (sum / Float(count)).squareRoot()
                readings.append((20 * log10(max(rms, 1e-7)),
                                 base + Double(i) / sampleRate))
                i += count
            }
            Task { @MainActor [readings] in
                guard let self, self.isMonitoring else { return }
                for r in readings { self.stepEchoTracker(db: r.db, at: r.t) }
                if let loudest = readings.map(\.db).max() {
                    self.levels = max(0, min(1, (loudest + 60) / 60))
                }
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }

        monitorEngine = engine
        isMonitoring = true
        ambientDBFS = -60
        echoTailMs = nil
        echoPhase = .armed
        lastWindowDB = -60
        inputDescription = Self.describeInput(session: AVAudioSession.sharedInstance())
    }

    /// Category + activation for ambient metering — same capture chain as the
    /// clone recording (.measurement, built-in mic) so the reading predicts
    /// actual take quality. Blocking (audiod round-trips); call OFF the main
    /// actor.
    nonisolated private static func activateMonitoringSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtIn)
        }
    }

    /// Fire-and-forget pre-warm: activate the monitoring session the moment
    /// mic permission lands, so the quiet-spot step that follows opens with
    /// the session already hot and its meter alive almost immediately.
    /// Repeating the calls in `startMonitoring` is fine — reconfiguring an
    /// already-active session is cheap.
    nonisolated static func prewarmMonitoringSession() {
        Task.detached(priority: .userInitiated) {
            try? activateMonitoringSession()
        }
    }

    /// Stops monitoring and tears the engine down. Safe to call anytime.
    func stopMonitoring() {
        guard isMonitoring, let engine = monitorEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        monitorEngine = nil
        isMonitoring = false
        levels = 0
        ambientDBFS = -60
        echoTailMs = nil
        echoPhase = .armed
        lastWindowDB = -60
    }

    /// Stops the recording and returns the final file URL.
    @discardableResult
    func stop() -> URL? {
        guard let rec = recorder else { return nil }
        rec.stop()
        stopMetering()
        isRecording = false
        let url = rec.url
        recorder = nil
        return url
    }

    // MARK: - Levels

    /// Recording meters at 20 Hz (plenty for a level bar). Monitoring runs at
    /// 100 Hz — decay tails are 100–800 ms, so the echo check needs the finer
    /// clock; `levels` still publishes at ~20 Hz to keep SwiftUI churn low.
    private func startMetering(interval: TimeInterval = 0.05) {
        meterTimer?.invalidate()
        meterTick = 0
        meterTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let rec = self.recorder, rec.isRecording else { return }
                rec.updateMeters()
                let power = rec.averagePower(forChannel: 0)            // dBFS, negative
                self.meterTick += 1
                // Publish the fast level at ≤ 20 Hz regardless of poll rate.
                if interval >= 0.05 || self.meterTick % 5 == 0 {
                    self.levels = max(0, min(1, (power + 60) / 60))    // map -60…0 → 0…1
                }
                // Monitoring never runs through this timer anymore (it has
                // its own engine tap) — this path only meters real recordings.
                self.ambientDBFS = self.ambientDBFS * 0.92 + power * 0.08
            }
        }
    }

    /// One 10 ms window of the quiet-spot state machine: keep a slow ambient
    /// baseline while armed, and when a clap fires, time how long its energy
    /// takes to fall 20 dB — the room's echo tail. `t` is sample-clock
    /// seconds from the monitoring tap.
    private func stepEchoTracker(db: Float, at t: Double) {
        defer { lastWindowDB = db }
        switch echoPhase {
        case .armed:
            // A clap is loud AND *sudden* — require a near-instant rise on
            // top of the absolute threshold, so speech, rustling clothes, and
            // closing doors (slow ramps) never start a bogus measurement.
            if db > max(ambientDBFS + 18, -32), db - lastWindowDB >= 15 {
                echoPhase = .tracking(peak: db, peakAt: t)
            } else {
                // Only the armed phase feeds the baseline, so the clap and its
                // tail never contaminate the "how quiet is this room" reading.
                // ~0.6 s time constant at 10 ms windows. Slow-ramp loudness
                // lands here too — it IS ambient noise, and absorbing it
                // raises the clap threshold accordingly.
                ambientDBFS = ambientDBFS * 0.984 + db * 0.016
            }
        case .tracking(let peak, let peakAt):
            if db > peak {
                echoPhase = .tracking(peak: db, peakAt: t)   // still rising
            } else {
                let floorDB = max(peak - 20, ambientDBFS + 6)
                if db <= floorDB {
                    echoTailMs = (t - peakAt) * 1000
                    echoPhase = .cooling(until: t + 0.4)
                } else if t - peakAt > 1.2 {
                    // Never decayed — extremely live room or sustained noise.
                    echoTailMs = 1200
                    echoPhase = .cooling(until: t + 0.4)
                }
            }
        case .cooling(let until):
            if t >= until, db < ambientDBFS + 10 {
                echoPhase = .armed
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        levels = 0
    }

    // MARK: - File path

    private static func makeFileURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return dir.appendingPathComponent("rec-\(ts).wav")
    }
}

enum AudioRecorderError: Error, LocalizedError {
    case recordFailed
    var errorDescription: String? { "Failed to start recording" }
}
