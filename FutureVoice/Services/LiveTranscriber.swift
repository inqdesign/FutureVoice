import AVFoundation
import Foundation
import Speech

/// Streaming on-device STT — publishes partial transcripts as the user speaks.
///
/// SFSpeechRecognizer auto-finalizes a recognition task after a brief pause
/// (or once the underlying segment grows long enough). Naively that wipes the
/// in-progress UI text when the user pauses and resumes. We work around it by
/// committing the finalized text and immediately starting a fresh recognition
/// segment that keeps consuming the same audio engine tap — the displayed
/// transcript is `committed + currentSegment`, never overwritten.
@MainActor
final class LiveTranscriber: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRunning = false
    @Published private(set) var level: Float = 0  // 0…1 RMS for waveform UI

    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var currentTask: SFSpeechRecognitionTask?
    private var committedText = ""
    private let appender = LiveTranscriberAppender()

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

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let localAppender = self.appender
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            localAppender.append(buffer)
            let rms = Self.rms(of: buffer)
            Task { @MainActor [weak self] in
                self?.level = rms
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw LiveError.engineFailed
        }

        self.engine = engine
        self.recognizer = rec
        self.committedText = ""
        self.transcript = ""
        self.level = 0
        self.isRunning = true
        startNewSegment()
    }

    /// Stops streaming and returns the latest transcript.
    @discardableResult
    func stop() -> String {
        guard isRunning else { return transcript }
        isRunning = false
        appender.setRequest(nil)
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        currentTask?.finish()
        engine = nil
        currentTask = nil
        recognizer = nil
        level = 0
        return transcript
    }

    // MARK: - Internals

    private func startNewSegment() {
        guard isRunning, let recognizer = recognizer else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        if #available(iOS 16.0, *) {
            req.addsPunctuation = true
        }
        appender.setRequest(req)

        currentTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleResult(result, error: error)
            }
        }
    }

    private func handleResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        guard isRunning else { return }

        if let result = result {
            let segmentText = result.bestTranscription.formattedString
            transcript = committedText.isEmpty
                ? segmentText
                : committedText + " " + segmentText

            if result.isFinal {
                // Commit what we've heard so far, then start a fresh recognition
                // segment so subsequent partials append rather than overwrite.
                committedText = transcript
                let oldTask = currentTask
                currentTask = nil
                startNewSegment()
                oldTask?.finish()
            }
            return
        }

        // Error path: just restart the segment so the user can keep speaking.
        if error != nil, isRunning {
            let oldTask = currentTask
            currentTask = nil
            startNewSegment()
            oldTask?.finish()
        }
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
        let db = 20 * log10(max(rms, 0.00001))
        return max(0, min(1, (db + 50) / 50))
    }
}

/// Thread-safe pipe that lets the audio-thread tap append buffers into whichever
/// `SFSpeechAudioBufferRecognitionRequest` is currently active without crossing
/// actor boundaries on the hot path.
private final class LiveTranscriberAppender: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func setRequest(_ req: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request = req
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let req = request
        lock.unlock()
        req?.append(buffer)
    }
}
