import Foundation

/// The two-language contract every coaching prompt shares.
///
/// Two languages are always in play: the language being practiced (target) and
/// the language the learner actually thinks in (native). The split is the same
/// everywhere in the app:
///
/// - **Material** — anything the learner is meant to SAY, read aloud, drill or
///   memorize — stays in the TARGET language. Drill cards, corrected sentences,
///   example utterances, expressions, scene lines.
/// - **Coaching** — anything that explains, judges or frames that material —
///   is written in the learner's NATIVE language. Reasons, notes, rationales,
///   summaries, memory hooks, scorecard commentary.
///
/// The reason is the whole point of the app: a B1 learner who has to decode an
/// English explanation of their English mistake mostly just skips it. Feedback
/// only works in a language the learner reads effortlessly.
///
/// Prompt templates live in the engines (`ConversationEngine`, `ShadowEngine`,
/// `WeeklyReportEngine`, `DrillEnrichmentEngine`); what lives HERE is only the
/// shared preamble, so the rule is stated once and identically. Each engine
/// still tags its own fields — `contract` cannot know their names.
enum CoachingLanguage {

    /// Shared prompt preamble. Returns an empty string when the two languages
    /// are the same (nothing to disambiguate) so callers can splice it in
    /// unconditionally.
    static func contract(target: String, native: String) -> String {
        let targetName = LanguageCatalog.englishName(target)
        let nativeName = LanguageCatalog.englishName(native)
        guard targetName != nativeName else { return "" }

        return """
        LANGUAGE CONTRACT — two languages are in play. Never mix them up:
        - The learner is practicing \(targetName). They think in \(nativeName).
        - MATERIAL stays in \(targetName): anything the learner is meant to say
          out loud, drill, or memorize — quoted lines, corrected sentences,
          example utterances, vocabulary, expressions.
        - COACHING is written in \(nativeName): anything that explains, judges
          or frames that material — reasons, notes, rationales, summaries,
          hooks, commentary.
        - Write \(nativeName) that a native speaker would actually write —
          natural and plain, never a stiff word-for-word translation of an
          English sentence, and never machine-translated grammar terminology
          nobody uses.
        - When a \(nativeName) sentence refers to a \(targetName) word or
          phrase, QUOTE it in \(targetName) inside the \(nativeName) sentence
          and do not translate the quoted part. Example shape: 「"went to the
          bank"처럼 과거형으로」.
        - The per-field rules below name a language for each field. Where they
          do, they win over this preamble.

        """
    }

    /// `"in Korean"` — for inline per-field tags. Empty when target == native,
    /// so a field's rule reads naturally either way.
    static func inNative(target: String, native: String) -> String {
        let targetName = LanguageCatalog.englishName(target)
        let nativeName = LanguageCatalog.englishName(native)
        guard targetName != nativeName else { return "" }
        return "in \(nativeName)"
    }
}
