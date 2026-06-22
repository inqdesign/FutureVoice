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

    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?
    private var ticker: Timer?

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
            let session = AVAudioSession.sharedInstance()
            if forceSessionReset {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            // `.playAndRecord` (not `.playback`) so a prior recording session's
            // route doesn't strand us on the quiet earpiece. No mic runs here,
            // so `.allowBluetoothA2DP` lets Bluetooth headphones get hi-fi
            // stereo. We then route AFTER activation: headphones win, and we
            // only force the loud bottom speaker when nothing is plugged in.
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: AudioSessionRouting.playbackOptions)
            try session.setActive(true)
            AudioSessionRouting.applyOutputRoute(session)
        }

        // Equalize loudness across voices: IVC clones come back much quieter
        // than premade preset voices (see AudioLoudness). Falls back to the
        // raw data when decoding fails or the level is already on target.
        let playData = AudioLoudness.normalized(data) ?? data

        let p = try AVAudioPlayer(data: playData)
        p.volume = 1.0
        p.delegate = self
        p.prepareToPlay()
        guard p.play() else { throw AudioPlayerError.playFailed }

        self.player = p
        self.completion = completion
        self.isPlaying = true
        self.currentTime = 0
        startTicker()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        stopTicker()
        let done = completion
        completion = nil
        done?()
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player, p.isPlaying else { return }
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
