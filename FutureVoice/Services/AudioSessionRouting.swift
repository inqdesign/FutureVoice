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

    /// Category options for EVERY live-mic surface (conversation, shadowing).
    ///
    /// Includes `.allowBluetooth` (HFP) on purpose: **whatever the learner is
    /// wearing is the mic**. If AirPods are in, the AirPods mic is the one
    /// pointed at their mouth — the phone's is across the room, in a pocket,
    /// or face-down on a desk. That holds for shadowing exactly as much as for
    /// a call: an attempt captured by a distant built-in mic scores worse than
    /// the same attempt captured at the mouth, and the learner reads that as
    /// the app misjudging them.
    ///
    /// Note what we DON'T do: no `setPreferredInput`. With HFP allowed, iOS
    /// picks the connected earphone mic on its own and falls back to the
    /// built-in when nothing is connected — the exact rule we want, for free.
    ///
    /// The cost is real but bounded: HFP narrows the link to telephone
    /// bandwidth (~16 kHz mSBC on modern earphones — fine for ASR, it's Siri's
    /// path) and drags OUTPUT into the call domain for as long as the mic is
    /// hot. Neither mic surface plays anything while recording, and playback
    /// re-enters through `playbackOptions`, so the narrowband window never
    /// covers audio the learner listens to. The deep-listening surfaces
    /// (Watch/drills/replay) have no mic and stay hi-fi throughout.
    static let recordOptions: AVAudioSession.CategoryOptions =
        [.allowBluetooth, .allowBluetoothA2DP, .duckOthers]

    /// Options for capture that must use the iPhone's OWN mic — **voice
    /// cloning only**. No `.allowBluetooth` (HFP), so a connected AirPods
    /// stays on hi-fi A2DP for OUTPUT while input falls to the built-in mic.
    /// Pair with `preferBuiltInMic` after activation.
    ///
    /// Scoring surfaces deliberately do NOT use this (see `recordOptions`):
    /// cloning is the one case where the 8 kHz HFP mic is disqualifying,
    /// because ElevenLabs IVC reproduces exactly the bandwidth it hears and
    /// the result stops sounding like the speaker at all.
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

    /// A Bluetooth audio device is connected — the only situation where the
    /// mic question (`MicPreference`) has two possible answers.
    ///
    /// Read from the OUTPUT route on purpose: `availableInputs` lists the
    /// earphone's HFP mic only once a category with `.allowBluetooth` is set,
    /// so asking about inputs before configuring a session reports nothing.
    /// The output side shows the device as soon as it connects.
    static func hasBluetoothOutput(_ session: AVAudioSession = .sharedInstance()) -> Bool {
        session.currentRoute.outputs.contains {
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
                || $0.portType == .bluetoothLE
        }
    }

    /// Pre-arm the session for a conversation call, BEFORE the first
    /// fluent-self line plays. The streaming player deliberately never touches
    /// the session (mid-call it must inherit LiveTranscriber's `.playAndRecord`)
    /// — but on the first call of a launch nothing has configured one yet, so
    /// the opener used to play on the default `.soloAmbient` session: silenced
    /// by the ring switch and stuck on default routing. Uses the same
    /// category/options the conversation transcriber sets, so the
    /// `LiveTranscriber.start` that follows changes nothing.
    static func warmUpForConversation() {
        let session = AVAudioSession.sharedInstance()
        // Same options `LiveTranscriber.start` is about to set, including the
        // learner's mic choice — otherwise the opener plays through HFP and
        // the route audibly shifts underneath the first reply.
        let options = MicPreferenceStore.forcesBuiltInMic
            ? builtInMicCaptureOptions
            : recordOptions
        try? session.setCategory(.playAndRecord, mode: .default, options: options)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        applyOutputRoute(session)
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

    /// Extra playback gain (dB) for the CURRENT route.
    ///
    /// On the same pair of earphones the app plays through two different
    /// Bluetooth profiles: a Talk call allows HFP (for the earphone mic), and
    /// HFP runs the earphone's CALL loudness chain; every listening surface
    /// (Watch, drills, shadow, replay) deliberately stays on hi-fi A2DP —
    /// which sits in the quieter MEDIA domain. Identical signal, audibly
    /// different loudness, and no session option can bridge the two domains.
    /// So the A2DP surfaces compensate in the signal instead. Speaker and
    /// wired routes play both kinds of surface identically — no boost.
    /// Compensates the A2DP (media-domain) surfaces against Talk's HFP
    /// call-domain loudness on the same earphones. The earphone mic is
    /// non-negotiable for Talk, so signal gain is the only lever; 9 dB is
    /// as far as it goes before the limiter starts audibly pressing the
    /// voice. The rest of the gap is the user's media-volume slider.
    static let a2dpBoostDB: Float = 9

    static func playbackBoostDB(_ session: AVAudioSession = .sharedInstance()) -> Float {
        session.currentRoute.outputs.contains { $0.portType == .bluetoothA2DP } ? a2dpBoostDB : 0
    }

    #if DEBUG
    /// One console line describing everything that decides loudness at this
    /// moment — category, mode, options, route, and the hardware volume.
    /// Temporary diagnostics for the "Talk is loud, everything else is quiet"
    /// hunt; grep the console for 🔊.
    static func debugSnapshot(_ tag: String) {
        let s = AVAudioSession.sharedInstance()
        let outs = s.currentRoute.outputs.map { "\($0.portType.rawValue)" }.joined(separator: "+")
        let ins = s.currentRoute.inputs.map { "\($0.portType.rawValue)" }.joined(separator: "+")
        print("🔊 [\(tag)] cat=\(s.category.rawValue) mode=\(s.mode.rawValue) " +
              "opts=\(s.categoryOptions.rawValue) out=\(outs) in=\(ins) " +
              "vol=\(String(format: "%.2f", s.outputVolume)) " +
              "gain=\(String(format: "%.2f", s.inputGain))")
    }
    #endif
}
