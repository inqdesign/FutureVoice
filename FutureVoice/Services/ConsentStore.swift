import Combine
import Foundation

/// The legal gate that stands in front of the voice clone.
///
/// It lives on ONE screen — the `.consent` step of `VoiceCloneOnboardingView`,
/// between the narrative and the mic — whose Next stays dead until both boxes
/// are ticked. There is no age screen of its own: a lone "how old are you?" in
/// front of a language app reads as a form to get past, while the same question
/// beside "here is what happens to your voice" reads as what it is.
///
/// Two SEPARATE facts, though, deliberately not collapsed into one flag:
///
/// - **Age.** ElevenLabs — the sub-processor that actually builds the voice
///   model — forbids making its Services available to anyone under 13 at all,
///   and to 13–17-year-olds without a parent or guardian's consent, and
///   separately forbids passing its Services on to end users "on terms less
///   restrictive or more permissive" than the ones we received them under.
///   There is no in-app way to verify a real parent, so the minimum here is
///   16: clear of the 13–17 consent band, and equal to the GDPR Art. 8 age of
///   digital consent in Germany, where the seller is registered. What's stored
///   is the declaration, never a birthday — collecting a date of birth would
///   mean holding a piece of personal data the app has no other use for.
/// - **Voice.** A model built from a recording of someone's voice is biometric
///   data — GDPR Art. 9 special category, Illinois BIPA "voiceprint", Korean
///   PIPA sensitive information. All three want consent that is *separate*
///   from the general terms, informed about who processes it and for how long,
///   and recorded. So it is its own toggle, above its own plain-language
///   disclosure, and the moment it was given is written down.
///
/// Storage is UserDefaults under `futurevoice.consent.*` — which means
/// `AppState.wipeLocalData()` clears it along with the rest of the account —
/// plus a JSON copy in Documents, which is the retainable written record BIPA
/// asks for and the thing to hand over on a data-access request.
@MainActor
final class ConsentStore: ObservableObject {
    static let shared = ConsentStore()

    /// Minimum age to use the app at all. See the type doc for why 16 and not
    /// 13 or 18 — it is a floor derived from the provider's terms, not a taste.
    static let minimumAge = 16

    /// Bumped when the privacy policy changes materially enough that consent
    /// should be asked again. Stored beside each consent so an old record is
    /// identifiable rather than silently treated as current.
    static let policyVersion = "2026-08-14"

    // MARK: - State

    /// What the age screen stores is a YES, not a birthday. Asking for a date
    /// of birth would collect a piece of personal data we have no other use
    /// for, which is the opposite of what a privacy gate should do — the only
    /// fact needed downstream is "old enough", so that is the only fact kept.
    @Published private(set) var ageConfirmedAt: Date?
    @Published private(set) var voiceConsentAt: Date?

    /// Declared themselves old enough.
    var isAgeVerified: Bool { ageConfirmedAt != nil }
    /// Explicitly agreed to their voice being turned into a voice model.
    var hasVoiceConsent: Bool { voiceConsentAt != nil }

    private enum Keys {
        static let ageConfirmed  = "futurevoice.consent.ageConfirmedAt"
        static let voiceConsent  = "futurevoice.consent.voiceConsentAt"
        static let policy        = "futurevoice.consent.policyVersion"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ageConfirmedAt = defaults.object(forKey: Keys.ageConfirmed) as? Date
        voiceConsentAt = defaults.object(forKey: Keys.voiceConsent) as? Date
    }

    // MARK: - Age

    /// Record the age declaration — a self-declaration, not a proof.
    ///
    /// That is the honest description of any age check an app can perform
    /// without demanding ID, and GDPR Art. 8 asks for "reasonable efforts…
    /// taking into consideration available technology" rather than certainty.
    /// A box the learner has to reach for beats a birthday we would then be
    /// obliged to store, protect and delete.
    ///
    /// There is no "no" to record: someone under the minimum simply leaves the
    /// box unticked and the step's Next never arms. A refusal state would be a
    /// second screen and a second thing to get wrong.
    func confirmAge(now: Date = Date()) {
        guard ageConfirmedAt == nil else { return }
        ageConfirmedAt = now
        defaults.set(now, forKey: Keys.ageConfirmed)
        defaults.set(Self.policyVersion, forKey: Keys.policy)
        writeAuditRecord()
        Analytics.capture("age_declared")
    }

    // MARK: - Voice (biometric) consent

    /// Called the moment the learner taps through the voice-consent step —
    /// before any recording is made, never after.
    func recordVoiceConsent(now: Date = Date()) {
        guard voiceConsentAt == nil else { return }
        voiceConsentAt = now
        defaults.set(now, forKey: Keys.voiceConsent)
        defaults.set(Self.policyVersion, forKey: Keys.policy)
        writeAuditRecord()
        Analytics.capture("voice_consent_given")
    }

    /// Withdrawal has to be as easy as consent (GDPR Art. 7(3)). The caller is
    /// responsible for actually deleting the voice model — this only forgets
    /// the permission, which is what forces the clone flow to ask again.
    func withdrawVoiceConsent() {
        voiceConsentAt = nil
        defaults.removeObject(forKey: Keys.voiceConsent)
        writeAuditRecord()
        Analytics.capture("voice_consent_withdrawn")
    }

    /// Forget everything. Called from `AppState.wipeLocalData()`: that clears
    /// the `futurevoice.*` defaults and the Documents copy, but this object is
    /// a singleton whose published values would otherwise stay warm until the
    /// next launch — and a warm `isAgeVerified` would wave the NEXT person
    /// who signs in on this phone straight past the gate.
    func reset() {
        ageConfirmedAt = nil
        voiceConsentAt = nil
        for key in [Keys.ageConfirmed, Keys.voiceConsent, Keys.policy] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Written record

    /// A snapshot BIPA-style retention can point at, and the thing to export
    /// on a subject-access request. Best-effort: the UserDefaults copy above is
    /// what the app actually reads, so a failed write never blocks a learner.
    private func writeAuditRecord() {
        struct Record: Codable {
            let ageConfirmedAt: Date?
            let voiceConsentAt: Date?
            let minimumAge: Int
            let policyVersion: String
        }
        let record = Record(ageConfirmedAt: ageConfirmedAt,
                            voiceConsentAt: voiceConsentAt,
                            minimumAge: Self.minimumAge,
                            policyVersion: Self.policyVersion)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record),
              let docs = FileManager.default
                  .urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        try? data.write(to: docs.appendingPathComponent("consent.json"), options: .atomic)
    }

    // MARK: - Policy links

    /// The privacy policy, in a language the reader can actually read — a
    /// policy you can't parse isn't disclosure. Follows the device language
    /// rather than the app's target-language chrome, same rule PaywallView uses.
    static var privacyURL: URL {
        let korean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
        return URL(string: korean ? "https://nawana.app/privacy-ko.html"
                                  : "https://nawana.app/privacy.html")!
    }

    /// Where a learner writes to if the age screen was answered wrongly, or to
    /// ask for their consent record.
    static let contactEmail = "hello.dearroroapp@gmail.com"
}
