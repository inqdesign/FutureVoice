import Foundation

/// How the fluent self ADDRESSES the learner by name in UI copy.
///
/// Not a formatter for displaying a name — `MeTab` prints `displayName`
/// straight and should keep doing that. This is for the lines the future self
/// speaks in the first person ("보람아, 내가 계속하게 도와줄게"), where a bare
/// name reads like a label and the language's own way of calling someone is
/// what makes it sound like a person talking.
///
/// Korean is the only language here that inflects: the vocative particle is
/// 아 after a final consonant (보람 → 보람아) and 야 after a vowel (지수 →
/// 지수야). It is attached ONLY to a name written in Hangul — "Alex야" is not
/// how anyone writes it — and only when the app is in Korean, since the same
/// persona is addressed in whatever language the learner picked.
enum LearnerAddress {

    /// The name ready to be dropped into a "%@, …" line, or nil when there is
    /// no name to use. Callers fall back to the nameless copy on nil rather
    /// than printing a stray comma.
    static func vocative(_ rawName: String?) -> String? {
        let name = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard UILanguage.chromeLanguage.hasPrefix("ko"), let last = name.last,
              let scalar = last.unicodeScalars.first,
              (0xAC00...0xD7A3).contains(scalar.value) else { return name }
        // Hangul syllable block: the final-consonant index is the remainder
        // mod 28, and 0 means the syllable ends on a vowel.
        let endsOnConsonant = (Int(scalar.value) - 0xAC00) % 28 != 0
        return name + (endsOnConsonant ? "아" : "야")
    }
}
