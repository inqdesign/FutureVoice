import AVFoundation
import Foundation
import Speech

/// Streaming on-device STT — publishes partial transcripts as the user speaks.
///
/// SFSpeechRecognizer on iOS 26 often does NOT fire `isFinal` when the user
/// pauses; the next utterance silently starts fresh and the previous text
/// disappears from `bestTranscription.formattedString`. To make the loop feel
/// continuous, we don't depend on isFinal alone. A "quiet watcher" runs in the
/// background and, whenever no partial-result change has come in for ~1.5s,
/// commits the current transcript and restarts the recognition segment. The
/// audio engine tap keeps feeding whichever request is currently active, so
/// the user can keep talking without seeing earlier sentences vanish.
@MainActor
final class LiveTranscriber: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRunning = false
    @Published private(set) var level: Float = 0  // 0…1 RMS for waveform UI

    /// Word-level audio-time timings from the CURRENT recognition segment.
    /// `startSeconds` is offset into the audio stream of this segment (NOT
    /// wall clock) — pair with `segmentAnchorAt` for absolute time.
    /// Replaces previous wall-clock STT-arrival stamps which were biased by
    /// 200–500 ms of recognizer latency.
    @Published private(set) var currentWordTimings: [WordTimingInfo] = []
    @Published private(set) var segmentAnchorAt: Date?

    struct WordTimingInfo: Equatable, Hashable {
        var word: String
        var startSeconds: Double   // offset into audio of current segment
        var duration: Double
    }

    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var currentRequest: SFSpeechAudioBufferRecognitionRequest?
    private var currentTask: SFSpeechRecognitionTask?
    private var taskGeneration = 0
    private var committedText = ""
    private var lastSegmentText = ""
    private var lastChangeTime = Date()
    private var quietWatcher: Task<Void, Never>?
    private let appender = LiveTranscriberAppender()

    private static let quietCommitThreshold: TimeInterval = 1.5

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
        self.lastSegmentText = ""
        self.lastChangeTime = Date()
        self.level = 0
        self.isRunning = true
        startNewSegment()
        startQuietWatcher()
    }

    @discardableResult
    func stop() -> String {
        guard isRunning else { return transcript }
        isRunning = false
        quietWatcher?.cancel()
        quietWatcher = nil
        appender.setRequest(nil)
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        currentRequest?.endAudio()
        currentTask?.finish()
        engine = nil
        currentRequest = nil
        currentTask = nil
        recognizer = nil
        level = 0
        return transcript
    }

    // MARK: - Segment lifecycle

    private func startNewSegment() {
        guard isRunning, let recognizer = recognizer else { return }
        // Anchor wall-clock time when this recognition segment begins. All
        // word timestamps in `currentWordTimings` will be relative to this.
        segmentAnchorAt = Date()
        currentWordTimings = []
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        if #available(iOS 16.0, *) {
            req.addsPunctuation = true
        }
        appender.setRequest(req)
        currentRequest = req

        taskGeneration += 1
        let myGen = taskGeneration
        currentTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Ignore late callbacks from a previous segment.
                guard myGen == self.taskGeneration else { return }
                self.handleResult(result, error: error)
            }
        }
    }

    private func commitAndRestart() {
        guard isRunning else { return }
        // What the user has seen becomes a permanent prefix; the next
        // recognition segment starts empty so further partials append.
        committedText = transcript
        lastSegmentText = ""
        lastChangeTime = Date()
        let oldTask = currentTask
        let oldReq = currentRequest
        currentTask = nil
        currentRequest = nil
        startNewSegment()
        oldReq?.endAudio()
        oldTask?.finish()
    }

    private func startQuietWatcher() {
        quietWatcher?.cancel()
        quietWatcher = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self else { return }
                guard self.isRunning else { return }
                guard !self.lastSegmentText.isEmpty else { continue }
                let quietFor = Date().timeIntervalSince(self.lastChangeTime)
                if quietFor > Self.quietCommitThreshold {
                    self.commitAndRestart()
                }
            }
        }
    }

    private func handleResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        guard isRunning else { return }

        if let result = result {
            let segmentText = result.bestTranscription.formattedString

            // SFSpeechRecognizer (especially on iOS 26) occasionally resets
            // its internal segment mid-utterance: bestTranscription suddenly
            // becomes empty or much shorter than the previous partial. Naive
            // assignment then wipes everything the user already saw. Detect
            // the shrink and treat it as a forced commit — freeze the longer
            // version into committedText, then accept the new short text as
            // the start of a fresh segment.
            let prev = lastSegmentText
            let shrank = segmentText.count + 4 < prev.count
            if shrank && !prev.isEmpty {
                committedText = committedText.isEmpty ? prev : committedText + " " + prev
                lastSegmentText = segmentText
                lastChangeTime = Date()
                transcript = committedText.isEmpty
                    ? segmentText
                    : committedText + (segmentText.isEmpty ? "" : " " + segmentText)
                currentWordTimings = result.bestTranscription.segments.map {
                    WordTimingInfo(word: $0.substring,
                                   startSeconds: $0.timestamp,
                                   duration: $0.duration)
                }
                if result.isFinal { commitAndRestart() }
                return
            }

            if segmentText != lastSegmentText {
                lastChangeTime = Date()
                lastSegmentText = segmentText
            }
            transcript = committedText.isEmpty
                ? segmentText
                : committedText + " " + segmentText
            currentWordTimings = result.bestTranscription.segments.map {
                WordTimingInfo(
                    word: $0.substring,
                    startSeconds: $0.timestamp,
                    duration: $0.duration
                )
            }
            if result.isFinal {
                commitAndRestart()
            }
            return
        }

        // Error path: preserve whatever we already showed, then resume.
        if error != nil {
            commitAndRestart()
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
