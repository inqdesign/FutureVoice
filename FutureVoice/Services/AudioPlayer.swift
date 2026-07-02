import AVFoundation
import Foundation

/// Plays MP3 audio data returned by ElevenLabs TTS.
/// Phase 1 keeps it dead simple: load full data → play to completion.
/// Phase 2 should consume the streaming TTS endpoint to cut latency.
@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    /// Live playback position in seconds, updated ~30Hz while playing. Used by
    /// karaoke-style shadow UI to highlight the currently-spoken word.
    @Published private(set) var currentTime: TimeInterval = 0
    /// Total length of the loaded audio, available after `play`/`prepare`.
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?
    private var ticker: Timer?
    // Segment / loop playback (timeline player). When `segmentEnd` is set,
    // playback stops (or loops) there instead of running to the file end.
    private var segmentStart: TimeInterval = 0
    private var segmentEnd: TimeInterval?
    private var loopEnabled = false
    private var rate: Float = 1.0

    // Streaming PCM playback (conversation TTS). AVAudioPlayerNode schedules
    // each network chunk as it arrives, so the fluent self starts talking on
    // the FIRST chunk instead of after the whole file downloads.
    private var streamEngine: AVAudioEngine?
    private var streamNode: AVAudioPlayerNode?
    private var streamFormat: AVAudioFormat?
    private var streamCompletion: (() -> Void)?
    private var streamPendingBuffers = 0
    private var streamFinished = false
    // Streaming AGC toward AudioLoudness.targetRMSdBFS. Boost-only (clones
    // are quiet, never over-loud), rate-limited so it can't pump audibly.
    private var streamGain: Float = 1.0
    private var streamVoicedSumSquares: Double = 0
    private var streamVoicedSamples: Int = 0

    /// Plays MP3 data and calls `completion` when playback ends or fails.
    /// - Parameter configureSession: when false, skip the internal `.playback`
    ///   category switch. Use this when the caller is in sync-record mode and
    ///   needs the session to stay in `.playAndRecord` so the mic keeps
    ///   capturing while audio plays.
    /// - Parameter forceSessionReset: when true, briefly deactivate the audio
    ///   session before re-setting the category. iOS sometimes keeps the prior
    ///   route + mode (e.g. `.measurement` from a sync-record run) bleeding
    ///   into the next `.playback` call, which manifests as quiet preview
    ///   audio. Force-reset clears that.
    func play(_ data: Data,
              configureSession: Bool = true,
              forceSessionReset: Bool = false,
              completion: (() -> Void)? = nil) throws {
        if configureSession {
            configureForPlayback(forceSessionReset: forceSessionReset)
        }

        // Equalize loudness across voices: IVC clones come back much quieter
        // than premade preset voices (see AudioLoudness). Falls back to the
        // raw data when decoding fails or the level is already on target.
        let playData = AudioLoudness.normalized(data) ?? data

        let p = try AVAudioPlayer(data: playData)
        p.volume = 1.0
        p.enableRate = true
        p.rate = rate
        p.delegate = self
        p.prepareToPlay()
        guard p.play() else { throw AudioPlayerError.playFailed }

        self.player = p
        self.completion = completion
        self.duration = p.duration
        self.segmentStart = 0
        self.segmentEnd = nil
        self.loopEnabled = false
        self.isPlaying = true
        self.currentTime = 0
        startTicker()
    }

    /// `.playAndRecord` (not `.playback`) so a prior recording session's route
    /// doesn't strand us on the quiet earpiece. No mic runs here, so
    /// `.allowBluetoothA2DP` lets Bluetooth headphones get hi-fi stereo. We
    /// route AFTER activation: headphones win, and we only force the loud
    /// bottom speaker when nothing is plugged in.
    private func configureForPlayback(forceSessionReset: Bool) {
        let session = AVAudioSession.sharedInstance()
        if forceSessionReset {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        try? session.setCategory(.playAndRecord, mode: .default,
                                 options: AudioSessionRouting.playbackOptions)
        try? session.setActive(true)
        AudioSessionRouting.applyOutputRoute(session)
    }

    // MARK: - Timeline / segment playback

    /// Decode audio and make it scrubbable WITHOUT starting playback, so a
    /// timeline UI can show duration and seek before the first play.
    func prepare(_ data: Data, forceSessionReset: Bool = false) {
        configureForPlayback(forceSessionReset: forceSessionReset)
        let playData = AudioLoudness.normalized(data) ?? data
        guard let p = try? AVAudioPlayer(data: playData) else { return }
        p.volume = 1.0
        p.enableRate = true
        p.rate = rate
        p.delegate = self
        p.prepareToPlay()
        self.player = p
        self.completion = nil
        self.duration = p.duration
        self.segmentStart = 0
        self.segmentEnd = nil
        self.loopEnabled = false
        self.isPlaying = false
        self.currentTime = 0
    }

    /// Play a region `[from, to]` (to == nil → to the end), optionally looping
    /// it. Requires a prior `prepare`/`play`. Used by the shadow timeline to
    /// hear just a phrase and repeat it.
    var isLoaded: Bool { player != nil }

    func playSegment(from: TimeInterval, to: TimeInterval?, loop: Bool) {
        guard let p = player else { return }
        // Switch the session back to playback mode (a prior shadow attempt may
        // have left it in `.measurement`, which plays silent) — but withOUT a
        // force-reset, since deactivating the session breaks the already-loaded
        // player so the SECOND tap of play would do nothing.
        configureForPlayback(forceSessionReset: false)
        segmentStart = max(0, min(from, p.duration))
        // Ignore a degenerate selection (start ≈ end) — play to the end instead
        // of looping on a zero-length slice (which sounds like nothing).
        if let to, to > segmentStart + 0.05 {
            segmentEnd = min(to, p.duration)
        } else {
            segmentEnd = nil
        }
        loopEnabled = loop
        p.currentTime = segmentStart
        guard p.play() else { return }
        isPlaying = true
        currentTime = segmentStart
        startTicker()
    }

    /// Update the active loop region WITHOUT restarting playback, so dragging a
    /// selection while it loops adjusts the region live instead of stuttering.
    func updateSegment(from: TimeInterval, to: TimeInterval?) {
        guard let p = player else { return }
        segmentStart = max(0, min(from, p.duration))
        if let to, to > segmentStart + 0.05 {
            segmentEnd = min(to, p.duration)
        } else {
            segmentEnd = nil
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
    }

    func seek(to t: TimeInterval) {
        guard let p = player else { return }
        let clamped = max(0, min(t, p.duration))
        p.currentTime = clamped
        currentTime = clamped
    }

    func setLoopEnabled(_ on: Bool) { loopEnabled = on }

    /// Playback speed (0.5–2.0). Applies live and persists across segment
    /// replays — slowing down is the point for shadowing hard phrases.
    func setRate(_ r: Float) {
        rate = r
        player?.enableRate = true
        player?.rate = r
    }

    func stop() {
        player?.stop()
        player = nil
        teardownStream(fireCompletion: false)
        isPlaying = false
        currentTime = 0
        segmentEnd = nil
        loopEnabled = false
        stopTicker()
        let done = completion
        completion = nil
        done?()
    }

    // MARK: - Streaming PCM playback

    /// Begin a streaming playback session. Chunks arrive via `feedPCMStream`;
    /// call `finishPCMStream` after the last chunk — `completion` fires once
    /// everything scheduled has actually been HEARD (dataPlayedBack), matching
    /// `play(_:completion:)` semantics. Does NOT touch the audio session
    /// (conversation keeps LiveTranscriber's .playAndRecord active).
    func startPCMStream(sampleRate: Double, completion: (() -> Void)? = nil) throws {
        stop()   // clear any AVAudioPlayer/stream leftovers first

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            throw AudioPlayerError.playFailed
        }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        node.play()

        streamEngine = engine
        streamNode = node
        streamFormat = format
        streamCompletion = completion
        streamPendingBuffers = 0
        streamFinished = false
        streamGain = 1.0
        streamVoicedSumSquares = 0
        streamVoicedSamples = 0
        isPlaying = true
    }

    /// Schedule one chunk of 16-bit LE mono PCM. Applies the streaming AGC
    /// (see `updateStreamGain`) and clamps to avoid clipping after boost.
    func feedPCMStream(_ chunk: Data) {
        guard let node = streamNode, let format = streamFormat, !chunk.isEmpty else { return }
        let sampleCount = chunk.count / 2
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(sampleCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        guard let out = buffer.floatChannelData?[0] else { return }

        chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                out[i] = Float(Int16(littleEndian: samples[i])) / 32768.0
            }
        }
        updateStreamGain(samples: out, count: sampleCount)
        if streamGain != 1.0 {
            for i in 0..<sampleCount {
                out[i] = max(-0.985, min(0.985, out[i] * streamGain))
            }
        }

        streamPendingBuffers += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.streamPendingBuffers -= 1
                if self.streamFinished, self.streamPendingBuffers <= 0 {
                    self.teardownStream(fireCompletion: true)
                }
            }
        }
    }

    /// No more chunks are coming. If everything already played, complete now;
    /// otherwise the last buffer's dataPlayedBack callback completes.
    func finishPCMStream() {
        streamFinished = true
        if streamNode != nil, streamPendingBuffers <= 0 {
            teardownStream(fireCompletion: true)
        }
    }

    private func teardownStream(fireCompletion: Bool) {
        guard streamEngine != nil || streamNode != nil else { return }
        streamNode?.stop()
        streamEngine?.stop()
        streamNode = nil
        streamEngine = nil
        streamFormat = nil
        streamPendingBuffers = 0
        streamFinished = false
        isPlaying = false
        let done = streamCompletion
        streamCompletion = nil
        if fireCompletion { done?() }
    }

    /// Boost-only AGC: accumulate RMS over VOICED samples (skips the leading
    /// silence that would otherwise explode the gain estimate), then step the
    /// gain toward `AudioLoudness.targetRMSdBFS` at most ~1.5 dB per chunk so
    /// adaptation is inaudible. Mirrors what `AudioLoudness.normalized` does
    /// offline for the buffered path.
    private func updateStreamGain(samples: UnsafePointer<Float>, count: Int) {
        let voicedFloor: Float = 0.02
        for i in 0..<count {
            let a = abs(samples[i])
            if a > voicedFloor {
                streamVoicedSumSquares += Double(a * a)
                streamVoicedSamples += 1
            }
        }
        // Wait for ~0.15s of actual voice before trusting the estimate.
        guard streamVoicedSamples > 3_000 else { return }
        let rms = Float((streamVoicedSumSquares / Double(streamVoicedSamples)).squareRoot())
        guard rms > 1e-6 else { return }
        let targetLinear = pow(10, AudioLoudness.targetRMSdBFS / 20)
        let desired = max(1.0, min(targetLinear / rms, pow(10, AudioLoudness.maxBoostDB / 20)))
        let maxStep: Float = pow(10, 1.5 / 20)   // ≤1.5 dB per chunk
        if desired > streamGain {
            streamGain = min(desired, streamGain * maxStep)
        } else {
            streamGain = max(desired, streamGain / maxStep)
        }
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player, p.isPlaying else { return }
                // Enforce a selected segment: loop back, or stop at its end.
                if let end = self.segmentEnd, p.currentTime >= end {
                    if self.loopEnabled {
                        p.currentTime = self.segmentStart
                    } else {
                        p.pause()
                        self.isPlaying = false
                        self.currentTime = end
                        self.stopTicker()
                        return
                    }
                } else if self.loopEnabled, self.segmentEnd == nil,
                          p.currentTime >= p.duration - 0.05 {
                    p.currentTime = self.segmentStart   // whole-file loop
                }
                self.currentTime = p.currentTime
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.stop() }
    }
}

enum AudioPlayerError: Error, LocalizedError {
    case playFailed
    var errorDescription: String? { "Failed to start playback" }
}
