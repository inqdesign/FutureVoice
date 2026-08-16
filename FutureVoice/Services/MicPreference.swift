import AVFoundation
import Foundation

/// Which mic records the learner **when a Bluetooth earphone is connected**.
///
/// With nothing connected there is no choice to make — iOS uses the built-in
/// mic either way — so everything here is scoped to the Bluetooth case.
///
/// Neither is simply "better", which is why this is asked rather than
/// inferred:
///
/// - **the phone's mic is the better microphone.** Wideband, multi-mic
///   beamforming, no compression — everything the earphone gives up. Its one
///   weakness is that it is wherever the phone is: on a desk, in a bag,
///   face-down, in a pocket, which the app cannot see.
/// - **the earphone's mic has the better position.** It runs over HFP, which
///   narrows the link to telephone bandwidth (~16 kHz mSBC on modern
///   earphones) and adds the earphone's own aggressive processing — but it is
///   at the learner's mouth regardless of where the phone ended up, and that
///   is what carries it in noise and at distance.
///
/// So the default is the worn mic: it is the one that cannot be undone by
/// where the phone happens to be lying, and a learner whose phone IS in front
/// of them is exactly the person who can tell us so.
enum MicPreference: String, CaseIterable, Identifiable {
    /// Whatever the learner is wearing (default).
    case earphone
    /// The iPhone's own mic, even with earphones connected. Output stays on
    /// hi-fi A2DP in the earphones — only the input moves.
    case phone

    var id: String { rawValue }
}

/// UserDefaults-backed, global across languages and surfaces: this is a fact
/// about the learner's hardware setup, not about what they're studying.
///
/// Deliberately NOT asked before every session. The answer is the same on the
/// second ask as on the first, and Talk's whole habit story is one tap from
/// tapping to talking — a modal in front of that is a tax on the app's most
/// repeated action. So: ask once, on the first mic use with Bluetooth
/// connected, then live in Me → Voice.
enum MicPreferenceStore {

    static let key = "futurevoice.micPreference"
    private static let askedKey = "futurevoice.micPreference.asked"

    static var current: MicPreference {
        get {
            UserDefaults.standard.string(forKey: key)
                .flatMap(MicPreference.init(rawValue:)) ?? .earphone
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// The one thing the audio layer needs to know.
    static var forcesBuiltInMic: Bool { current == .phone }

    /// Whether the learner has been asked (by the sheet) or has visited the
    /// setting. Either counts — both mean the choice is now theirs.
    static var hasChosen: Bool {
        get { UserDefaults.standard.bool(forKey: askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedKey) }
    }

    static func choose(_ preference: MicPreference) {
        current = preference
        hasChosen = true
    }

    /// Ask only when the choice is live: a Bluetooth device is connected AND
    /// we've never asked. Everything else — wired headphones, speaker, a
    /// second session — goes straight through.
    static func shouldAsk() -> Bool {
        !hasChosen && AudioSessionRouting.hasBluetoothOutput()
    }
}
