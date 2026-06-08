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

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?

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
        let options: AVAudioSession.CategoryOptions = (quality == .voiceCloneHigh)
            ? [.defaultToSpeaker]
            : [.defaultToSpeaker, .allowBluetooth]
        try session.setCategory(.playAndRecord, mode: mode, options: options)
        try session.setActive(true)

        if quality == .voiceCloneHigh,
           let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
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
            settings = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 24,
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

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let rec = self.recorder, rec.isRecording else { return }
                rec.updateMeters()
                let power = rec.averagePower(forChannel: 0)            // dBFS, negative
                let normalized = max(0, min(1, (power + 60) / 60))     // map -60…0 → 0…1
                self.levels = normalized
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
