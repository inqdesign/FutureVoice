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
///
/// Committed text lives in per-segment `chunks`. A committed chunk starts as
/// the segment's last PARTIAL hypothesis (so the UI never loses text), and is
/// upgraded in place when that segment's language-model-rescored FINAL result
/// arrives — partials are systematically worse (soundalike words, unrevised
/// guesses), so every segment ends better than it looked live. Turn-committing
/// callers should prefer `stopAndFinalize()` over `stop()` for the same
/// reason: it waits a beat for the last segment's final pass.
@MainActor
final class LiveTranscriber: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRunning = false
    @Published private(set) var level: Float = 0  // 0…1 RMS for waveform UI

    /// Where the capture of the run that just ended was written — the user's
    /// own audio, for listen-back. Set by `stop()` when the run was started
    /// with `captureToFile: true`; the caller owns (moves/deletes) the file.
    private(set) var lastRecordingURL: URL?

    /// The tail of the CHUNK capture when the run stopped — audio recorded
    /// since the last `rotateCaptureChunk()` (or since start, if none). Set by
    /// every stop path, like `lastRecordingURL`; the caller owns the file.
    /// Usually trailing silence (the caller checks voiced time before using
    /// it), but on a turn that never rotated it holds the whole utterance.
    private(set) var lastChunkRecordingURL: URL?

    /// Word-level audio-time timings from the CURRENT recognition segment.
    /// `startSeconds` is offset into the audio stream of this segment (NOT
    /// wall clock) — pair with `segmentAnchorAt` for absolute time.
    /// Replaces previous wall-clock STT-arrival stamps which were biased by
    /// 200–500 ms of recognizer latency.
    @Published private(set) var currentWordTimings: [WordTimingInfo] = []
    @Published private(set) var segmentAnchorAt: Date?

    /// When the LIVE segment's hypothesis last changed — i.e. the last moment
    /// the recognizer was still catching up with speech that is being spoken.
    ///
    /// Deliberately NOT "when `transcript` last changed". `transcript` is also
    /// rewritten by the late, language-model-rescored FINAL of a segment that
    /// was frozen seconds ago (`handleResult`'s late-callback path) — a
    /// correction of words the user finished saying, carrying no evidence that
    /// they are still talking. Endpointing must not treat that as new speech:
    /// callers hold fire while this is moving, so a rescore landing during the
    /// silence used to restart the settle wait and the learner paid for their
    /// own correction with a longer pause before the answer.
    @Published private(set) var lastLivePartialAt: Date?

    struct WordTimingInfo: Equatable, Hashable {
        var word: String
        var startSeconds: Double   // offset into audio of current segment
        var duration: Double
    }

    /// What the most recent `stopAndFinalize()` actually did. The rescored
    /// FINAL pass either lands before the turn is sent or it doesn't, and until
    /// this existed nothing recorded which — so a turn shipped with the
    /// recognizer's worst hypothesis looked identical to a clean one.
    struct FinalizeWait {
        /// How long the final pass was waited for, in ms.
        var waitedMs: Int
        /// Rotated segments still holding a partial when the turn ended.
        var pendingSegments: Int
        /// True when the deadline hit first — the turn shipped unrescored text.
        var timedOut: Bool
        /// True when waiting actually changed the transcript, i.e. the wait
        /// earned its latency.
        var upgradedText: Bool
    }

    /// Diagnostics from the last `stopAndFinalize()`; nil until one has run.
    private(set) var lastFinalizeWait: FinalizeWait?

    /// Bumped by every `start()`. A detached finalize task from the PREVIOUS
    /// run must not report into — or tear down — the run that replaced it.
    private var runGeneration = 0

    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var currentRequest: SFSpeechAudioBufferRecognitionRequest?
    private var currentTask: SFSpeechRecognitionTask?
    private var taskGeneration = 0
    /// Committed segments in spoken order, keyed by the generation that
    /// produced them so a late-arriving FINAL result can upgrade its own
    /// chunk in place. gen -1 = frozen by a mid-run recognizer reset; no
    /// final will ever cover that text, so it is never replaced.
    private var chunks: [(gen: Int, text: String)] = []
    /// Set while `stopAndFinalize()` waits for the last segment's final pass;
    /// cleared when it arrives (or the wait times out).
    private var finalizingGen: Int?
    /// Generations whose chunk was frozen by the quiet watcher and is STILL
    /// holding a partial hypothesis, waiting for its rescored final to land.
    ///
    /// Without this, `stopAndFinalize` only ever knew about the live segment —
    /// and the quiet watcher (1.5s) rotates before the turn-taking VAD on its
    /// default/long tiers (2.2s/5s), so on those turns the live segment was
    /// empty, the wait was skipped entirely, and whether the turn shipped
    /// rescored or partial text came down to an unobserved race. (Since the
    /// 2026-08 VAD retune the SHORT tier at 1.2s can now fire ahead of a
    /// rotation, putting the live segment back in play — `finalizingGen`
    /// covers that half, this set covers the rotated half, and a turn can
    /// legitimately be waiting on both.)
    private var pendingFinalGens: Set<Int> = []
    private var lastSegmentText = ""
    private var lastChangeTime = Date()
    private var quietWatcher: Task<Void, Never>?
    private let appender = LiveTranscriberAppender()
    private let fluency = FluencyMeter()
    private let recorder = TurnAudioFileWriter()
    /// Second, parallel capture of the SAME buffers, cut into pieces at the
    /// caller's chosen pause boundaries (`rotateCaptureChunk`). Exists so the
    /// audio-grounded transcription can start while the learner is still
    /// talking, chunk by chunk, instead of waiting for the whole turn. The
    /// full-turn file above stays untouched — it remains the listen-back copy
    /// and the whole-turn transcription fallback.
    private let chunkRecorder = TurnAudioFileWriter()
    /// Format the current run's writers were opened with — what a rotation
    /// must reopen the chunk writer with.
    private var captureFormat: AVAudioFormat?
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

    /// Ambient noise estimate the endpointer is currently working against
    /// (0…1 on the mic level curve; ~0.35 ≈ −32.5 dBFS). Telemetry only.
    var ambientNoiseLevel: Float { fluency.noiseFloorLevel() }

    /// Is the mic ACTUALLY open right now? `isRunning` only says the caller
    /// started a run and never stopped it — an interruption (a real phone
    /// call, Siri, an alarm) stops the engine underneath us without going
    /// through `stop()`, leaving a run that reads as live and hears nothing.
    /// Anything recovering a call must test this, not `isRunning`.
    var isEngineRunning: Bool { engine?.isRunning ?? false }

    /// The longest MID-SPEECH silence this run has already survived — a pause
    /// the learner opened and then closed by carrying on talking.
    ///
    /// It is the only hard evidence available about how long THIS person, in
    /// THIS turn, goes quiet while still composing. The endpointer's fixed
    /// tiers are a guess about that; this is a measurement, and a turn that
    /// has already shown a 3 s thinking gap must not be ended on a 1.6 s one.
    /// Trailing silence is deliberately excluded — it is only counted once
    /// speech resumes, so the pause currently in progress can never raise the
    /// bar that is about to end it.
    var observedPauseSeconds: Double { fluency.longestPauseSoFar() }

    /// Whether the current — or, once stopped, the most recent — run actually
    /// got iOS's voice processing unit (see `start(voiceProcessing:)`).
    /// Requested ≠ granted: some routes refuse it, and the engine falls back
    /// to the raw mic. Deliberately NOT cleared by `stop()`, because the turn
    /// telemetry that reports it is assembled after the mic is already down.
    private(set) var voiceProcessingActive = false

    /// How long the partial text may sit unchanged before the segment is
    /// frozen and recognition restarts.
    ///
    /// Every rotation throws away the recognizer's language-model context and
    /// glues the pieces back with a space, so a seam costs both accuracy and
    /// (in Korean) correct spacing. At 1.5s it fired on nearly every turn:
    /// measured `text_quiet_ms` at turn end runs 1.7–2.2s, i.e. the watcher
    /// was chopping the utterance moments before the turn ended anyway, for
    /// no benefit. 2.6s clears the turn-taking tiers (1.2 / 2.2s of true
    /// silence) while still catching the genuinely long mid-turn pause the
    /// watcher exists for.
    private static let quietCommitThreshold: TimeInterval = 2.6

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
    /// - Parameter chunkCapture: additionally keep a SECOND capture of the
    ///   same audio that the caller cuts into pieces at pause boundaries
    ///   (`rotateCaptureChunk`) for incremental transcription. Off by
    ///   default — only the conversation turn pipeline consumes the pieces,
    ///   and an unconsumed chunk file is a disk leak.
    /// - Parameter voiceProcessing: run the mic through iOS's voice processing
    ///   unit (noise suppression + AGC + echo cancellation) — the same block
    ///   Siri and FaceTime use. Both mic surfaces that SCORE (Talk, Shadow)
    ///   now pass true: nothing in either reads absolute amplitude — match
    ///   scores are token-level over the transcript, rhythm comes from STT
    ///   word timings, and the meter's own thresholds adapt to the floor —
    ///   while the room degrades the recognizer that every one of those
    ///   numbers is derived from. The default stays OFF so a future caller
    ///   that genuinely needs the raw signal (the way `AudioSampleQuality`
    ///   does for voice cloning) gets it by not asking.
    func start(locale: String, preferBuiltInMic: Bool = false,
               measurementMode: Bool? = nil,
               contextualStrings: [String] = [],
               captureToFile: Bool = false,
               chunkCapture: Bool = false,
               voiceProcessing: Bool = false) throws {
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
        // iOS's voice processing unit (AEC + noise suppression + AGC). Until
        // 2026-08 nothing in the app used it — every surface tapped the RAW
        // mic — which is why a café or a street cost recognition accuracy
        // twice over:
        //   • the noise went straight into Apple STT *and* into the AAC the
        //     Gemini transcription call re-reads;
        //   • `FluencyMeter`'s noise floor rose with the room, so the user's
        //     voice stopped clearing `noiseFloor + 6 dB`, energy endpointing
        //     never fired, and the turn fell through to ConversationView's 6s
        //     transcript-quiet fallback — the "slow outside" learners report.
        // Suppressing the noise before either consumer sees it fixes both.
        // Echo cancellation is a bonus and only best-effort here: the fluent
        // self plays through a SEPARATE node, so the unit has no guaranteed
        // render reference to subtract. NS and AGC don't depend on that.
        // Mode stays `.default` — `.voiceChat` would also move output into the
        // call-volume domain, and this app's loudness alignment is hard-won.
        var vpActive = false
        if voiceProcessing {
            do {
                try input.setVoiceProcessingEnabled(true)
                vpActive = true
            } catch {
                // Some routes/devices refuse it. Raw mic is a fine fallback —
                // it's exactly what every run did before this existed.
            }
        }
        if vpActive {
            // NOTE (2026-08-18): do NOT connect a silent source to the mixer to
            // feed VPIO's output bus. It was tried, to stop the hundreds of
            // `auou/vpio/appl, render err: -1` the unit logs when only its input
            // is used, and it KILLED THE MIC on Bluetooth: the output format is
            // read before `engine.start()`, when the earphone is still on A2DP,
            // but opening the mic flips the link to HFP at a different rate —
            // so the connection is stale by the time the graph runs, the engine
            // refuses to start, and the retry inherits the same dead node. The
            // call then plays fine (the fluent self has its own engine) while
            // nothing is ever heard. The render errors are noisy but harmless;
            // a working mic is not negotiable.

            // Keep noise suppression (the reason VPIO is here at all) but drop
            // its AGC. AGC rides the level continuously, and the learner HEARS
            // that: their own turn plays back thin and pumping in Practice.
            // Nothing in the app reads absolute mic amplitude — shadow scores
            // are token-level over the transcript, `FluencyMeter`'s thresholds
            // track the floor — so the levelling buys recognition nothing and
            // costs the one recording the learner listens to.
            if #available(iOS 17.0, *) {
                input.isVoiceProcessingAGCEnabled = false
            }
        }
        // AFTER the toggle: the unit re-negotiates the input format (typically
        // to 48 kHz mono float), and a tap installed with the pre-toggle format
        // would throw at runtime.
        let localAppender = self.appender
        let localFluency = self.fluency
        let localRecorder = self.recorder
        let localChunkRecorder = self.chunkRecorder
        fluency.reset()
        lastRecordingURL = nil
        lastChunkRecordingURL = nil
        captureFormat = nil

        // Re-runnable so the VPIO fallback below can rebuild the tap against
        // the format the raw mic hands back.
        let arm: (Bool) -> Void = { [weak self] capture in
            let format = input.outputFormat(forBus: 0)
            let sampleRate = format.sampleRate
            if capture {
                localRecorder.begin(format: format)
                if chunkCapture {
                    localChunkRecorder.begin(format: format)
                    self?.captureFormat = format
                }
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                localAppender.append(buffer)
                localRecorder.append(buffer)
                localChunkRecorder.append(buffer)
                let rms = Self.rms(of: buffer)
                localFluency.feed(level: rms, seconds: Double(buffer.frameLength) / sampleRate)
                Task { @MainActor [weak self] in
                    self?.level = rms
                }
            }
        }

        arm(captureToFile)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            #if DEBUG
            print("🔊 [mic] engine.start failed (vp=\(vpActive ? 1 : 0)): \(error)")
            #endif
            input.removeTap(onBus: 0)
            // The voice processing unit is a whole I/O unit swap; a route that
            // accepted the toggle can still fail to start under it. Losing
            // noise suppression is a bad turn — failing to open the mic at all
            // is a dead call — so retry once on the raw mic.
            guard vpActive else { throw LiveError.engineFailed }
            try? input.setVoiceProcessingEnabled(false)
            vpActive = false
            // Discard the captures opened at the VPIO format — `arm` reopens them.
            if let stale = localRecorder.finish() {
                try? FileManager.default.removeItem(at: stale)
            }
            if let stale = localChunkRecorder.finish() {
                try? FileManager.default.removeItem(at: stale)
            }
            arm(captureToFile)
            engine.prepare()
            do {
                try engine.start()
            } catch {
                #if DEBUG
                print("🔊 [mic] engine.start failed on the raw-mic retry: \(error)")
                #endif
                input.removeTap(onBus: 0)
                throw LiveError.engineFailed
            }
        }
        self.voiceProcessingActive = vpActive
        // The voice processing unit swaps the whole I/O unit on its way in and
        // drops the `.speaker` override set above, so re-assert it now that the
        // engine is up. The mode is left alone — changing it under a running
        // VPIO would fight the unit; playback restores it
        // (`AudioSessionRouting.reassertOutputAfterMic`).
        if vpActive { AudioSessionRouting.applyOutputRoute(session) }
        #if DEBUG
        AudioSessionRouting.debugSnapshot("mic/start vp=\(vpActive ? 1 : 0)")
        // The tap's own format and the port feeding it: "the mic hears nothing"
        // is either a dead graph or a quiet one, and only these two lines (plus
        // `level`) tell them apart.
        let inFormat = input.outputFormat(forBus: 0)
        print("🔊 [mic/format] rate=\(inFormat.sampleRate) ch=\(inFormat.channelCount) " +
              "port=\(session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: "+"))")
        #endif

        self.engine = engine
        self.recognizer = rec
        self.runGeneration += 1
        self.chunks = []
        self.finalizingGen = nil
        self.pendingFinalGens = []
        self.lastFinalizeWait = nil
        self.transcript = ""
        self.lastSegmentText = ""
        self.lastChangeTime = Date()
        self.lastLivePartialAt = nil
        self.level = 0
        self.isRunning = true
        startNewSegment()
        startQuietWatcher()
    }

    /// Close the current chunk capture at a pause boundary and start a fresh
    /// one, returning the closed piece. The caller owns the file. Returns nil
    /// while nothing is being captured. The full-turn capture is unaffected —
    /// both writers keep receiving the same tap buffers.
    ///
    /// Call this only at genuine silence (the caller's endpoint monitor knows)
    /// — a cut mid-word splits that word across two files and neither half
    /// transcribes correctly.
    func rotateCaptureChunk() -> URL? {
        guard isRunning, let format = captureFormat else { return nil }
        let closed = chunkRecorder.finish()
        chunkRecorder.begin(format: format)
        return closed
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
        lastChunkRecordingURL = chunkRecorder.finish()
        currentRequest?.endAudio()
        currentTask?.finish()
        engine = nil
        currentRequest = nil
        currentTask = nil
        recognizer = nil
        finalizingGen = nil
        pendingFinalGens.removeAll()
        level = 0
        return transcript
    }

    /// Like `stop()`, but waits (briefly) for the recognizer's FINAL,
    /// language-model-rescored pass of the last segment before returning.
    /// The live transcript's tail is otherwise the last raw partial — the
    /// worst hypothesis the recognizer ever held. The mic is off from the
    /// first line; only the text quality improves during the wait.
    func stopAndFinalize(timeout: TimeInterval = 0.9) async -> String {
        guard isRunning else { return transcript }
        isRunning = false
        quietWatcher?.cancel()
        quietWatcher = nil
        appender.setRequest(nil)
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        lastRecordingURL = recorder.finish()
        lastChunkRecordingURL = chunkRecorder.finish()
        engine = nil
        level = 0

        // The live segment is worth waiting on only if it holds text. Rotated
        // segments always are: their chunk is frozen at a partial until the
        // final lands. Waiting on BOTH is the whole point — on a 3s/5s-tier
        // turn the live segment is empty and the rotated one is the only place
        // the user's last words live.
        if !lastSegmentText.isEmpty { finalizingGen = taskGeneration }
        currentRequest?.endAudio()

        let startedWaiting = Date()
        let pendingAtStop = pendingFinalGens.count
        let textBefore = transcript
        let deadline = startedWaiting.addingTimeInterval(timeout)
        while finalizingGen != nil || !pendingFinalGens.isEmpty {
            if Date() >= deadline { break }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        lastFinalizeWait = FinalizeWait(
            waitedMs: Int(Date().timeIntervalSince(startedWaiting) * 1000),
            pendingSegments: pendingAtStop,
            timedOut: finalizingGen != nil || !pendingFinalGens.isEmpty,
            upgradedText: transcript != textBefore
        )

        finalizingGen = nil
        pendingFinalGens.removeAll()
        currentTask?.cancel()
        currentRequest = nil
        currentTask = nil
        recognizer = nil
        return transcript
    }

    /// Same rescored FINAL pass as `stopAndFinalize()`, except NOTHING waits
    /// for it. The mic stops and the text we already have is returned on the
    /// spot; when the rescored pass lands (or its deadline passes) `onUpgrade`
    /// fires with the improved transcript.
    ///
    /// Blocking on that pass used to sit in the critical path between "user
    /// stops talking" and "fluent self answers", and it bought nothing the
    /// caller couldn't apply late: the turn on screen is already showing the
    /// live text, and Gemini re-transcribes from the attached audio anyway.
    /// So the improvement now arrives as a quiet in-place edit instead of a
    /// pause. `onUpgrade` is NOT called when the text didn't change, when the
    /// pass timed out, or when a new `start()` has already superseded the run.
    ///
    /// The timeout is generous precisely BECAUSE it costs no wall-clock time.
    func stopAndFinalizeInBackground(
        timeout: TimeInterval = 2.0,
        onUpgrade: @escaping @MainActor (String) -> Void
    ) -> String {
        guard isRunning else { return transcript }
        isRunning = false
        quietWatcher?.cancel()
        quietWatcher = nil
        appender.setRequest(nil)
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        lastRecordingURL = recorder.finish()
        lastChunkRecordingURL = chunkRecorder.finish()
        engine = nil
        level = 0

        // Same rule as `stopAndFinalize`: the live segment is worth a final
        // only when it holds text; rotated segments always are.
        if !lastSegmentText.isEmpty { finalizingGen = taskGeneration }
        currentRequest?.endAudio()

        let textBefore = transcript
        let startedWaiting = Date()
        let pendingAtStop = pendingFinalGens.count
        let myRun = runGeneration
        let deadline = startedWaiting.addingTimeInterval(timeout)

        Task { @MainActor [weak self] in
            while let self, self.runGeneration == myRun,
                  self.finalizingGen != nil || !self.pendingFinalGens.isEmpty {
                if Date() >= deadline { break }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
            guard let self, self.runGeneration == myRun else { return }
            let timedOut = self.finalizingGen != nil || !self.pendingFinalGens.isEmpty
            self.lastFinalizeWait = FinalizeWait(
                waitedMs: Int(Date().timeIntervalSince(startedWaiting) * 1000),
                pendingSegments: pendingAtStop,
                timedOut: timedOut,
                upgradedText: self.transcript != textBefore
            )
            let upgraded = self.transcript
            self.finalizingGen = nil
            self.pendingFinalGens.removeAll()
            self.currentTask?.cancel()
            self.currentRequest = nil
            self.currentTask = nil
            self.recognizer = nil
            if upgraded != textBefore, !upgraded.isEmpty { onUpgrade(upgraded) }
        }

        return textBefore
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
                self?.handleResult(result, error: error, generation: myGen)
            }
        }
    }

    /// - Parameter awaitingFinal: whether this segment's rescored FINAL is
    ///   still to come. True for the quiet watcher, which freezes a PARTIAL and
    ///   relies on the late-final upgrade. False when the final already arrived
    ///   (`result.isFinal`) or never will (error path) — marking those as
    ///   pending would strand `stopAndFinalize` until its deadline waiting for
    ///   a result that is already in hand or gone for good.
    private func commitAndRestart(awaitingFinal: Bool) {
        guard isRunning else { return }
        // What the user has seen becomes this segment's chunk; the next
        // recognition segment starts empty so further partials append.
        if !lastSegmentText.isEmpty {
            chunks.append((gen: taskGeneration, text: lastSegmentText))
            if awaitingFinal { pendingFinalGens.insert(taskGeneration) }
        }
        lastSegmentText = ""
        lastChangeTime = Date()
        let oldReq = currentRequest
        currentTask = nil
        currentRequest = nil
        startNewSegment()
        // endAudio() only — no task.finish(). The old task runs to its
        // natural FINAL result, which arrives late and upgrades the chunk
        // frozen above (partials are systematically worse text).
        oldReq?.endAudio()
    }

    /// Rebuilds the published transcript from committed chunks + the live
    /// segment's current partial.
    private func rebuildTranscript() {
        var parts = chunks.map(\.text)
        parts.append(lastSegmentText)
        transcript = parts.filter { !$0.isEmpty }.joined(separator: " ")
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
                    // Freezes a partial — its final is still owed.
                    self.commitAndRestart(awaitingFinal: true)
                }
            }
        }
    }

    private func handleResult(_ result: SFSpeechRecognitionResult?, error: Error?,
                              generation myGen: Int) {
        // Late callback from an already-committed segment. The only thing we
        // still want from it is the FINAL, language-model-rescored text —
        // strictly better than the partial its chunk was frozen with.
        guard myGen == taskGeneration else {
            if let result, result.isFinal {
                if let idx = chunks.firstIndex(where: { $0.gen == myGen }) {
                    let finalText = result.bestTranscription.formattedString
                    if !finalText.isEmpty { chunks[idx].text = finalText }
                    rebuildTranscript()
                }
                pendingFinalGens.remove(myGen)
            } else if error != nil {
                // Nothing more is coming for this segment; release the wait
                // rather than let it burn the full deadline.
                pendingFinalGens.remove(myGen)
            }
            return
        }

        // Mic already stopped: `stopAndFinalize()` is waiting for the last
        // segment's final pass. Accept exactly that, nothing else.
        if !isRunning {
            guard finalizingGen == myGen else { return }
            if let result, result.isFinal {
                let finalText = result.bestTranscription.formattedString
                if !finalText.isEmpty { lastSegmentText = finalText }
                rebuildTranscript()
                finalizingGen = nil
            } else if error != nil {
                finalizingGen = nil
            }
            return
        }

        if let result = result {
            let segmentText = result.bestTranscription.formattedString

            // SFSpeechRecognizer (especially on iOS 26) occasionally resets
            // its internal segment mid-utterance: bestTranscription starts
            // OVER and the previous text is gone for good. Freeze the old
            // text as a chunk so the user doesn't lose it. Crucially this
            // must NOT fire on an ordinary hypothesis REVISION — partials
            // routinely rewrite and briefly shrink while the recognizer
            // rethinks, and freezing a revision bakes the stale wrong words
            // into the transcript ahead of the corrected ones (phantom /
            // duplicated text the user never said).
            if !lastSegmentText.isEmpty,
               Self.looksLikeSegmentReset(previous: lastSegmentText, current: segmentText) {
                // gen -1: no final result will ever cover this text, so the
                // late-final upgrade path must never touch it.
                chunks.append((gen: -1, text: lastSegmentText))
                lastSegmentText = ""
            }

            if segmentText != lastSegmentText {
                lastChangeTime = Date()
                // The ONLY place the endpointer's settle clock advances: this
                // is the recognizer still trailing live speech. A late rescore
                // of an already-frozen segment goes through the guard above and
                // must leave this untouched (see `lastLivePartialAt`).
                lastLivePartialAt = lastChangeTime
                lastSegmentText = segmentText
            }
            rebuildTranscript()
            currentWordTimings = result.bestTranscription.segments.map {
                WordTimingInfo(
                    word: $0.substring,
                    startSeconds: $0.timestamp,
                    duration: $0.duration
                )
            }
            if result.isFinal {
                // This IS the final — nothing further to wait for.
                commitAndRestart(awaitingFinal: false)
            }
            return
        }

        // Error path: preserve whatever we already showed, then resume. No
        // final will follow an error, so this chunk stays as-is.
        if error != nil {
            commitAndRestart(awaitingFinal: false)
        }
    }

    /// True when a new partial looks like the recognizer STARTED OVER rather
    /// than revised its hypothesis: essentially none of the leading words
    /// survive AND the text got drastically shorter. Erring toward "revision"
    /// is the safe side — a wrongly-taken reset permanently duplicates text,
    /// while a wrongly-taken revision merely re-listens to a few words.
    private static func looksLikeSegmentReset(previous: String, current: String) -> Bool {
        let prevWords = previous.lowercased().split(separator: " ")
        let curWords = current.lowercased().split(separator: " ")
        guard prevWords.count >= 3 else { return false }
        guard curWords.count * 2 <= prevWords.count else { return false }
        let sharedHead = zip(prevWords, curWords).prefix(while: { $0.0 == $0.1 }).count
        return sharedHead == 0
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

    /// Absolute "this is speech" floor — 0.35 on the `rms()` curve is
    /// −32.5 dBFS. A quiet room's ambient sits far below it, so there this
    /// always wins and behavior is exactly what it was before adaptation.
    private let baseVoicedThreshold: Float = 0.35
    /// How far above the measured noise floor a frame must sit to count as
    /// speech. 0.22 on the 0…1 curve ≈ 11 dB.
    ///
    /// Raised from 0.12 (≈6 dB) on 2026-08-18 after a café test where the turn
    /// never ended: 6 dB over a decaying MINIMUM is a bar that other people's
    /// voices clear easily, so the room read as the learner and endpointing
    /// never fired. The physical asymmetry this leans on is large — the
    /// learner's mouth is ~20 cm from the mic and the next table is metres
    /// away, which is 15–20 dB — so 11 dB sits between the two with room on
    /// both sides.
    ///
    /// Quiet rooms are UNAFFECTED by construction: there the absolute floor
    /// (0.35) is the higher of the two and decides alone. This margin only
    /// binds once the room is loud enough to matter, which is exactly where
    /// the old value was failing.
    private let noiseMargin: Float = 0.22
    /// Decaying-minimum noise estimate (classic "minimum statistics"): snaps
    /// DOWN to any quieter frame, creeps UP slowly. Speech cannot drag it up —
    /// even continuous speech has low-energy frames between words — but a room
    /// that genuinely got louder is tracked within a few seconds.
    ///
    /// Why this exists: outdoors and in cafés ambient runs −40…−25 dBFS, i.e.
    /// ABOVE the fixed 0.35 bar. Every frame then read as "the user is still
    /// talking", `lastVoicedAt` never went stale, and the energy-based
    /// endpointing never fired — turns fell through to the 6s transcript-quiet
    /// fallback, which is the "slow outside" the user felt. It also inflated
    /// speakingSeconds/pause stats by counting street noise as speech.
    private var noiseFloor: Float = 0
    private var hasNoiseFloor = false
    private let noiseRisePerSecond: Float = 0.03   // ≈1.5 dB/s

    private var voicedThreshold: Float {
        max(baseVoicedThreshold, noiseFloor + noiseMargin)
    }
    private let minPause = 0.35                  // seconds of silence = one pause

    func reset() {
        lock.lock(); defer { lock.unlock() }
        total = 0; voiced = 0; started = false; silenceRun = 0
        pauseCount = 0; pauseSeconds = 0; longestPause = 0
        lastVoicedAt = nil
        noiseFloor = 0; hasNoiseFloor = false
    }

    func lastVoicedTime() -> Date? {
        lock.lock(); defer { lock.unlock() }
        return lastVoicedAt
    }

    func longestPauseSoFar() -> Double {
        lock.lock(); defer { lock.unlock() }
        return longestPause
    }

    /// Current ambient estimate (0…1 on the `rms()` curve) — telemetry only,
    /// so a "slow turn-taking" report can be read against how loud it actually
    /// was where the user stood.
    func noiseFloorLevel() -> Float {
        lock.lock(); defer { lock.unlock() }
        return noiseFloor
    }

    func feed(level: Float, seconds: Double) {
        guard seconds > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        total += seconds
        // Seed from the first frame (the mic opens before the user starts, so
        // it is normally ambient) — but never ABOVE the old fixed bar. If that
        // frame happens to catch speech, an unclamped seed would push the
        // threshold above the user's own voice and read them as silent. With
        // the clamp the worst case is exactly the pre-adaptation behavior,
        // and the decaying minimum corrects within a few frames.
        if hasNoiseFloor {
            noiseFloor = min(level, noiseFloor + noiseRisePerSecond * Float(seconds))
        } else {
            noiseFloor = min(level, baseVoicedThreshold)
            hasNoiseFloor = true
        }
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
        // 64 kbps, not the 32 it was until 2026-08. This file is not just
        // listen-back material — it is the audio `UtteranceTranscriber` sends
        // to Gemini, i.e. the ground truth the on-device guess gets corrected
        // against. At 32 kbps a quiet room is fine, but in traffic or a café
        // the encoder spends its bits on the noise and smears the speech,
        // degrading exactly the environment we need the audio path for. A
        // 2-minute turn is still well under a megabyte.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 64_000
        ]
        lock.lock(); defer { lock.unlock() }
        file = try? AVAudioFile(forWriting: dest, settings: settings)
        url = file == nil ? nil : dest
    }

    /// Writes INSIDE the lock on purpose. Copying the `AVAudioFile` reference
    /// out and writing unlocked let a tap callback still hold (and write to)
    /// the file after `finish()` released its own reference — so the m4a's
    /// trailing atoms were flushed on the audio thread AFTER the caller had
    /// already read the file back, yielding a truncated, unopenable capture.
    /// That is the audio the Gemini turn attaches, so a lost flush costs the
    /// user their verbatim transcript. Contention is start/finish only.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let f = file else { return }
        try? f.write(from: buffer)
    }

    /// Closes the capture and returns its URL. On return the file is fully
    /// written: releasing the last `AVAudioFile` reference under the lock
    /// finalizes the container synchronously, and no `append` can be in
    /// flight because it holds the same lock.
    func finish() -> URL? {
        lock.lock(); defer { lock.unlock() }
        let u = url
        file = nil    // AVAudioFile closes (and flushes) when released
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
