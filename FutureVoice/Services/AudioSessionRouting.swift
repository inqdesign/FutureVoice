import AVFoundation

/// Centralizes the "speaker vs. headphones" decision so playback and the live
/// transcriber agree on output routing.
///
/// Background: this is a voice app, so the session is `.playAndRecord`. We used
/// to hard-force the loud bottom speaker (`.defaultToSpeaker` +
/// `overrideOutputAudioPort(.speaker)`) to dodge the quiet earpiece route — but
/// that also defeated wired/Bluetooth headphones, which is exactly what most
/// people study with. Instead we now decide AFTER the route resolves: respect
/// any external output, and only snap to the speaker when nothing is plugged in.
enum AudioSessionRouting {

    /// Category options for pure playback (Watch, drills, shadow, standalone
    /// TTS). `.allowBluetoothA2DP` gives hi-fi stereo to Bluetooth headphones
    /// since no mic is in use; no `.defaultToSpeaker` so headphones win.
    static let playbackOptions: AVAudioSession.CategoryOptions =
        [.allowBluetoothA2DP, .duckOthers]

    /// Category options while the mic is live (conversation).
    ///
    /// Includes `.allowBluetooth` (HFP) on purpose: conversation is where
    /// hands-free happens — phone in a pocket, talking through AirPods while
    /// walking. The built-in mic is useless there, so the AirPods mic must
    /// work even though HFP caps the round trip at 8 kHz. The deep-listening
    /// surfaces (Watch/drills) have no mic and stay hi-fi via `playbackOptions`,
    /// so this 8 kHz only touches live back-and-forth, not study playback.
    /// (iOS can't do hi-fi A2DP output AND a Bluetooth mic simultaneously.)
    static let recordOptions: AVAudioSession.CategoryOptions =
        [.allowBluetooth, .allowBluetoothA2DP, .duckOthers]

    /// Options for capture that must use the iPhone's OWN mic (shadowing,
    /// "say it" scoring). No `.allowBluetooth` (HFP), so a connected AirPods
    /// stays on hi-fi A2DP for OUTPUT while input falls to the built-in mic.
    /// Pair with `preferBuiltInMic` after activation. Fixes flaky recognition
    /// caused by the AirPods' 8 kHz HFP mic.
    static let builtInMicCaptureOptions: AVAudioSession.CategoryOptions =
        [.allowBluetoothA2DP, .duckOthers]

    /// Force the device's built-in mic as the input. Call after `setActive`.
    static func preferBuiltInMic(_ session: AVAudioSession = .sharedInstance()) {
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtIn)
        }
    }

    /// Output ports that mean "the user is listening through something other
    /// than the phone's own speakers" — so we must not override to the speaker.
    private static let externalOutputPorts: Set<AVAudioSession.Port> = [
        .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP,
        .usbAudio, .carAudio, .airPlay, .lineOut, .HDMI
    ]

    static func hasExternalOutput(_ session: AVAudioSession = .sharedInstance()) -> Bool {
        session.currentRoute.outputs.contains { externalOutputPorts.contains($0.portType) }
    }

    /// Call right after `setActive(true)`. Snaps to the loud bottom speaker only
    /// when nothing external is connected; otherwise clears any override so the
    /// audio follows the connected headphones.
    static func applyOutputRoute(_ session: AVAudioSession = .sharedInstance()) {
        if hasExternalOutput(session) {
            try? session.overrideOutputAudioPort(.none)
        } else {
            try? session.overrideOutputAudioPort(.speaker)
        }
    }
}
