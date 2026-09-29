import AVFoundation
import Foundation

/// The app's few UI sounds — today only the weekly test's answer cues.
///
/// Played with `AVAudioPlayer` on the app's own playback session, NOT
/// `AudioServicesPlaySystemSound`: the app-wide session is `.playAndRecord`
/// (every mic surface leaves it that way), and under that category a system
/// sound is routed to the quiet earpiece or dropped outright — on device the
/// cues were simply inaudible (2026-09-23). The route is the one every
/// playback surface uses (`AudioSessionRouting.applyOutputRoute`: headphones
/// win, else the loud bottom speaker), so a cue is heard wherever the fluent
/// self is. That category ignores the silent switch, so the goals sheet's
/// Sounds toggle is the one control.
///
/// The files are synthesized by `scripts/make-ui-sounds.py` — nothing
/// sampled, nothing licensed. Haptics stay in `HapticEngine`; a view fires
/// both, one line each.
@MainActor
enum SoundEffects {
    enum Cue: String, CaseIterable {
        case tap = "test-tap"
        case right = "test-right"
        case wrong = "test-wrong"
        case done = "test-done"
    }

    private static var players: [Cue: AVAudioPlayer] = [:]

    /// Whether cues play at all. The weekly test reads its own setting; a
    /// future surface with a different switch passes its own.
    static func play(_ cue: Cue, enabled: Bool? = nil) {
        guard enabled ?? WeeklyTestSettings.shared.soundsOn, let player = player(cue) else { return }
        let session = AVAudioSession.sharedInstance()
        // Mix, don't duck: a 400 ms cue is no reason to dip someone's music.
        try? session.setCategory(.playAndRecord, mode: .default,
                                 options: [.allowBluetoothA2DP, .mixWithOthers])
        try? session.setActive(true)
        AudioSessionRouting.applyOutputRoute(session)
        player.currentTime = 0
        player.play()
    }

    /// The keyboard's own click, when the OS lets us read it: the sound the
    /// thumb already knows from typing. A synthesized tock never quite
    /// matched it (user, 2026-09-23). Falls back to the bundled file.
    private static let systemKeyClicks = [
        "/System/Library/Audio/UISounds/key_press_click.caf",
        "/System/Library/Audio/UISounds/Tock.caf",
    ]

    private static func player(_ cue: Cue) -> AVAudioPlayer? {
        if let p = players[cue] { return p }
        var url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav")
        if cue == .tap, let system = systemKeyClicks.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            url = URL(fileURLWithPath: system)
        }
        guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.volume = 0.9
        p.prepareToPlay()
        players[cue] = p
        return p
    }
}
