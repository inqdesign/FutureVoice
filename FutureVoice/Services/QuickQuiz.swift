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
    /// Shown once answered, and the quiz waits for Next: grammar says why,
    /// a level expression what it means (native).
    var note: String? = nil
    /// A written question from `QuickQuizStock`, counted as asked once shown.
    var stockId: UUID? = nil
    /// From the learner's own material rather than the level.
    var isOwn: Bool = false

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
///   word       a word's meaning → pick the word (the weekly test's decoys)
///   expression a line with the expression blanked → pick it
///   grammar    a new everyday line with a blank → pick the form that fits
///
/// The learner's OWN material comes first — notebook words, the "To study"
/// list in the line the fluent self said it in — and the LEVEL fills the
/// rest (same day, founder: "someone who has made no scene and had no call
/// still gets a quiz at their level"): graded words of their CEFR band they
/// have not marked known or used, and written questions from `QuickQuizStock`
/// (common expressions of the level; grammar from their recurring slips,
/// else the level's). A first-day learner gets a full quiz.
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
/// `glossBudget`) and, when the written stock runs low, one batch.
///
/// An answer is weaker evidence than a test's, so only a MISS writes back:
/// the word or phrase goes into the notebook, due now (a level word or
/// expression the learner had never saved included — getting it wrong is
/// the reason to study it). A right answer changes nothing — USED outranks
/// KNOWN, and a tap is neither. Grammar writes nothing.
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
        // The written stock is topped up while the words are looked up.
        async let stockTask = QuickQuizStock.available(appState: appState,
                                                       grammar: size, expressions: size)
        let words = await wordItems(appState: appState, rng: &rng)
        let ownExpressions = expressionItems(appState: appState, rng: &rng)
        let stock = await stockTask

        // The learner's own first, each kind its share; then the level.
        let ownWords = words.filter { $0.isOwn }
        let levelWords = words.filter { !$0.isOwn }
        var picked = Array(ownWords.prefix(maxWords)) + Array(ownExpressions.prefix(maxExpressions))
            + Array(stock.grammar.prefix(maxGrammar))
        let fill = [Array(stock.expressions), levelWords, Array(stock.grammar.dropFirst(maxGrammar)),
                    Array(ownWords.dropFirst(maxWords)), Array(ownExpressions.dropFirst(maxExpressions))]
        // Round-robin over the fill so a thin learner still gets a mix.
        var queues = fill.map { $0.shuffled(using: &rng) }
        while picked.count < size, queues.contains(where: { !$0.isEmpty }) {
            for i in queues.indices where picked.count < size && !queues[i].isEmpty {
                picked.append(queues[i].removeFirst())
            }
        }
        guard picked.count >= minItems else { return [] }
        QuickQuizStock.markAsked(Set(picked.compactMap(\.stockId)))
        return picked.shuffled(using: &rng)
    }

    /// Words the level offers when the notebook runs out: graded at the
    /// learner's band, not already known, used or in the notebook.
    static let levelWordPool = 12

    // MARK: - Kinds

    /// Notebook words first, then level words, each with its meaning. The
    /// meanings are looked up together, capped at `glossBudget`.
    private static func wordItems(appState: AppState, rng: inout WeeklyTestRandom) async -> [QuickQuizItem] {
        let vocab = VocabStore.shared
        let language = appState.targetLanguage
        let native = appState.nativeLanguage
        let studying = vocab.studying.filter { WeeklyTestEngine.isInTargetScript($0) }
        let own = studying.shuffled(using: &rng)
        let taken = Set(studying.map { $0.lowercased() })
            .union(vocab.records.keys.map { $0.lowercased() })
        let level = CoreVocabulary.entries
            .filter { $0.level == appState.proficiency && !taken.contains($0.word.lowercased()) }
            .map(\.word)
            .filter { WeeklyTestEngine.isInTargetScript($0) }
            .shuffled(using: &rng)
            .prefix(levelWordPool)
        let candidates = Array(own.prefix(size)) + Array(level)
        guard !candidates.isEmpty else { return [] }
        let ownSet = Set(own.map { $0.lowercased() })

        var graded: [String] = []
        for band in WeeklyTestEngine.decoyBands(around: appState.proficiency) {
            graded += CoreVocabulary.entries
                .filter { $0.level == band && !taken.contains($0.word.lowercased()) }
                .map(\.word)
                .shuffled(using: &rng)
        }

        // Every meaning at once; whatever has not arrived by the budget is left out.
        var senses: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for word in candidates {
                group.addTask { @MainActor in
                    let entry = await WordLore.entry(for: word, native: native, target: language)
                    return (word, entry?.senses.first?.meaning.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(glossBudget * 1_000_000_000))
                return ("", nil)
            }
            for await (word, sense) in group {
                if word.isEmpty { group.cancelAll(); break }
                if let sense { senses[word] = sense }
                if senses.count == candidates.count { group.cancelAll(); break }
            }
        }

        var out: [QuickQuizItem] = []
        for word in candidates {
            guard let sense = senses[word], !sense.isEmpty,
                  !sense.lowercased().contains(word.lowercased()) else { continue }
            let decoys = WeeklyTestEngine.meaningDecoys(for: word, own: candidates, graded: graded,
                                                        language: language, rng: &rng)
            guard decoys.count == WeeklyTestEngine.choiceCount - 1 else { continue }
            out.append(QuickQuizItem(kind: .word, prompt: sense, answer: word,
                                     options: ([word] + decoys).shuffled(using: &rng),
                                     isOwn: ownSet.contains(word.lowercased())))
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
            .map { QuickQuizItem(kind: .expression, prompt: $0.prompt, answer: $0.answer, options: $0.options,
                                 isOwn: true) }
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
