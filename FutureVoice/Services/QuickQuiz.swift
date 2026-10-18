import Foundation

/// One question of the quick quiz. Every kind is a single tap.
struct QuickQuizItem: Identifiable, Equatable {
    enum Kind: Equatable { case word, expression, grammar }
    let id = UUID()
    let kind: Kind
    /// word: the meaning (native) · expression / grammar: a line with a blank.
    let prompt: String
    let answer: String
    let options: [String]
    /// grammar: the point's name (native), shown above the line.
    var heading: String? = nil
    /// grammar: why the answer is right (native), shown once answered.
    var note: String? = nil

    /// The line with its blank filled — what a missed item is listed as.
    var solved: String {
        prompt.replacingOccurrences(of: WeeklyTestEngine.blankMark, with: answer)
    }
}

/// The quick quiz (2026-10-18, founder: "a check-in on what I'm studying
/// right now, any time, in a simpler form than the weekly test"). The weekly
/// test stays as it is; this is the light one beside it.
///
/// Three kinds, all multiple choice, graded in code:
///
///   word       a notebook word's meaning → pick the word (the weekly test's decoys)
///   expression a "To study" phrase in the line the fluent self said it in,
///              blanked → pick the phrase
///   grammar    a new everyday line with a blank → pick the form that fits
///              (`QuickQuizGrammar`, the learner's recurring grammar points)
///
/// Nothing here rests on what the RECOGNIZER heard. Words and expressions
/// come from the fluent self's own lines (model-written), and grammar items
/// are written fresh. Sentence cards were in the first cut and came out the
/// same day (founder): a card is the learner's transcript plus a fix, and a
/// misheard app name ("나와나는" → "나와 나는") had been "corrected" into a
/// different sentence, which the quiz then marked as the right answer.
///
/// A quiz is built when it opens and gone when it closes. The only network
/// is the free, cached dictionary lookup for word meanings (capped by
/// `glossBudget`) and, when the grammar stock runs low, one model call.
///
/// An answer is weaker evidence than a test's, so only a MISS writes back:
/// the word or phrase is due again now. A right answer changes nothing —
/// USED outranks KNOWN, and a tap is neither. Grammar writes nothing.
@MainActor
enum QuickQuizEngine {
    static let size = 10
    /// Under this there is nothing to quiz; the screen says so.
    static let minItems = 3
    static let maxWords = 4
    static let maxExpressions = 3
    static let maxGrammar = 3
    /// How long word meanings may take to arrive before the quiz goes
    /// without the rest.
    static let glossBudget: TimeInterval = 5

    static func build(appState: AppState) async -> [QuickQuizItem] {
        var rng = WeeklyTestRandom(seed: UUID())
        // The grammar stock is topped up while the words are looked up.
        async let grammarTask = QuickQuizGrammar.items(appState: appState, count: maxGrammar)
        let words = await wordItems(appState: appState, rng: &rng)
        let expressions = expressionItems(appState: appState, rng: &rng)
        let grammar = await grammarTask

        // Each kind its share, then whatever is left fills the quiz.
        var picked = Array(words.prefix(maxWords)) + Array(expressions.prefix(maxExpressions))
            + grammar
        let rest = Array(words.dropFirst(maxWords)) + Array(expressions.dropFirst(maxExpressions))
        picked += rest.shuffled(using: &rng).prefix(max(0, size - picked.count))
        guard picked.count >= minItems else { return [] }
        return Array(picked.shuffled(using: &rng).prefix(size))
    }

    // MARK: - Kinds

    private static func wordItems(appState: AppState, rng: inout WeeklyTestRandom) async -> [QuickQuizItem] {
        let vocab = VocabStore.shared
        let language = appState.targetLanguage
        let studying = vocab.studying.filter { WeeklyTestEngine.isInTargetScript($0) }
        guard !studying.isEmpty else { return [] }
        let candidates = studying.shuffled(using: &rng)
        let taken = Set(studying.map { $0.lowercased() })

        var graded: [String] = []
        for band in WeeklyTestEngine.decoyBands(around: appState.proficiency) {
            graded += CoreVocabulary.entries
                .filter { $0.level == band && !taken.contains($0.word.lowercased()) }
                .map(\.word)
                .shuffled(using: &rng)
        }

        let started = Date()
        var out: [QuickQuizItem] = []
        for word in candidates {
            guard out.count < size, Date().timeIntervalSince(started) < glossBudget else { break }
            guard let entry = await WordLore.entry(for: word, native: appState.nativeLanguage,
                                                   target: language),
                  let sense = entry.senses.first?.meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sense.isEmpty,
                  !sense.lowercased().contains(word.lowercased())
            else { continue }
            let decoys = WeeklyTestEngine.meaningDecoys(for: word, own: candidates, graded: graded,
                                                        language: language, rng: &rng)
            guard decoys.count == WeeklyTestEngine.choiceCount - 1 else { continue }
            out.append(QuickQuizItem(kind: .word, prompt: sense, answer: word,
                                     options: ([word] + decoys).shuffled(using: &rng)))
        }
        return out
    }

    private static func expressionItems(appState: AppState, rng: inout WeeklyTestRandom) -> [QuickQuizItem] {
        let sessions = SessionStore.shared.load()
            .filter { $0.archivedAt == nil && $0.mode == .conversation }
        // The top of the list is what is being studied now; shuffled within
        // it so two quizzes in a row don't ask the same three.
        let toStudy = ExpressionCatalog.toStudy(scenarios: appState.scenarios, sessions: sessions)
            .filter { WeeklyTestEngine.isInTargetScript($0.text) }
        let recent = Array(toStudy.prefix(15)).shuffled(using: &rng)
        guard !recent.isEmpty else { return [] }
        let openers = Set(sessions.compactMap { s in s.turns.first { $0.role == .fluentSelf }?.id })
        let fluent = sessions.flatMap { s in
            s.turns.filter { $0.role == .fluentSelf && !$0.excludedFromScoring && !openers.contains($0.id) }
                .map { (session: s, turn: $0) }
        }
        return WeeklyTestEngine.gapItems(toStudy: recent, sessions: sessions, fluentTurns: fluent,
                                         allSessions: sessions, openers: openers,
                                         appState: appState, rng: &rng)
            .map { QuickQuizItem(kind: .expression, prompt: $0.prompt, answer: $0.answer, options: $0.options) }
    }

    // MARK: - Writing back

    /// A miss puts the item back in front of the learner; a right answer
    /// writes nothing.
    static func apply(_ item: QuickQuizItem, correct: Bool) {
        guard !correct else { return }
        let vocab = VocabStore.shared
        switch item.kind {
        case .word:
            if !vocab.isStudying(item.answer) { vocab.addStudying(item.answer) }
            ReviewQueue.retire(.word, item.answer)
        case .expression:
            if !vocab.isStudyingExpression(item.answer) { vocab.setStudyingExpression(item.answer, true) }
            ReviewQueue.retire(.expression, item.answer)
        case .grammar:
            break
        }
    }
}
