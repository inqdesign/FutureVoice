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

    /// Where the capture of the run that just ended was written — the user's
    /// own audio, for listen-back. Set by `stop()` when the run was started
    /// with `captureToFile: true`; the caller owns (moves/deletes) the file.
    private(set) var lastRecordingURL: URL?

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
    private let fluency = FluencyMeter()
    private let recorder = TurnAudioFileWriter()
    /// Domain vocabulary hints applied to every recognition segment —
    /// topic words, names, news terms the user is likely to say. Biases the
    /// recognizer toward them (SFSpeechRecognizer contextualStrings).
    private var contextualStrings: [String] = []

    /// Measured delivery stats (voiced time, pauses, hesitations) for the turn
    /// just recorded — call right after `stop()`.
    func fluencyStats() -> FluencyStats { fluency.snapshot() }

    /// Wall-clock moment the mic last heard VOICED audio (energy above the
    /// fluency meter's voiced threshold). nil until the user first speaks.
    /// This is the endpointing signal for turn-taking: "how long has the user
    /// actually been silent" — as opposed to "how long since the STT partial
    /// last changed", which lags real speech by an unpredictable amount.
    var lastVoicedAt: Date? { fluency.lastVoicedTime() }

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

    /// - Parameter preferBuiltInMic: force the iPhone's own mic regardless of a
    ///   connected AirPods. The AirPods' 8 kHz HFP mic makes recognition
    ///   unreliable AND drags the earphone OUTPUT down to telephone quality,
    ///   so scoring (shadowing, "say it") and conversation both use the
    ///   built-in mic; a connected earphone keeps hi-fi A2DP for output.
    /// - Parameter measurementMode: `.measurement` disables output processing
    ///   — clean for scoring capture, but playback gets noticeably quiet, so
    ///   conversation passes false to keep replies loud. Defaults to
    ///   `preferBuiltInMic` (scoring behavior unchanged).
    /// - Parameter contextualStrings: words/phrases the user is likely to say
    ///   (topic, names, news terms). Passed to every recognition segment.
    /// - Parameter captureToFile: also write the mic audio to a compact AAC
    ///   file (`lastRecordingURL` after `stop()`) so the user can listen back
    ///   to their own turn.
    func start(locale: String, preferBuiltInMic: Bool = false,
               measurementMode: Bool? = nil,
               contextualStrings: [String] = [],
               captureToFile: Bool = false) throws {
        guard !isRunning else { return }
        self.contextualStrings = Array(contextualStrings.prefix(50))
        let rec = SFSpeechRecognizer(locale: Locale(identifier: LanguageCatalog.sttLocale(locale)))
        guard let rec = rec, rec.isAvailable else { throw LiveError.unavailable }
        rec.defaultTaskHint = .dictation

        let session = AVAudioSession.sharedInstance()
        // The avatar's reply (played via AudioPlayer with configureSession=false)
        // inherits THIS session, so route choice here governs conversation
        // output too. Respect headphones instead of force-routing to the
        // speaker. `preferBuiltInMic` keeps input on the reliable built-in
        // mic while a connected earphone stays on hi-fi A2DP for output.
        let options = preferBuiltInMic
            ? AudioSessionRouting.builtInMicCaptureOptions
            : AudioSessionRouting.recordOptions
        // `.measurement` disables iOS output sound processing/gain — great for
        // clean scoring input, but it makes the avatar's reply noticeably
        // QUIET. Scoring keeps it (default); conversation opts out to keep
        // replies at full loudness.
        let useMeasurement = measurementMode ?? preferBuiltInMic
        let mode: AVAudioSession.Mode = useMeasurement ? .measurement : .default
        try session.setCategory(.playAndRecord, mode: mode, options: options)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        AudioSessionRouting.applyOutputRoute(session)
        if preferBuiltInMic { AudioSessionRouting.preferBuiltInMic(session) }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let localAppender = self.appender
        let localFluency = self.fluency
        let localRecorder = self.recorder
        let sampleRate = format.sampleRate
        fluency.reset()
        lastRecordingURL = nil
        if captureToFile { recorder.begin(format: format) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            localAppender.append(buffer)
            localRecorder.append(buffer)
            let rms = Self.rms(of: buffer)
            localFluency.feed(level: rms, seconds: Double(buffer.frameLength) / sampleRate)
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
        lastRecordingURL = recorder.finish()
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
        // Do NOT force on-device recognition. Apple's server model is
        // markedly more accurate than the on-device one — especially for
        // accented, non-native speech, which is this app's entire audience.
        // Leaving the flag off lets the framework use the server when it can
        // and fall back on-device otherwise. Segment restarts (quiet-commit /
        // isFinal) keep each request well under the server's ~1-minute cap,
        // and every feature that records also needs the network for
        // Gemini/TTS anyway, so there is no offline scenario to protect.
        if #available(iOS 16.0, *) {
            req.addsPunctuation = true
        }
        if !contextualStrings.isEmpty {
            req.contextualStrings = contextualStrings
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
/// Measures delivery from the mic energy stream on the audio thread: voiced
/// time, and mid-utterance silences ≥ `minPause` counted as pauses/hesitations.
/// Real fluency evidence (pace + pausing) without any external API.
private final class FluencyMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0.0
    private var voiced = 0.0
    private var started = false
    private var silenceRun = 0.0
    private var pauseCount = 0
    private var pauseSeconds = 0.0
    private var longestPause = 0.0
    private var lastVoicedAt: Date?

    private let voicedThreshold: Float = 0.35   // normalized 0…1 level from rms()
    private let minPause = 0.35                  // seconds of silence = one pause

    func reset() {
        lock.lock(); defer { lock.unlock() }
        total = 0; voiced = 0; started = false; silenceRun = 0
        pauseCount = 0; pauseSeconds = 0; longestPause = 0
        lastVoicedAt = nil
    }

    func lastVoicedTime() -> Date? {
        lock.lock(); defer { lock.unlock() }
        return lastVoicedAt
    }

    func feed(level: Float, seconds: Double) {
        guard seconds > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        total += seconds
        if level >= voicedThreshold {
            // Voiced again — close any qualifying mid-speech silence.
            if started, silenceRun >= minPause {
                pauseCount += 1
                pauseSeconds += silenceRun
                longestPause = max(longestPause, silenceRun)
            }
            silenceRun = 0
            voiced += seconds
            started = true
            lastVoicedAt = Date()
        } else if started {
            silenceRun += seconds   // ignore leading/trailing silence
        }
    }

    func snapshot() -> FluencyStats {
        lock.lock(); defer { lock.unlock() }
        return FluencyStats(speakingSeconds: voiced, totalSeconds: total,
                            pauseCount: pauseCount, pauseSeconds: pauseSeconds,
                            longestPauseSeconds: longestPause)
    }
}

/// Writes the mic tap's buffers to a compact AAC file so the user can listen
/// back to their own turn later. Lock-guarded like the appender — `append`
/// runs on the audio thread; a nil file (capture not requested, or the file
/// failed to open) makes it a cheap no-op.
private final class TurnAudioFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var url: URL?

    func begin(format: AVAudioFormat) {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-turn-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 32_000
        ]
        lock.lock(); defer { lock.unlock() }
        file = try? AVAudioFile(forWriting: dest, settings: settings)
        url = file == nil ? nil : dest
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let f = file; lock.unlock()
        guard let f else { return }
        try? f.write(from: buffer)
    }

    func finish() -> URL? {
        lock.lock(); defer { lock.unlock() }
        let u = url
        file = nil    // AVAudioFile closes when released
        url = nil
        return u
    }
}

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
