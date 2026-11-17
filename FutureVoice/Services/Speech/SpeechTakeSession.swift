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

    @Published private(set) var script: SpeechScript
    @Published private(set) var track: SpeechPrompterTrack
    let camera = SpeechCamera()

    @Published private(set) var phase: Phase = .ready
    /// The first display word not yet read.
    @Published private(set) var cursor = 0
    /// Whole seconds into the take — published once a second, because the
    /// whole take screen redraws on every change and only the timer reads it.
    @Published private(set) var elapsed: TimeInterval = 0
    /// The exact clock, for the take's own logic.
    private var clock: TimeInterval = 0
    /// Set as the take starts (`ceilingSeconds`), read on every tick.
    private var takeCeiling: TimeInterval = .infinity
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
    /// Karaoke (2026-11-13, founder): the prompter moves at the FLUENT
    /// reading's tempo from the reader's first word, and `guide` is the word
    /// they should be saying now. Off by default (a beginner reads at their
    /// own pace); per visit, like `followVoice`. The score is the same
    /// either way.
    @Published var fluentPace = false
    /// The word the fluent reading is on, while `fluentPace` runs.
    @Published private(set) var guide: Int?
    /// The fluent reading has been laid onto the prompter's words.
    @Published private(set) var fluentPaceAvailable = false
    /// Each prompter word's start in the fluent reading, seconds.
    private var guideStarts: [Double?] = []
    /// The take's clock minus the fluent reading's, set at the first word.
    private var guideOrigin: Double?
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
    /// The take's script layout; the movement is filled in when it ends.
    private var prompterBase: SpeechPrompterRecord?
    /// Host-clock seconds when the voice recording began — the same clock
    /// the screen frames are stamped on.
    private var voiceStartHost: Double?
    /// The take is read WHILE it is spoken: at each pause after
    /// `chunkSeconds` the capture is cut and that piece goes to the reader,
    /// so stopping leaves only the last few seconds to read instead of the
    /// whole take (a three-minute file used to be read from scratch after
    /// the reader had already stopped). In order; nil = that piece failed.
    private var chunkReads: [Task<Piece?, Never>] = []

    /// One piece of the take: its words, and how they were pronounced
    /// (`PronunciationAssessor`, scripted against those same words — the
    /// reader's text is the reference, so the assessment scores the sounds
    /// of what was SAID; the script diff is accuracy's job). `pron` is nil
    /// when the piece held no speech or the server did not answer.
    struct Piece {
        let text: String
        let pron: PronunciationResult?
        /// What the piece was judged against (the script span, or the
        /// read-back): `SpeechDelivery` lines Azure's words up with it.
        var reference: String = ""
        /// The read-back lost words Azure heard, and Azure's hearing stands
        /// in for it (`pieceText`).
        var readBackReplaced = false
        /// Where this piece begins in the take (negative: it opened during
        /// the countdown).
        var startMs = 0
        /// The script span was found from the piece's own words, not taken
        /// from the prompter's cursor.
        var placed = false
    }

    /// A piece's words, from two witnesses. The read-back (Gemini) is the
    /// text the take is scored on, but it can come back short: on
    /// 2026-11-07 the founder's take read 139 words where Azure heard 193 —
    /// the last piece and a half missing — so the end of the script counted
    /// as skipped and the coverage scaled every other part down. When Azure
    /// heard the piece and the read-back holds under 70% of its words (or
    /// nothing), Azure's own text is the piece's text. With no Azure text
    /// the read-back stands, nil included.
    ///
    /// Azure's text is a transcript only when its script span COVERED the
    /// audio (2026-11-17, founder's take: "fifty-one to ninety" marked as
    /// "2025"). The span is where the prompter was, not where the voice was,
    /// and for audio the span lacks Azure writes words out of the span:
    /// measured, a piece saying "thousand people, aged fifty-one to ninety"
    /// against a span ending at "aged" came back "1000 people aged people
    /// 2025 in 2025 a nature…". Those words are tagged Insertion: 0 on six
    /// covered readings, 6 to 20 on six uncovered ones. From
    /// `maxInsertionsToTrust` up, Azure's text never stands in.
    nonisolated static func pieceText(readBack: String?, heard: String?, insertions: Int = 0,
                                      language: String) -> (text: String, replaced: Bool)? {
        let read = readBack?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let azure = heard?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !azure.isEmpty else { return readBack.map { ($0, false) } }
        // Nobody read this piece: nil sends the whole file to the reader.
        guard insertions <= maxInsertionsToTrust else { return read.isEmpty ? nil : (readBack ?? read, false) }
        func size(_ s: String) -> Int {
            LanguageCatalog.writesSpaces(language)
                ? s.split(whereSeparator: \.isWhitespace).count
                : s.filter { !$0.isWhitespace && !$0.isPunctuation }.count
        }
        if read.isEmpty || Double(size(read)) < 0.7 * Double(size(azure)) { return (azure, true) }
        return (readBack ?? read, false)
    }
    nonisolated static let maxInsertionsToTrust = 3
    private var lastChunkAt: TimeInterval = 0
    /// The prompter cursor at the last cut: the script from here to the
    /// cursor at the next cut is that piece's reference (`scriptSpan`).
    private var lastCutCursor = 0
    static let chunkSeconds: TimeInterval = 12
    /// A piece is cut at a SENTENCE END once it is `chunkSeconds` long, and
    /// at the next pause whatever the word once it is this long (the
    /// assessment endpoint takes ≤30 s). Whole sentences of the script are
    /// what a piece is judged against (2026-11-03): judged against its own
    /// read-back, a piece whose first word the two readers heard differently
    /// mis-aligned from there and marked eight right words "inserted" at 0.
    static let chunkHardSeconds: TimeInterval = 22

    private let native: String
    private let level_: CEFRLevel

    /// The native reference reading, fetched as the screen opens so it is
    /// there when the take ends (Season 2 scoring only).
    private var referenceTask: Task<SpeechReference?, Never>?
    /// The listening reading's words with its sounds: a sound it says off the
    /// dictionary is never charged (`SpeechReading.fluentLowSounds`).
    private var fluentTask: Task<SpeechListenAudio?, Never>?

    init(script: SpeechScript, native: String, level: CEFRLevel) {
        self.script = script
        self.native = native
        self.level_ = level
        self.track = SpeechPrompterTrack(script: script.body, language: script.language)
        if SpeechReading.isActive(for: script.language) {
            let body = script.body, language = script.language
            referenceTask = Task { await SpeechReferenceService.fetch(text: body, language: language) }
            let listened = script
            fluentTask = Task { await SpeechListenService.reading(listened) }
        }
        let defaults = UserDefaults.standard
        cameraOn = defaults.object(forKey: Self.cameraKey) as? Bool ?? true
        speed = defaults.object(forKey: Self.speedKey) as? Double ?? 1.0
        // Fluent pace: the listening reading's word times laid onto the
        // prompter's words, once the reading has loaded.
        if let task = fluentTask {
            let words = track.words.count
            let body = script.body
            Task { [weak self] in
                guard let reading = await task.value else { return }
                let starts = SpeechListenText.display(body: body, words: reading.words).map { $0.time?.start }
                // Only when the reading lines up word for word with the
                // prompter (spaced scripts split the same way).
                guard starts.count == words, starts.contains(where: { $0 != nil }) else { return }
                self?.guideStarts = starts
                self?.fluentPaceAvailable = true
            }
        }

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
        // A capture run shoots the screen, not a camera prompt —
        // unless `-speechrealcam 1` asks for the real camera (device checks).
        if DebugCapture.isCapturing && !UserDefaults.standard.bool(forKey: "speechrealcam") { return }
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
        takeCeiling = Self.ceilingSeconds(targetSeconds: script.targetSeconds, body: script.body,
                                          language: script.language)
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
            inputPort = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portType.rawValue
            chunkReads = []
            lastChunkAt = 0
            lastCutCursor = 0
            follows = 0
            partials = 0
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
        guide = nil
        guideOrigin = nil
        phase = .recording
        runTicker()
    }

    /// The script was edited from the prompter: read the new text from the
    /// top. Only between takes — the edit sheet can't open mid-take.
    func replaceScript(_ updated: SpeechScript) {
        guard phase == .ready || isFailed else { return }
        script = updated
        track = SpeechPrompterTrack(script: updated.body, language: updated.language)
        reset()
    }

    /// Called by the screen right before a take: how the script is laid out
    /// (nil: no video this take).
    func prepareVideo(_ record: SpeechPrompterRecord?) {
        prompterBase = record
        videoPrepared = record != nil
    }

    private var isFailed: Bool { if case .failed = phase { return true } else { return false } }

    private func heard(_ text: String) {
        guard phase == .recording, followVoice else { return }
        partials += 1
        let next = track.advance(current: cursor, heard: text)
        // The fluent clock starts at the reader's first word: lined up on the
        // word they reached, so it never begins behind them.
        if fluentPace, guideOrigin == nil, next > 0, !guideStarts.isEmpty {
            let reached = min(next, guideStarts.count) - 1
            if let at = guideStarts[...reached].last(where: { $0 != nil }) ?? nil {
                guideOrigin = clock - at
            }
        }
        if next != cursor {
            follows += 1
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

        // Karaoke: the word the fluent reading is on at this moment.
        if fluentPace, let origin = guideOrigin {
            let t = clock - origin
            let at = guideStarts.lastIndex { ($0 ?? .infinity) <= t }
            if at != guide { guide = at }
        }

        // Steady speed: the cursor walks at the planned pace (the prompter
        // itself moves on its own clock; this keeps the auto-stop honest).
        if !followVoice && !holding {
            position += wps * speed * 0.1
            cursor = min(track.words.count, Int(position))
        }

        // How long nobody has been heard — by EITHER witness, the level
        // meter or the recognizer (2026-11-03). The meter alone read the
        // founder's whole take as silence: a phone propped up for the camera
        // sits an arm's length from the mouth, AGC is off for the take, and
        // the meter's floor (−32.5 dBFS) is set for a phone at the ear. With
        // `quietFor` stuck at "forever", every piece was cut at exactly 12.0 s
        // (28 of 28 pieces in the ledger, mid-word) and the take ENDED the
        // instant the prompter reached the second-to-last word — the last
        // words were never recorded, and the result said the last sentence
        // was skipped. `voiceActive` already took both witnesses for the same
        // reason (a reader whose phone sat on a desk); this is the same rule
        // for the cut and the stop.
        let quietFor = quietSeconds ?? clock

        // Cut a piece for the reader at a pause, never mid-word — and at a
        // sentence end while one comes within `chunkHardSeconds`, so the
        // piece's reference is whole script sentences.
        if clock - lastChunkAt >= Self.chunkSeconds, quietFor >= 0.35,
           atSentenceEnd || clock - lastChunkAt >= Self.chunkHardSeconds,
           let piece = live.rotateCaptureChunk() {
            lastChunkAt = clock
            chunkReads.append(readPiece(piece, cursorSpan: scriptSpan(upTo: cursor), cursor: cursor, endedAt: clock))
        }
        // Finished = the LAST word was heard, then a second of quiet. Being
        // ON the last word isn't finished: a breath before it ("…바로 그 첫,
        // 연습입니다") ended the take with the final word unsaid (founder,
        // 2026-10-05). If the recognizer misses the last word, the take still
        // ends — after a longer pause.
        // Held: the reader stopped the text on purpose; nothing ends now.
        if holding { return }
        let lastHeard = cursor >= track.words.count
        let onLast = cursor >= track.words.count - 1
        if (lastHeard && quietFor > 1.0) || (onLast && quietFor > 3.0), clock > 3 {
            Task { await stop() }
            return
        }
        // A take nobody ends still ends.
        if clock > takeCeiling {
            Task { await stop() }
        }
    }

    /// When a take nobody ended gives up: three times the script's length
    /// plus a minute. The length is read off the text as well, because a
    /// script from the tutor, a goal's prep or the news is saved with
    /// `targetSeconds` 0, and those takes were cut at exactly 60 s, mid
    /// sentence (founder, 2026-11-09: 94 of 193 words).
    nonisolated static func ceilingSeconds(targetSeconds: Int, body: String, language: String) -> TimeInterval {
        let length = max(targetSeconds, SpeechLibrary.estimatedSeconds(body, language: language))
        return Double(length) * 3 + 60
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
        // What the level meter alone made of the take — the record that
        // says whether the cut and the stop had a working witness (see
        // `quietSeconds`). Read before the transcriber is torn down.
        let meterVoiced = live.fluencyStats().speakingSeconds
        let liveText = await live.stopAndFinalize()
        if let tail = live.lastChunkRecordingURL {
            chunkReads.append(readPiece(tail, cursorSpan: scriptSpan(upTo: track.words.count),
                                        cursor: track.words.count,
                                        endedAt: startedAt.map { stoppedAt.timeIntervalSince($0) } ?? clock))
        }
        let pieces = chunkReads
        chunkReads = []

        // The video is finished in the background: the result never waits
        // on it.
        let fromCamera = recordingVideo
        let voiceHost = voiceStartHost
        recordingVideo = false
        // (movie, seconds the picture started before the voice, the script's
        // movement)
        let videoStop: Task<(URL, Double, [Double])?, Never> = Task { [composer] in
            guard fromCamera, let r = await composer.finish() else { return nil }
            return (r.url, voiceHost.map { $0 - r.firstFrameHost } ?? 0, r.offsets)
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
        var prons: [PronunciationResult] = []
        var assessed: [SpeechDelivery.Piece] = []
        var readBackFixed = 0
        var placedPieces = 0
        for piece in pieces {
            guard let piece = await piece.value else { texts = []; prons = []; assessed = []; break }
            texts.append(piece.text)
            if piece.readBackReplaced { readBackFixed += 1 }
            if piece.placed { placedPieces += 1 }
            if let pron = piece.pron {
                prons.append(pron)
                assessed.append(.init(reference: piece.reference, result: pron, startMs: piece.startMs))
            }
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
            // A take longer than one assessment is cut into windows here and
            // each is read and assessed on its own, BESIDE the whole read, so
            // the sounds are still heard and the wait is the slower of the two.
            let language = script.language
            let long: Task<[SpeechDelivery.Piece], Never>? = duration > PronunciationAssessor.maxSeconds
                ? Task { await Self.assessInWindows(audioURL: audioURL, language: language) }
                : nil
            let reading = await SpeechReader.read(audioURL: audioURL, liveText: liveText, language: script.language)
            transcript = reading.text
            audioGrounded = reading.audioGrounded
            path = "whole"
            prons = []
            assessed = []
            if let long {
                assessed = await long.value
                prons = assessed.map(\.result)
            } else if reading.audioGrounded {
                let whole = await PronunciationAssessor.assess(
                    audioURL: audioURL, reference: transcript,
                    language: script.language, surface: "speech")
                if let r = whole.result {
                    prons = [r]
                    assessed = [.init(reference: transcript, result: r)]
                }
            }
        }
        let readMs = ms(readStart)
        // The diff is O(script × transcript) — by syllable for Korean, a
        // million cells for a long script — so it runs off the main thread.
        // One number for the take's sounds: each piece's score weighted by
        // how many words it judged. Its own row on the result, and a quarter
        // of `overall` (2026-11-04).
        let pronunciation = Self.pronunciation(of: prons)
        let body = script.body, language = script.language, pronScore = pronunciation?.score
        // How it was delivered (`SpeechDelivery`): recorded on every take,
        // and with Season 2's scoring on, what four of its five parts are.
        let deliveryPieces = assessed
        let delivery = Task.detached {
            SpeechDelivery.measure(deliveryPieces, language: language, audioURL: audioURL)
        }
        var metrics = await Task.detached {
            SpeechAnalyzer.analyze(script: body, transcript: transcript, language: language,
                                   envelope: envelope, pronunciation: pronScore)
        }.value
        // Season 2: compared with a native reading of this script in the
        // reader's gender (`SpeechReading`). Without the reference (offline,
        // the server not ready) the take keeps the scoring it already has.
        if SpeechReading.isActive(for: language) {
            let delivered = await delivery.value
            let refTask = referenceTask
            let flTask = fluentTask
            // THE reference is the one reading the learner hears (karaoke:
            // its tempo, rhythm and pauses are the target), in whatever voice
            // the challenge was given: measured on 138 human readings, the
            // reference's gender moves pauses and rhythm by nothing and
            // speed by ~4 points, with no loss against the experts. A script
            // with no such reading (the learner's own) keeps the pair.
            let fluent = await Self.within(seconds: 20, { await flTask?.value ?? nil })
            let single = fluent.map { SpeechReference(version: 2, male: $0.words, female: $0.words) }
            let paired: SpeechReference? = single == nil
                ? await Self.within(seconds: 45, { await refTask?.value ?? nil }) : nil
            if let reference = single ?? paired,
               var reading = Self.reading(pieces: assessed, reference: reference, script: body,
                                          metrics: metrics, delivery: delivered, fluent: fluent?.words) {
                if let fluent {
                    reading.gender = fluent.gender
                    reading.reference = "listen"
                }
                metrics.reading = reading
                metrics.overall = reading.total
                metrics.scoring = SpeechReading.version
            }
        }

        let take = SpeechTake(id: id, scriptId: script.id, createdAt: Date(),
                              durationSeconds: duration, audioFilename: audioName,
                              videoFilename: nil, transcript: transcript,
                              metrics: metrics, coaching: nil,
                              pronunciationWords: pronunciation?.weakWords,
                              assessments: prons.isEmpty ? nil : prons,
                              assessmentStartsMs: assessed.count == prons.count && !prons.isEmpty
                                  ? assessed.map(\.startMs) : nil,
                              inputPort: inputPort)
        SpeechStore.shared.save(take)
        PronunciationLedger.shared.record(prons, id: id, surface: "speech", language: script.language)
        SyncEngine.noteChanged(.blobSpeechAudio)
        // A saved take is what a Speech block in the routine asks for.
        ActivityEventLog.shared.record(.speech)
        // A challenge's board takes only what the camera recorded; the score
        // goes up, the video and the voice never do.
        if script.isChallenge {
            SpeechChallenges.shared.enter(take: take, script: script, recordedOnCamera: fromCamera)
        }
        #if SPEECH_APP
        // A group board takes every scored take, camera or not.
        if script.isChallenge || SpeechGroups.shared.script(id: script.id) != nil {
            SpeechGroups.shared.record(score: take.metrics.overall, scriptId: script.id)
        }
        #endif
        let resultMs = ms(stoppedAt)
        // Flagged BEFORE the result shows, so it opens on "Preparing your
        // video…" rather than flashing the audio player first.
        if fromCamera { SpeechStore.shared.markVideoPending(id, true) }
        phase = .done(take)

        // Picture and voice, put together behind the result.
        let videoTask = Task {
            defer { SpeechStore.shared.markVideoPending(id, false) }
            guard let (raw, leadIn, offsets) = await videoStop.value else { return false }
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
            // The merge cut any picture before the voice, so the script's
            // movement starts there too.
            var record = self.prompterBase
            record?.offsets = Array(offsets.dropFirst(Int((max(0, leadIn) / SpeechPrompterRecord.step).rounded())))
            let cutFromVoice = Int(max(0, -leadIn) * 1000)
            if let times = SpeechPrompterTrack.wordTimes(of: self.track.words.map(\.text), language: language,
                                                         pieces: deliveryPieces) {
                record?.wordStarts = times.starts.map { $0 - cutFromVoice }
                record?.wordEnds = times.ends.map { $0 - cutFromVoice }
            }
            self.update(id) {
                $0.videoFilename = name
                $0.prompter = record
            }
            // Its iCloud copy, if the learner picked a quality.
            SpeechVideoSync.shared.ensureCopies()
            return true
        }

        let coachStart = Date()
        if let coaching = await SpeechCoach.review(script: script, transcript: transcript,
                                                   metrics: metrics, native: native, level: level_) {
            update(id) { $0.coaching = coaching }
        }
        let coachMs = ms(coachStart)
        let hasVideo = await videoTask.value
        let delivered = await delivery.value
        Analytics.capture("speech_take", [
            "mic": inputPort ?? "unknown",
            "built_in": script.isBuiltIn,
            "challenge": script.isChallenge,
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
            "cursor_end": cursor, "words": track.words.count, "follows": follows, "partials": partials,
            "meter_voiced": Int(meterVoiced),
            "pieces": pieces.count,
            // How many pieces came back with a phoneme assessment, and the
            // take's number — the only record of whether the reader answers.
            "pron_pieces": prons.count,
            "pron": metrics.pronunciation ?? -1,
            // How it was delivered (`SpeechDelivery`, 2026-11-07): where the
            // app's readers stand against the Season 2 calibration. -1 = not
            // measured.
            "prosody": delivered.prosody ?? -1,
            "fluency": delivered.fluency ?? -1,
            "weak_sounds": delivered.weakSounds ?? -1,
            "mid_pauses": delivered.midPauses ?? -1,
            "mid_boundaries": delivered.midBoundaries ?? -1,
            "wpm": delivered.wordsPerMinute ?? -1,
            "monotone_words": delivered.monotoneWords,
            "pitch_range": delivered.pitchRange ?? -1,
            "pitch_sd": delivered.pitchSD ?? -1,
            "scoring": metrics.scoring ?? 0,
            // Pieces whose read-back lost words Azure heard (`pieceText`).
            "readback_fixed": readBackFixed,
            // Pieces whose script span came from their own words (the rest
            // fell back to the prompter's cursor).
            "placed_pieces": placedPieces,
            "read_ms": readMs,
            "result_ms": resultMs,
            "coach_ms": coachMs,
        ])
    }

    /// Whether the word the reader just finished closes a sentence.
    private var atSentenceEnd: Bool {
        cursor > lastCutCursor && track.endsSentence(at: cursor - 1)
    }

    /// The script the prompter walked since the last cut — this piece's
    /// reference — and moves the mark. Two words of overlap at the start:
    /// a prompter a word AHEAD of the voice would otherwise open the next
    /// piece's audio on words its reference no longer has, which is the
    /// mis-alignment above; a word already said in the previous piece is an
    /// omission here, which the marks ignore. Empty when the prompter did
    /// not move (follow off, a lost recognizer), and the reader's own words
    /// stand in.
    private func scriptSpan(upTo end: Int) -> String {
        let hi = min(end, track.words.count)
        guard hi > lastCutCursor else { return "" }
        let lo = max(0, lastCutCursor - 2)
        lastCutCursor = hi
        return Self.spanText(track, lo..<hi, language: script.language)
    }

    /// The script's words in `range` as one text.
    nonisolated static func spanText(_ track: SpeechPrompterTrack, _ range: Range<Int>, language: String) -> String {
        let joiner = LanguageCatalog.writesSpaces(language) ? " " : ""
        // A line break where a paragraph ends, so `SpeechDelivery` knows a
        // paragraph's pause from a sentence's.
        var text = ""
        for (i, w) in track.words[range].enumerated() {
            if i > 0 {
                text += w.paragraph != track.words[range.lowerBound + i - 1].paragraph && !joiner.isEmpty ? "\n" : joiner
            }
            text += w.text
        }
        return text
    }

    /// - Parameter cursorSpan: the script the prompter walked since the last
    ///   cut. Only the fallback: the cursor is where the SCREEN was, and a
    ///   cursor behind the voice had a piece judged against the sentence
    ///   before the one it held (2026-11-17).
    /// - Parameter endedAt: the take's clock when this piece was cut. Its
    ///   start is counted back from there by the file's own length, so the
    ///   time the words are placed at never adds up across pieces.
    private func readPiece(_ url: URL, cursorSpan: String, cursor: Int, endedAt: TimeInterval) -> Task<Piece?, Never> {
        let language = script.language
        let track = track
        let seconds = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        let startMs = Int((endedAt - seconds) * 1000)
        return Task {
            defer { try? FileManager.default.removeItem(at: url) }
            return await Self.judge(url, track: track, language: language,
                                    cursorSpan: cursorSpan, cursor: cursor, startMs: startMs)
        }
    }

    /// One piece, read and judged. The piece is read first, and its own
    /// words say which part of the script it holds: that span is what its
    /// sounds are judged against. Words that are not the script's (the
    /// reader left it) are judged against themselves. Only a piece nobody
    /// could read falls back to where the prompter stood. The assessment
    /// waits for the read-back, which happens while the next piece is still
    /// being spoken. Also what a stored take is scored again with
    /// (`SpeechRescore`), where there is no cursor.
    nonisolated static func judge(_ url: URL, track: SpeechPrompterTrack, language: String,
                                  cursorSpan: String = "", cursor: Int? = nil, startMs: Int) async -> Piece? {
        let readBack = await SpeechReader.readPiece(audioURL: url, language: language)
        let said = readBack?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var reference = cursorSpan
        var placed = false
        if !said.isEmpty {
            if let range = ShadowEngine.scriptRange(of: said, in: track.words.map(\.text),
                                                    language: language, near: cursor) {
                reference = Self.spanText(track, range, language: language)
                placed = true
            } else {
                reference = said
            }
        }
        guard !reference.isEmpty else { return readBack.map { Piece(text: $0, pron: nil) } }
        let result = await PronunciationAssessor.assess(
            audioURL: url, reference: reference, language: language, surface: "speech").result
        guard let piece = Self.pieceText(readBack: readBack, heard: result?.recognized,
                                         insertions: result?.words.filter(\.isInsertion).count ?? 0,
                                         language: language) else { return nil }
        return Piece(text: piece.text, pron: result, reference: reference,
                     readBackReplaced: piece.replaced, startMs: startMs, placed: placed)
    }

    /// A long take's pronunciation when it was read as one file: windows of
    /// ~20 s (`PronunciationAssessor.windows`), each read for its own words
    /// (the scripted reference, as for a live piece) and assessed, all at
    /// once. A window that can't be read or assessed is left out.
    nonisolated private static func assessInWindows(audioURL: URL, language: String) async -> [SpeechDelivery.Piece] {
        guard PronunciationAssessor.supports(language),
              let wav = await Task.detached(operation: { AudioLoudness.wav16kMono(fromFileAt: audioURL) }).value
        else { return [] }
        let windows = PronunciationAssessor.windows(ofWAV: wav)
        // The windows cut the file end to end: 16-bit, 16 kHz, a 44-byte header.
        var starts: [Int] = [], bytes = 0
        for window in windows {
            starts.append(bytes / 32)
            bytes += max(0, window.count - 44)
        }
        let windowStarts = starts
        return await withTaskGroup(of: (Int, SpeechDelivery.Piece?).self) { group in
            for (index, piece) in windows.enumerated() {
                group.addTask {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("pron-\(UUID().uuidString).wav")
                    guard (try? piece.write(to: url)) != nil else { return (index, nil) }
                    defer { try? FileManager.default.removeItem(at: url) }
                    guard let text = await SpeechReader.readPiece(audioURL: url, language: language),
                          !text.isEmpty else { return (index, nil) }
                    let assessed = await PronunciationAssessor.assess(
                        wav: piece, reference: text, language: language, surface: "speech")
                    return (index, assessed.result.map {
                        SpeechDelivery.Piece(reference: text, result: $0, startMs: windowStarts[index])
                    })
                }
            }
            var got: [(Int, SpeechDelivery.Piece)] = []
            for await (index, result) in group { if let result { got.append((index, result)) } }
            return got.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// The take's pronunciation from its pieces: the SOUND score
    /// (`soundScore`) weighted by each piece's judged words, and every
    /// faulted word, worst first. nil when no piece was assessed.
    static func pronunciation(of pieces: [PronunciationResult])
    -> (score: Int, weakWords: [PronunciationResult.Word])? {
        let weighted = pieces.map { (score: $0.soundScore, weight: max(1, $0.judgedWords.count)) }
        let total = weighted.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        let score = weighted.reduce(0) { $0 + $1.score * $1.weight } / total
        let weak = pieces.flatMap(\.weakWords)
            .sorted { ($0.accuracy ?? 0) < ($1.accuracy ?? 0) }
        return (score, Array(weak.prefix(12)))
    }

    /// A take's Season 2 score from its assessed pieces (each piece's words
    /// timed from its own start, so no pause is measured across pieces) and
    /// the reference in the reader's gender, told by the voice's pitch.
    nonisolated static func reading(pieces: [SpeechDelivery.Piece], reference: SpeechReference,
                                    script: String, metrics: SpeechMetrics,
                                    delivery: SpeechDelivery,
                                    fluent: [SpeechReference.Word]? = nil) -> SpeechReadingScore? {
        let scriptTokens = SpeechDelivery.referenceTokens(script)
        let tokens = scriptTokens.map(\.core)
        var take: [(word: String, startMs: Int, endMs: Int, breakAfter: Bool)] = []
        for piece in pieces {
            let words = piece.result.words.filter { !$0.isOmission && $0.durationMs > 0 }
            for (i, w) in words.enumerated() {
                take.append((w.word, w.offsetMs, w.offsetMs + w.durationMs, i == words.count - 1))
            }
        }
        let gender = (delivery.pitchMedianHz ?? 0) > SpeechReading.femaleAboveHz ? "female" : "male"
        let ref = reference.words(for: gender).map { (word: $0.w, startMs: $0.s, endMs: $0.e, breakAfter: false) }
        return SpeechReading.score(
            take: SpeechReading.timeline(words: take, script: tokens),
            reference: SpeechReading.timeline(words: ref, script: tokens),
            script: tokens, stops: scriptTokens.map(\.stop), slips: metrics.slips, scriptTokens: metrics.scriptTokens,
            missed: metrics.missed, soundAccuracy: delivery.soundAccuracy, weakest: delivery.weakest,
            coverage: metrics.coverage ?? 1, gender: gender,
            weakSounds: pieces.isEmpty ? nil
                : SpeechReading.weakSounds(pieces: pieces.map(\.result), script: script, fluent: fluent)
                    .values.reduce(0) { $0 + $1.count })
    }

    /// The value, or nil if it takes longer than `seconds`.
    nonisolated static func within<T: Sendable>(seconds: Double, _ value: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await value() }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
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
        if phase == .recording {
            Analytics.capture("speech_take_cancelled", followFacts().merging(["seconds": Int(clock), "closed": true]) { a, _ in a })
        }
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
        if phase == .recording {
            Analytics.capture("speech_take_cancelled", followFacts().merging(["seconds": Int(clock)]) { a, _ in a })
        }
        discardRecording()
        reset()
    }

    /// Again: this take is dropped and a fresh one counts in right away.
    func restartTake() async {
        cancelTake()
        await start()
    }

    /// The reader is pressing the prompter to hold the steady scroll.
    var holding = false

    /// Seconds since anyone was last heard, by the level meter or by the
    /// recognizer turning sound into new words — whichever is more recent.
    /// Nil until either has heard anything.
    private var quietSeconds: TimeInterval? {
        let now = Date()
        return [live.lastVoicedAt, live.lastLivePartialAt].compactMap { $0 }
            .map { now.timeIntervalSince($0) }.min()
    }

    /// Whether a voice was heard in the last moment — the prompter keeps
    /// flowing while someone is speaking and eases to a stop when they don't.
    var voiceActive: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "speechdemo") { return true }
        #endif
        // Two witnesses, either is enough: the level meter heard a voice, or
        // the recognizer is still turning sound into new words. The meter
        // alone missed a reader whose phone sat on a desk, and the prompter
        // stopped under them.
        let now = Date()
        if let voiced = live.lastVoicedAt, now.timeIntervalSince(voiced) < 1.2 { return true }
        if let partial = live.lastLivePartialAt, now.timeIntervalSince(partial) < 1.5 { return true }
        return false
    }

    /// Follow diagnostics for the take's analytics row: how often the
    /// prompter found the reader, and where it ended.
    private var follows = 0
    /// The mic the take came through, read once the mic is up.
    private var inputPort: String?
    private var partials = 0
    private func followFacts() -> [String: Any] {
        ["words": track.words.count, "cursor_end": cursor, "follows": follows,
         "partials": partials, "heard_chars": live.transcript.count,
         "language": script.language, "follow": followVoice]
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
