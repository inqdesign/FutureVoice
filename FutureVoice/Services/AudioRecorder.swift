import AVFoundation
import Foundation

/// Records mic audio to a 16kHz mono PCM WAV file — the format Whisper and
/// ElevenLabs expect. Phase 1 keeps this simple: tap-to-start, tap-to-stop.
/// Phase 2 should add VAD so the user doesn't have to hold a button.
@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var levels: Float = 0   // 0…1, for waveform UI

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?

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
    func start() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let url = Self.makeFileURL()
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
        isRecording = true
        startMetering()
        return url
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
