import Foundation

/// A voice nobody is paying for is PARKED (2026-09-28): the server deletes it
/// from ElevenLabs after 7 days (`park-idle-voices`) and stamps `parked_at` on
/// its row. The account voice ceiling (Pro: 160 for every learner together)
/// was being held by people who had left.
///
/// What the phone does about it, in three rules:
/// - **Nothing already made stops playing.** The id stays in
///   `AppState.voiceCloneId`, because every cache lookup (PhraseAudioStore,
///   the voicemail, a scene line) is keyed by it — nil would hide audio that
///   is sitting on disk, and would walk the learner into re-recording.
/// - **Nothing new is synthesized.** `ElevenLabsClient` refuses a parked id
///   before the network with `.insufficientCredits`, the error every surface
///   already answers with its paywall.
/// - **It comes back by itself** when there is something to spend it with —
///   a subscription, or free minutes left — rebuilt from the recording on the
///   phone (`AppState.refreshParkedVoice`).
///
/// A plain defaults key, not app state: `ElevenLabsClient` is not on the main
/// actor and must be able to ask.
enum VoiceParking {
    private static let key = "futurevoice.parkedVoiceId"

    static var parkedVoiceId: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    static func isParked(_ voiceId: String) -> Bool {
        guard let parked = parkedVoiceId else { return false }
        return parked == voiceId
    }
}
