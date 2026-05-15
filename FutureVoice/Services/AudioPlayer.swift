import AVFoundation
import Foundation

/// Plays MP3 audio data returned by ElevenLabs TTS.
/// Phase 1 keeps it dead simple: load full data → play to completion.
/// Phase 2 should consume the streaming TTS endpoint to cut latency.
@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?

    /// Plays MP3 data and calls `completion` when playback ends or fails.
    func play(_ data: Data, completion: (() -> Void)? = nil) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)

        let p = try AVAudioPlayer(data: data)
        p.delegate = self
        p.prepareToPlay()
        guard p.play() else { throw AudioPlayerError.playFailed }

        self.player = p
        self.completion = completion
        self.isPlaying = true
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        let done = completion
        completion = nil
        done?()
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
