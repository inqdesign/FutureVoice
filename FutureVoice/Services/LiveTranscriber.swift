import AVFoundation
import Foundation
import Speech

/// Streaming on-device STT — publishes partial transcripts as the user speaks.
/// Used in the conversation loop so the UI can show what's being heard in real
/// time, instead of waiting for a finished recording file.
@MainActor
final class LiveTranscriber: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRunning = false
    @Published private(set) var level: Float = 0  // 0…1 RMS for waveform UI

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    enum LiveError: Error, LocalizedError {
        case unavailable
        case engineFailed
        var errorDescription: String? {
            switch self {
            case .unavailable:   return "Speech recognizer unavailable for this locale"
            case .engineFailed:  return "Audio engine failed to start"
            }
        }
    }

    static func requestPermissions() async -> Bool {
        let speech: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let mic: Bool
        if #available(iOS 17.0, *) {
            mic = await AVAudioApplication.requestRecordPermission()
        } else {
            mic = await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        return speech && mic
    }

    func start(locale: String) throws {
        guard !isRunning else { return }
        let rec = SFSpeechRecognizer(locale: Locale(identifier: locale))
        guard let rec = rec, rec.isAvailable else { throw LiveError.unavailable }
        rec.defaultTaskHint = .dictation

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req, weak self] buffer, _ in
            req?.append(buffer)
            let rms = Self.rms(of: buffer)
            Task { @MainActor in self?.level = rms }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw LiveError.engineFailed
        }

        self.engine = engine
        self.request = req
        self.transcript = ""
        self.level = 0
        self.isRunning = true

        self.task = rec.recognitionTask(with: req) { [weak self] result, _ in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
            }
        }
    }

    /// Stops streaming and returns the latest transcript.
    @discardableResult
    func stop() -> String {
        guard isRunning else { return transcript }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        engine = nil
        request = nil
        task = nil
        isRunning = false
        level = 0
        return transcript
    }

    // MARK: - Level metering

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let v = channelData[i]
            sum += v * v
        }
        let rms = (sum / Float(count)).squareRoot()
        // Map to 0…1 with a gentle compressor (-50dB floor)
        let db = 20 * log10(max(rms, 0.00001))
        let normalized = max(0, min(1, (db + 50) / 50))
        return normalized
    }
}
