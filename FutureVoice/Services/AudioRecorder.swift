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

    /// Clap-tail tracker for the echo check (monitoring only).
    private enum EchoPhase {
        case armed                                  // waiting for a transient
        case tracking(peak: Float, peakAt: Date)    // clap detected, watching decay
        case cooling(until: Date)                   // ignore the clap's own settle
    }
    private var echoPhase: EchoPhase = .armed
    private var meterTick = 0

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var monitorURL: URL?

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

    /// Starts a new recording. Returns the destination file URL.
    @discardableResult
    func start(quality: Quality = .sttOptimal) throws -> URL {
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
        // mic only.
        // Both qualities capture through the iPhone's own mic. Clone: AirPods'
        // 8 kHz HFP mic ruins fidelity. STT (shadowing): the same HFP mic makes
        // recognition flaky. `.sttOptimal` keeps `.allowBluetoothA2DP` so a
        // connected AirPods still gets hi-fi playback; clone forces the speaker
        // since it never plays back during capture.
        let options: AVAudioSession.CategoryOptions = (quality == .voiceCloneHigh)
            ? [.defaultToSpeaker]
            : AudioSessionRouting.builtInMicCaptureOptions
        try session.setCategory(.playAndRecord, mode: mode, options: options)
        try session.setActive(true)
        if quality == .sttOptimal { AudioSessionRouting.applyOutputRoute(session) }

        // Force the built-in mic for BOTH: clone fidelity and reliable STT.
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtIn)
        }

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
        guard rec.record() else { throw AudioRecorderError.recordFailed }

        recorder = rec
        isRecording = true
        inputDescription = Self.describeInput(session: session)
        startMetering()
        return url
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

    /// Meters the room WITHOUT keeping audio: records to a scratch file in
    /// caches purely to drive `levels`/`ambientDBFS`, so the user can walk
    /// around and watch the surface settle as they find a quiet spot. The
    /// scratch file is deleted on stop — nothing is retained.
    func startMonitoring() throws {
        guard recorder == nil else { return }   // never fight a real recording
        let session = AVAudioSession.sharedInstance()
        // Same capture chain as the clone recording (.measurement, built-in
        // mic) so the reading predicts actual take quality.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtIn)
        }

        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ambient-monitor.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        guard rec.record() else { throw AudioRecorderError.recordFailed }

        recorder = rec
        monitorURL = url
        isMonitoring = true
        ambientDBFS = -60
        echoTailMs = nil
        echoPhase = .armed
        inputDescription = Self.describeInput(session: session)
        startMetering(interval: 0.01)   // 100 Hz — the echo check needs it
    }

    /// Stops monitoring and deletes the scratch file. Safe to call anytime.
    func stopMonitoring() {
        guard isMonitoring, let rec = recorder else { return }
        rec.stop()
        stopMetering()
        isMonitoring = false
        recorder = nil
        if let url = monitorURL { try? FileManager.default.removeItem(at: url) }
        monitorURL = nil
        ambientDBFS = -60
        echoTailMs = nil
        echoPhase = .armed
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
                if self.isMonitoring {
                    self.stepEchoTracker(power: power)
                } else {
                    self.ambientDBFS = self.ambientDBFS * 0.92 + power * 0.08
                }
            }
        }
    }

    /// One metering tick of the quiet-spot state machine: keep a slow ambient
    /// baseline while armed, and when a clap-like transient fires, time how
    /// long its energy takes to fall 20 dB — the room's echo tail.
    private func stepEchoTracker(power: Float) {
        let now = Date()
        switch echoPhase {
        case .armed:
            if power > max(ambientDBFS + 18, -32) {
                // Transient — start tracking its decay.
                echoPhase = .tracking(peak: power, peakAt: now)
            } else {
                // Only the armed phase feeds the baseline, so the clap and its
                // tail never contaminate the "how quiet is this room" reading.
                // ~0.6 s time constant at 100 Hz.
                ambientDBFS = ambientDBFS * 0.984 + power * 0.016
            }
        case .tracking(let peak, let peakAt):
            if power > peak {
                echoPhase = .tracking(peak: power, peakAt: now)   // still rising
            } else {
                let floorDB = max(peak - 20, ambientDBFS + 6)
                if power <= floorDB {
                    echoTailMs = now.timeIntervalSince(peakAt) * 1000
                    echoPhase = .cooling(until: now.addingTimeInterval(0.4))
                } else if now.timeIntervalSince(peakAt) > 1.2 {
                    // Never decayed — extremely live room or sustained noise.
                    echoTailMs = 1200
                    echoPhase = .cooling(until: now.addingTimeInterval(0.4))
                }
            }
        case .cooling(let until):
            if now >= until, power < ambientDBFS + 10 {
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
