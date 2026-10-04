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
    /// Whole seconds into the take — published once a second, because the
    /// whole take screen redraws on every change and only the timer reads it.
    @Published private(set) var elapsed: TimeInterval = 0
    /// The exact clock, for the take's own logic.
    private var clock: TimeInterval = 0
    @Published var cameraOn: Bool {
        didSet {
            UserDefaults.standard.set(cameraOn, forKey: Self.cameraKey)
            Task { cameraOn ? await camera.start() : camera.stop() }
        }
    }
    /// Every take starts following the voice; switching to a steady speed
    /// lasts for this visit only (a remembered switch kept reopening the
    /// prompter in the mode the reader had forgotten choosing).
    @Published var followVoice = true
    /// Fixed-speed multiplier (0.7…1.3), only read when not following.
    @Published var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: Self.speedKey) }
    }
    /// The mic level, in its own object: it changes many times a second and
    /// only the mic glyph draws it, so it must not redraw the whole screen.
    let level = SpeechLevel()

    private static let cameraKey = "speech.cameraOn"
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
    /// Draws the take screen into the saved video, frame by frame.
    let composer = SpeechVideoComposer()
    /// The screen handed the composer its layout and script images.
    private var videoPrepared = false
    /// Host-clock seconds when the voice recording began — the same clock
    /// the screen frames are stamped on.
    private var voiceStartHost: Double?
    /// The take is read WHILE it is spoken: at each pause after
    /// `chunkSeconds` the capture is cut and that piece goes to the reader,
    /// so stopping leaves only the last few seconds to read instead of the
    /// whole take (a three-minute file used to be read from scratch after
    /// the reader had already stopped). In order; nil = that piece failed.
    private var chunkReads: [Task<String?, Never>] = []
    private var lastChunkAt: TimeInterval = 0
    static let chunkSeconds: TimeInterval = 12

    private let native: String
    private let level_: CEFRLevel

    init(script: SpeechScript, native: String, level: CEFRLevel) {
        self.script = script
        self.native = native
        self.level_ = level
        self.track = SpeechPrompterTrack(script: script.body, language: script.language)
        let defaults = UserDefaults.standard
        cameraOn = defaults.object(forKey: Self.cameraKey) as? Bool ?? true
        speed = defaults.object(forKey: Self.speedKey) as? Double ?? 1.0

        camera.frameHandler = { [composer] buffer in composer.append(buffer) }

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
            .sink { [weak self] value in self?.level.value = value }
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
        clock = 0
        // "3" goes up FIRST and the mic is set up while it shows: the setup
        // (recognizer + voice processing + recorder session) holds the main
        // thread for a beat, and running it before the count meant a blank
        // pause after the tap. The wait before "2" shrinks by what the setup
        // took, so the count is as long as ever.
        let countStartedAt = Date()
        phase = .countdown(3)
        HapticEngine.countdownTick()
        try? await Task.sleep(for: .milliseconds(30))   // let "3" draw first
        do {
            try live.start(locale: script.language,
                           preferBuiltInMic: MicPreferenceStore.forcesBuiltInMic,
                           measurementMode: false,
                           contextualStrings: track.words.prefix(50).map(\.text),
                           chunkCapture: true,
                           voiceProcessing: true)
            chunkReads = []
            lastChunkAt = 0
            wavURL = try recorder.prepare(quality: .sttOptimal)
        } catch {
            live.stop()
            phase = .failed(explain("The microphone couldn't start. Try again."))
            return
        }
        let setupTook = Date().timeIntervalSince(countStartedAt)
        try? await Task.sleep(for: .seconds(max(0, 0.7 - setupTook)))
        for n in [2, 1] {
            guard case .countdown = phase else { return }
            phase = .countdown(n)
            HapticEngine.countdownTick()
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard case .countdown = phase else { return }
        }
        try? recorder.beginPrepared()
        voiceStartHost = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        // Screen refused or unavailable: keep the camera's own take instead.
        recordingVideo = cameraOn && camera.isRunning && videoPrepared
        if recordingVideo { composer.begin() }
        HapticEngine.countdownGo()
        startedAt = Date()
        lastAdvanceAt = Date()
        phase = .recording
        runTicker()
    }

    /// Called by the screen right before a take: where everything is, and
    /// the script drawn for the video.
    func prepareVideo(layout: SpeechVideoComposer.Layout, column: SpeechVideoComposer.Column?) {
        guard let column else { videoPrepared = false; return }
        composer.prepare(layout: layout, column: column)
        videoPrepared = true
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
        clock = Date().timeIntervalSince(startedAt)
        if clock.rounded(.down) != elapsed { elapsed = clock.rounded(.down) }
        let wps = track.wordsPerSecond(language: script.language)

        // Steady speed: the cursor walks at the planned pace (the prompter
        // itself moves on its own clock; this keeps the auto-stop honest).
        if !followVoice {
            position += wps * speed * 0.1
            cursor = min(track.words.count, Int(position))
        }

        // Finished: the last word is reached and they have stopped.
        let quietFor = live.lastVoicedAt.map { Date().timeIntervalSince($0) } ?? clock

        // Cut a piece for the reader at a pause, never mid-word.
        if clock - lastChunkAt >= Self.chunkSeconds, quietFor >= 0.35,
           let piece = live.rotateCaptureChunk() {
            lastChunkAt = clock
            chunkReads.append(readPiece(piece))
        }
        if cursor >= track.words.count - 1, quietFor > 2.2, clock > 3 {
            Task { await stop() }
            return
        }
        // A take nobody ends still ends.
        if clock > Double(script.targetSeconds) * 3 + 60 {
            Task { await stop() }
        }
    }

    // MARK: - Stop and score

    func stop() async {
        guard phase == .recording else { return }
        phase = .analyzing
        ticker?.cancel()
        let stoppedAt = Date()
        func ms(_ since: Date) -> Int { Int(Date().timeIntervalSince(since) * 1000) }
        let duration = clock
        let recorded = recorder.stop() ?? wavURL
        let liveText = await live.stopAndFinalize()
        if let tail = live.lastChunkRecordingURL { chunkReads.append(readPiece(tail)) }
        let pieces = chunkReads
        chunkReads = []

        // The video is finished in the background: the result never waits
        // on it.
        let fromCamera = recordingVideo
        let voiceHost = voiceStartHost
        recordingVideo = false
        // (movie, seconds the picture started before the voice)
        let videoStop: Task<(URL, Double)?, Never> = Task { [composer] in
            guard fromCamera, let r = await composer.finish() else { return nil }
            return (r.url, voiceHost.map { $0 - r.firstFrameHost } ?? 0)
        }

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
            Task { if let v = await videoStop.value { try? FileManager.default.removeItem(at: v.0) } }
            phase = .failed(explain("We didn't hear you. Check the microphone and try again."))
            return
        }

        // The pieces were read during the take; only the tail is left. Any
        // piece that failed sends the whole file to the reader instead, so a
        // hole is never scored as skipped words.
        let readStart = Date()
        var texts: [String] = []
        for piece in pieces {
            guard let text = await piece.value else { texts = []; break }
            texts.append(text)
        }
        let transcript: String
        let audioGrounded: Bool
        let path: String
        if !pieces.isEmpty, texts.count == pieces.count,
           !texts.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let joiner = LanguageCatalog.writesSpaces(script.language) ? " " : ""
            transcript = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: joiner)
            audioGrounded = true
            path = "pieces"
        } else {
            let reading = await SpeechReader.read(audioURL: audioURL, liveText: liveText, language: script.language)
            transcript = reading.text
            audioGrounded = reading.audioGrounded
            path = "whole"
        }
        let readMs = ms(readStart)
        // The diff is O(script × transcript) — by syllable for Korean, a
        // million cells for a long script — so it runs off the main thread.
        let body = script.body, language = script.language
        let metrics = await Task.detached {
            SpeechAnalyzer.analyze(script: body, transcript: transcript, language: language, envelope: envelope)
        }.value

        let take = SpeechTake(id: id, scriptId: script.id, createdAt: Date(),
                              durationSeconds: duration, audioFilename: audioName,
                              videoFilename: nil, transcript: transcript,
                              metrics: metrics, coaching: nil)
        SpeechStore.shared.save(take)
        let resultMs = ms(stoppedAt)
        // Flagged BEFORE the result shows, so it opens on "Preparing your
        // video…" rather than flashing the audio player first.
        if fromCamera { SpeechStore.shared.markVideoPending(id, true) }
        phase = .done(take)

        // Picture and voice, put together behind the result.
        let videoTask = Task {
            defer { SpeechStore.shared.markVideoPending(id, false) }
            guard let (raw, leadIn) = await videoStop.value else { return false }
            let name = "take-\(id.uuidString).mov"
            var url = SpeechStore.mediaURL(name)
            let merged = await SpeechMediaMerger.merge(video: raw, audio: audioURL, to: url,
                                                       videoLeadIn: leadIn)
            try? FileManager.default.removeItem(at: raw)
            guard merged else { return false }
            // A camera take is the learner's to keep or save to Photos; it
            // doesn't ride in the device backup at this size.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            self.update(id) { $0.videoFilename = name }
            return true
        }

        let coachStart = Date()
        if let coaching = await SpeechCoach.review(script: script, transcript: transcript,
                                                   metrics: metrics, native: native, level: level_) {
            update(id) { $0.coaching = coaching }
        }
        let coachMs = ms(coachStart)
        let hasVideo = await videoTask.value
        Analytics.capture("speech_take", [
            "built_in": script.isBuiltIn,
            "genre": script.genre.rawValue,
            "seconds": Int(duration),
            "overall": metrics.overall,
            "accuracy": metrics.accuracy,
            "camera": hasVideo,
                        "follow": followVoice,
            "audio_grounded": audioGrounded,
            // Where the wait went: stop → result on screen, the reading part
            // of it, and the coach that follows.
            "read_path": path,
            "pieces": pieces.count,
            "read_ms": readMs,
            "result_ms": resultMs,
            "coach_ms": coachMs,
        ])
    }

    private func readPiece(_ url: URL) -> Task<String?, Never> {
        let language = script.language
        return Task {
            defer { try? FileManager.default.removeItem(at: url) }
            return await SpeechReader.readPiece(audioURL: url, language: language)
        }
    }

    /// Applies a change to the stored take and to the one on screen.
    private func update(_ id: UUID, _ change: (inout SpeechTake) -> Void) {
        guard var take = SpeechStore.shared.takes.first(where: { $0.id == id }) else { return }
        change(&take)
        SpeechStore.shared.save(take)
        if case .done(let shown) = phase, shown.id == id { phase = .done(take) }
    }

    /// Back to the start of the script, ready for another take.
    func reset() {
        cursor = 0
        position = 0
        elapsed = 0
        clock = 0
        phase = .ready
    }

    /// Leaving mid-take: nothing is kept.
    func tearDown() {
        discardRecording()
        camera.stop()
    }

    /// Throws away the take in progress — nothing is saved or scored.
    private func discardRecording() {
        ticker?.cancel()
        guard phase == .recording || isCountdown else { return }
        let url = recorder.stop()
        live.stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        chunkReads.forEach { $0.cancel() }
        chunkReads = []
        if recordingVideo { composer.cancel(); recordingVideo = false }
    }

    /// Cancel: this take is dropped and the script is back at the top.
    func cancelTake() {
        discardRecording()
        reset()
    }

    /// Again: this take is dropped and a fresh one counts in right away.
    func restartTake() async {
        cancelTake()
        await start()
    }

    /// Whether a voice was heard in the last moment — the prompter keeps
    /// flowing while someone is speaking and eases to a stop when they don't.
    var voiceActive: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "speechdemo") { return true }
        #endif
        return live.lastVoicedAt.map { Date().timeIntervalSince($0) < 1.2 } ?? false
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

/// The live mic level, observed only by the glyph that shows it.
@MainActor
final class SpeechLevel: ObservableObject {
    @Published var value: Float = 0
}
