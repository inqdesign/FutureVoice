import AVFoundation
import Combine
import Foundation

/// One take under the prompter, from the countdown to a saved, scored take.
/// The screen draws `phase`, `cursor` and `level`; everything else is here.
@MainActor
final class SpeechTakeSession: ObservableObject {
    enum Phase: Equatable {
        case ready
        case countdown(Int)
        case recording
        case analyzing
        case done(SpeechTake)
        case failed(String)
    }

    let script: SpeechScript
    let track: SpeechPrompterTrack
    let camera = SpeechCamera()

    @Published private(set) var phase: Phase = .ready
    /// The first display word not yet read.
    @Published private(set) var cursor = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var cameraOn: Bool {
        didSet {
            UserDefaults.standard.set(cameraOn, forKey: Self.cameraKey)
            Task { cameraOn ? await camera.start() : camera.stop() }
        }
    }
    @Published var followVoice: Bool {
        didSet { UserDefaults.standard.set(followVoice, forKey: Self.followKey) }
    }
    /// Fixed-speed multiplier (0.7…1.3), only read when not following.
    @Published var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: Self.speedKey) }
    }
    @Published private(set) var level: Float = 0

    private static let cameraKey = "speech.cameraOn"
    private static let followKey = "speech.followVoice"
    private static let speedKey = "speech.speed"

    private let live = LiveTranscriber()
    private let recorder = AudioRecorder()
    private var bag: Set<AnyCancellable> = []
    private var ticker: Task<Void, Never>?
    private var startedAt: Date?
    private var lastAdvanceAt = Date()
    /// Fractional position for the fixed-speed scroll and the stall nudge.
    private var position: Double = 0
    private var wavURL: URL?
    private var recordingVideo = false
    /// When the screen recording started — it begins before the countdown,
    /// so the voice's start is measured against it. Nil = not recording the
    /// screen (camera off, refused, unavailable).
    private var screenStartedAt: Date?
    private var voiceStartedAt: Date?

    private let native: String
    private let level_: CEFRLevel

    init(script: SpeechScript, native: String, level: CEFRLevel) {
        self.script = script
        self.native = native
        self.level_ = level
        self.track = SpeechPrompterTrack(script: script.body, language: script.language)
        let defaults = UserDefaults.standard
        cameraOn = defaults.object(forKey: Self.cameraKey) as? Bool ?? true
        followVoice = defaults.object(forKey: Self.followKey) as? Bool ?? true
        speed = defaults.object(forKey: Self.speedKey) as? Double ?? 1.0

        live.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] text in self?.heard(text) }
            .store(in: &bag)
        // The camera's state is drawn by the same screen.
        camera.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &bag)
        live.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.level = value }
            .store(in: &bag)
    }

    func appear() async {
        #if DEBUG
        // A capture run shoots the screen, not a camera prompt.
        if DebugCapture.isCapturing { return }
        #endif
        if cameraOn { await camera.start() }
    }

    // MARK: - Record

    func start() async {
        guard phase == .ready || isFailed else { return }
        guard await LiveTranscriber.requestPermissions() else {
            phase = .failed(explain("Microphone and speech recognition are needed to record. Turn them on in Settings."))
            return
        }
        cursor = 0
        position = 0
        elapsed = 0
        // With the camera on, the take is saved as the whole screen —
        // prompter and camera together. Started before the mic, so iOS's
        // permission alert (if it shows) never sits inside the take.
        screenStartedAt = cameraOn && camera.isRunning ? await SpeechScreenRecorder.start() : nil
        do {
            try live.start(locale: script.language,
                           preferBuiltInMic: MicPreferenceStore.forcesBuiltInMic,
                           measurementMode: false,
                           contextualStrings: track.words.prefix(50).map(\.text),
                           voiceProcessing: true)
            wavURL = try recorder.prepare(quality: .sttOptimal)
        } catch {
            live.stop()
            if screenStartedAt != nil { SpeechScreenRecorder.discard(); screenStartedAt = nil }
            phase = .failed(explain("The microphone couldn't start. Try again."))
            return
        }
        for n in [3, 2, 1] {
            phase = .countdown(n)
            HapticEngine.countdownTick()
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard case .countdown = phase else { return }
        }
        try? recorder.beginPrepared()
        voiceStartedAt = Date()
        // Screen refused or unavailable: keep the camera's own take instead.
        recordingVideo = screenStartedAt == nil && cameraOn && camera.startRecording() != nil
        HapticEngine.countdownGo()
        startedAt = Date()
        lastAdvanceAt = Date()
        phase = .recording
        runTicker()
    }

    private var isFailed: Bool { if case .failed = phase { return true } else { return false } }

    private func heard(_ text: String) {
        guard phase == .recording, followVoice else { return }
        let next = track.advance(current: cursor, heard: text)
        if next != cursor {
            cursor = min(next, track.words.count)
            position = Double(cursor)
            lastAdvanceAt = Date()
        }
    }

    private func runTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.phase == .recording else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        let wps = track.wordsPerSecond(language: script.language)
        let voicedRecently = live.lastVoicedAt.map { Date().timeIntervalSince($0) < 0.8 } ?? false

        if !followVoice {
            position += wps * speed * 0.1
            cursor = min(track.words.count, Int(position))
        } else if voicedRecently, Date().timeIntervalSince(lastAdvanceAt) > 3 {
            // Following stalled while they are clearly speaking — the
            // recognizer lost the thread (a name, a kanji it spells another
            // way). Creep forward at reading pace so the line never freezes
            // under them; the next match snaps it back.
            position += wps * 0.1
            let crept = min(track.words.count, Int(position))
            if crept > cursor { cursor = crept }
        }

        // Finished: the last word is reached and they have stopped.
        let quietFor = live.lastVoicedAt.map { Date().timeIntervalSince($0) } ?? elapsed
        if cursor >= track.words.count - 1, quietFor > 2.2, elapsed > 3 {
            Task { await stop() }
            return
        }
        // A take nobody ends still ends.
        if elapsed > Double(script.targetSeconds) * 3 + 60 {
            Task { await stop() }
        }
    }

    // MARK: - Stop and score

    func stop() async {
        guard phase == .recording else { return }
        phase = .analyzing
        ticker?.cancel()
        let duration = elapsed
        let recorded = recorder.stop() ?? wavURL
        let liveText = await live.stopAndFinalize()
        let screenVideo = screenStartedAt != nil ? await SpeechScreenRecorder.stop() : nil
        var leadIn = 0.0
        if let screen = screenStartedAt, let voice = voiceStartedAt { leadIn = voice.timeIntervalSince(screen) }
        screenStartedAt = nil
        let rawVideo = recordingVideo ? await camera.stopRecording() : screenVideo
        recordingVideo = false

        guard let recorded else {
            phase = .failed(explain("The recording couldn't be saved. Try again."))
            return
        }
        let id = UUID()
        let audioName = "take-\(id.uuidString).wav"
        let audioURL = SpeechStore.mediaURL(audioName)
        do {
            try FileManager.default.moveItem(at: recorded, to: audioURL)
        } catch {
            phase = .failed(explain("The recording couldn't be saved. Try again."))
            return
        }

        let envelope = await Task.detached { SpeechAnalyzer.envelope(of: audioURL) }.value
        guard let envelope, envelope.speakingSeconds > 1.5 else {
            try? FileManager.default.removeItem(at: audioURL)
            if let rawVideo { try? FileManager.default.removeItem(at: rawVideo) }
            phase = .failed(explain("We didn't hear you. Check the microphone and try again."))
            return
        }

        let reading = await SpeechReader.read(audioURL: audioURL, liveText: liveText, language: script.language)
        let metrics = SpeechAnalyzer.analyze(script: script.body, transcript: reading.text,
                                             language: script.language, envelope: envelope)

        var videoName: String?
        if let rawVideo {
            let name = "take-\(id.uuidString).mov"
            var url = SpeechStore.mediaURL(name)
            if await SpeechMediaMerger.merge(video: rawVideo, audio: audioURL, to: url,
                                             videoLeadIn: screenVideo != nil ? leadIn : 0) {
                // A camera take is the learner's to keep or save to Photos;
                // it doesn't ride in the device backup at this size.
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? url.setResourceValues(values)
                videoName = name
            }
            try? FileManager.default.removeItem(at: rawVideo)
        }

        var take = SpeechTake(id: id, scriptId: script.id, createdAt: Date(),
                              durationSeconds: duration, audioFilename: audioName,
                              videoFilename: videoName, transcript: reading.text,
                              metrics: metrics, coaching: nil)
        SpeechStore.shared.save(take)
        phase = .done(take)
        Analytics.capture("speech_take", [
            "built_in": script.isBuiltIn,
            "genre": script.genre.rawValue,
            "seconds": Int(duration),
            "overall": metrics.overall,
            "accuracy": metrics.accuracy,
            "camera": videoName != nil,
            "follow": followVoice,
            "audio_grounded": reading.audioGrounded,
        ])

        if let coaching = await SpeechCoach.review(script: script, transcript: reading.text,
                                                   metrics: metrics, native: native, level: level_) {
            take.coaching = coaching
            SpeechStore.shared.save(take)
            if case .done(let shown) = phase, shown.id == take.id { phase = .done(take) }
        }
    }

    /// Back to the start of the script, ready for another take.
    func reset() {
        cursor = 0
        position = 0
        elapsed = 0
        phase = .ready
    }

    /// Leaving mid-take: nothing is kept.
    func tearDown() {
        ticker?.cancel()
        if phase == .recording || isCountdown {
            let url = recorder.stop()
            live.stop()
            if let url { try? FileManager.default.removeItem(at: url) }
            if recordingVideo {
                Task { if let v = await camera.stopRecording() { try? FileManager.default.removeItem(at: v) } }
            }
            if screenStartedAt != nil { SpeechScreenRecorder.discard(); screenStartedAt = nil }
        }
        camera.stop()
    }

    #if DEBUG
    /// Captures only: a take caught mid-read, without a mic.
    func preview(cursor: Int) {
        self.cursor = cursor
        cameraOn = false
        elapsed = 21
        phase = .recording
        // `-speechdemo 1`: words arrive in bursts the way the recognizer
        // delivers them, to watch the prompter's motion without a mic.
        guard UserDefaults.standard.bool(forKey: "speechdemo") else { return }
        Task { [weak self] in
            while let self, self.cursor < self.track.words.count {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 600_000_000...1_400_000_000))
                self.cursor += Int.random(in: 1...4)
            }
        }
    }
    #endif

    private var isCountdown: Bool { if case .countdown = phase { return true } else { return false } }
}
