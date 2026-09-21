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

    /// One prompt bullet for every line the fluent self SAYS: the text is read
    /// by a synthesizer whose pauses and intonation follow the punctuation.
    ///
    /// Reported 2026-09-15 as "when it speaks Korean it reads without
    /// breathing". Measured the same day (scratch probe, `eleven_turbo_v2_5`
    /// and `eleven_multilingual_v2`, HTTP and the gateway's per-sentence
    /// multi-stream path): a three-sentence Korean turn with no commas got
    /// ~1.1 s of internal pause in 12 s, the same text with a comma at each
    /// clause boundary ~1.7 s, and the gap between sentences stayed ~400 ms on
    /// every path — so nothing in synthesis or chunking eats the breaths; the
    /// text never asked for them. `speed: 0.9` was tried and slowed the words
    /// while REDUCING the pauses, which is the wrong axis.
    ///
    /// **The first version made it worse, and the reason is worth keeping**
    /// (2026-09-16). It said "a comma between two clauses", and the model
    /// read a finished sentence as a clause: "나 방금 너랑 비슷한 사람 봤다,
    /// 어찌나 반갑던지, 뭐 하고 지내?". A comma after a sentence-final ending
    /// keeps the voice suspended on a sentence that is already over, then
    /// jumps to a new one — choppy to read AND to hear. On the opener pool
    /// (flash-lite, 18 lines) that shape went from 2–6 with no rule to 10 with
    /// that one. So the rule is stated as INTONATION: a period finishes, a
    /// comma hangs, and a comma is only ever inside a sentence after an ending
    /// that leaves it open. Measured on the rewrite: 0 wrong commas on both
    /// models, and long comma-less sentences in live-turn replies 5 → 1 of 15.
    /// Removing the rule instead brings the original complaint back.
    ///
    /// **Joining is half the rule** (2026-09-16, chosen by ear from four
    /// synthesized takes of the same voicemail). Correct punctuation on three
    /// stacked short sentences still reads staccato — each one falls, and the
    /// line becomes a list. The take that won joined the first two with ~는데
    /// and a comma, so the voice hangs once instead of landing twice. It is
    /// written to stay clear of `ConversationEngine`'s ceiling rule (over the
    /// ceiling is fixed by dropping an idea, never by merging), because that
    /// rule is about not evading a COUNT, and this one is about two clauses
    /// that were always one thought.
    ///
    /// The deeper, older problem is NOT this rule: short lines composed on an
    /// English skeleton ("지금 괜찮아? 목소리 듣고 싶어서.") predate it in
    /// ElevenLabs history from August on. Spliced, not repeated: every engine
    /// whose output is voiced carries this one string.
    static let breathPunctuation = """
        PUNCTUATE LIKE SPEECH. Every line you write is read aloud by a \
        synthesizer whose intonation follows your punctuation: a period makes \
        the voice fall and finish, a comma keeps it suspended for what \
        follows, and a sentence with nothing inside it is read in one breath. \
        So a FINISHED sentence always ends with a period, question mark or \
        exclamation mark, never a comma. In Korean, a sentence-final ending \
        (~어, ~아, ~야, ~지, ~네, ~다, ~자, ~래) is followed by . ? or !, \
        never by a comma. Wrong: "목소리 들으니까 반갑다, 어떻게 지내?" \
        Right: "목소리 들으니까 반갑다. 어떻게 지내?" A comma belongs only \
        INSIDE a sentence, where the voice should hang and breathe: after a \
        connective ending that leaves the sentence open (Korean ~는데, ~서, \
        ~니까, ~고, ~던지, ~면; Japanese ~て, ~けど, ~から; their equivalents \
        elsewhere), after a name you're calling, or after a short reaction \
        ("아, 진짜?"). Never a comma every few words. \
        AND DON'T STACK SHORT SENTENCES. Three short ones in a row make the \
        voice fall three times and read as staccato. When two of them are \
        really ONE thought — a reason and what it led to, a worry and the \
        question it raises — join them into a single sentence with a \
        connective ending and a comma: not "아까 전화 안 받았지? 별일 없는 \
        거지. 오늘 하루는 어땠어?" but "아까 전화 안 받아서 걱정했는데, 별일 \
        없는 거지? 오늘 하루는 어땠어?". This is never a licence to exceed \
        the turn's sentence ceiling: if you are over it, drop an idea instead.
        """

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
