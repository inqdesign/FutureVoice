import Foundation

/// The gender a learner's sentences take, for the languages whose words
/// change with it (2026-11-13, founder). French and Spanish make the speaker
/// agree with themselves ("je suis contente", "estoy cansado"), and in this
/// app the fluent self speaks AS the learner, so its lines are lines the
/// learner will say back (Say it again, shadowing, cards). Every other target
/// ignores it.
///
/// Three answers, all equal: male, female, or prefer not to say, which keeps
/// the fluent self in wording that has no gender, the way natives rephrase
/// ("ça me fait plaisir" for "enchanté(e)"). Nothing asks for it. Two ways
/// in:
///   - **The learner's own recording** (`guessFromVoiceIfNeeded`): a median
///     pitch clearly low or clearly high fills it in, marked as a guess. The
///     band where voices overlap guesses nothing. NEVER the voice they PICKED
///     (founder: a man may pick a female tutor voice), and nothing at all for
///     a learner who chose the AI tutor without recording.
///   - **Me → Profile**, where any answer they choose replaces the guess and
///     is never guessed over again.
enum LearnerGender: String, CaseIterable, Identifiable {
    case male, female, unsaid

    var id: String { rawValue }

    enum Source: String { case voice, chosen }

    static let valueKey = "futurevoice.learnerGender"
    static let sourceKey = "futurevoice.learnerGender.source"

    /// Below this a voice is guessed male, above `femaleAboveHz` female.
    /// Adult ranges are roughly 85–180 Hz and 165–255 Hz; `VoicePitch`'s
    /// single 165 Hz cut is fine for offering a preset, where a wrong side
    /// costs nothing, and too sharp for saying who someone is.
    static let maleBelowHz: Double = 150
    static let femaleAboveHz: Double = 185

    static var current: LearnerGender? {
        UserDefaults.standard.string(forKey: valueKey).flatMap(LearnerGender.init(rawValue:))
    }

    static var source: Source? {
        UserDefaults.standard.string(forKey: sourceKey).flatMap(Source.init(rawValue:))
    }

    /// Languages whose sentences about the speaker change with it.
    static func matters(in language: String) -> Bool {
        ["fr", "es"].contains(LanguageCatalog.base(language))
    }

    static func set(_ value: LearnerGender, source: Source) {
        let d = UserDefaults.standard
        d.set(value.rawValue, forKey: valueKey)
        d.set(source.rawValue, forKey: sourceKey)
        SyncEngine.noteChanged(.defaults)
    }

    /// The guess a median pitch allows, nil in the overlap.
    static func guess(fromPitch hz: Double) -> LearnerGender? {
        if hz < maleBelowHz { return .male }
        if hz > femaleAboveHz { return .female }
        return nil
    }

    private static var guessing = false

    /// Fills in a guess from the learner's OWN recording, once: only for a
    /// target that needs it, only when nothing is on file, never for a
    /// tutor-only voice. Off the main thread (it reads 12 s of audio).
    @MainActor
    static func guessFromVoiceIfNeeded(target: String, tutorOnly: Bool) {
        guard matters(in: target), current == nil, !tutorOnly, !guessing,
              let sample = VoiceSampleStore.shared.url else { return }
        guessing = true
        Task {
            let hz = await Task.detached(priority: .utility) { VoicePitch.medianF0(url: sample) }.value
            guessing = false
            guard current == nil, let hz, let value = guess(fromPitch: hz) else { return }
            set(value, source: .voice)
        }
    }
}
