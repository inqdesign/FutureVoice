import Foundation
import NaturalLanguage

/// The user's active vocabulary pool. Tracks, against `CoreVocabulary`, which
/// words they've actually USED (auto-detected from their spoken turns) or
/// self-marked as KNOWN. Grows over time → the word-book page.
@MainActor
final class VocabStore: ObservableObject {
    static let shared = VocabStore()

    enum State: String, Codable { case used, known }

    struct Record: Codable {
        var state: State
        var firstAt: Date
        var lastAt: Date
        var count: Int
    }

    /// lemma → record. Absent = not yet used/known.
    @Published private(set) var records: [String: Record] = [:]
    /// Words the user collected into their notebook to keep studying.
    @Published private(set) var studying: [String] = []
    /// Multi-word expressions the user has used (lowercased key -> record).
    @Published private(set) var expressionRecords: [String: Record] = [:]
    /// Expressions the user bookmarked to keep studying — the phrase-level
    /// analogue of `studying`. Lowercased keys, newest first.
    @Published private(set) var studyingExpressions: [String] = []
    /// Session ids already folded in, so re-ingest is cheap/idempotent.
    private var ingestedSessions: Set<UUID> = []
    private var ingestedExpressionSessions: Set<UUID> = []

    private var fileURL: URL
    private var metaURL: URL
    private var studyingURL: URL
    private var expressionsURL: URL
    private var expressionsMetaURL: URL
    private var studyingExpressionsURL: URL

    init() {
        let dir = LanguageScope.activeDirectory
        fileURL = dir.appendingPathComponent("vocab_pool.json")
        metaURL = dir.appendingPathComponent("vocab_ingested.json")
        studyingURL = dir.appendingPathComponent("vocab_studying.json")
        expressionsURL = dir.appendingPathComponent("vocab_expressions.json")
        expressionsMetaURL = dir.appendingPathComponent("vocab_expressions_ingested.json")
        studyingExpressionsURL = dir.appendingPathComponent("vocab_studying_expressions.json")
        load()
    }

    /// Language switch: repoint every file at the new language's directory
    /// and swap the in-memory pool for that language's contents.
    func languageScopeDidChange() {
        let dir = LanguageScope.activeDirectory
        fileURL = dir.appendingPathComponent("vocab_pool.json")
        metaURL = dir.appendingPathComponent("vocab_ingested.json")
        studyingURL = dir.appendingPathComponent("vocab_studying.json")
        expressionsURL = dir.appendingPathComponent("vocab_expressions.json")
        expressionsMetaURL = dir.appendingPathComponent("vocab_expressions_ingested.json")
        studyingExpressionsURL = dir.appendingPathComponent("vocab_studying_expressions.json")
        records = [:]
        studying = []
        expressionRecords = [:]
        studyingExpressions = []
        ingestedSessions = []
        ingestedExpressionSessions = []
        load()
    }

    // MARK: - Notebook (study collection)

    func isStudying(_ word: String) -> Bool { studying.contains(word) }

    func addStudying(_ word: String) {
        guard !studying.contains(word) else { return }
        studying.insert(word, at: 0)   // newest first
        saveStudying()
        Analytics.capture("word_saved", ["cefr": VocabStore.coreLevelLabel(for: word)])
    }

    func removeStudying(_ word: String) {
        studying.removeAll { $0 == word }
        saveStudying()
    }

    // MARK: - Expression study state (bookmark + known), mirroring words

    private func exprKey(_ phrase: String) -> String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func isStudyingExpression(_ phrase: String) -> Bool {
        studyingExpressions.contains(exprKey(phrase))
    }

    /// Bookmark / un-bookmark an expression for study. Bookmarking ensures a
    /// record exists so the phrase shows up in the Expressions list even if it
    /// was added by hand rather than picked up in a talk.
    func setStudyingExpression(_ phrase: String, _ studying: Bool) {
        let k = exprKey(phrase)
        guard !k.isEmpty else { return }
        if studying {
            guard !studyingExpressions.contains(k) else { return }
            studyingExpressions.insert(k, at: 0)
            Analytics.capture("expression_bookmarked")
            if expressionRecords[k] == nil {
                expressionRecords[k] = Record(state: .used, firstAt: Date(), lastAt: Date(), count: 0)
                saveExpressions()
            }
        } else {
            studyingExpressions.removeAll { $0 == k }
        }
        saveStudyingExpressions()
    }

    func isKnownExpression(_ phrase: String) -> Bool {
        expressionRecords[exprKey(phrase)]?.state == .known
    }

    /// Mark / unmark an expression as known. Unmarking falls back to `.used`
    /// (it's still an expression the user has met), never deletes the record.
    func setKnownExpression(_ phrase: String, _ known: Bool) {
        let k = exprKey(phrase)
        guard !k.isEmpty else { return }
        if var r = expressionRecords[k] {
            r.state = known ? .known : .used
            r.lastAt = Date()
            expressionRecords[k] = r
        } else if known {
            expressionRecords[k] = Record(state: .known, firstAt: Date(), lastAt: Date(), count: 0)
        }
        saveExpressions()
        // Known-state changes can move a phrase in/out of the widget's studying
        // view is unaffected, but keep the snapshot fresh for the count badge.
        StudyWidgetRefresher.schedule()
    }

    // MARK: - Stats

    var usedCount: Int { records.values.filter { $0.state == .used }.count }
    var knownCount: Int { records.count }   // used + self-marked known
    var total: Int { CoreVocabulary.total }

    /// Words active in the last `days` — the real "speaking vocabulary".
    func activeCount(days: Int = 30) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return records.values.filter { $0.state == .used && $0.lastAt >= cutoff }.count
    }

    func state(of lemma: String) -> State? { records[lemma]?.state }

    /// When the word was last used/marked — real study time, for ordering
    /// books by recency.
    func lastAt(of lemma: String) -> Date? { records[lemma]?.lastAt }

    /// Words the user actually uses, most-recent first.
    func usedWords() -> [String] {
        records.filter { $0.value.state == .used }
            .sorted { $0.value.lastAt > $1.value.lastAt }
            .map { $0.key }
    }

    /// Words actually used within the last `days` — the evidence for the
    /// CURRENT vocabulary level. A word said once a year ago proves what the
    /// user could do then, not now; lifetime words stay in `usedWords()` for
    /// the cumulative growth chart.
    func usedWords(withinDays days: Int) -> [String] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return records.filter { $0.value.state == .used && $0.value.lastAt >= cutoff }
            .sorted { $0.value.lastAt > $1.value.lastAt }
            .map { $0.key }
    }

    // MARK: - Mutation

    /// Fold a finished session's USER turns into the pool. No-op if already done.
    @discardableResult
    func ingest(sessionId: UUID, userTexts: [String], at date: Date = Date()) -> [String] {
        guard !ingestedSessions.contains(sessionId) else { return [] }
        ingestedSessions.insert(sessionId)
        var newWords: [String] = []
        for lemma in lemmas(in: userTexts) where CoreVocabulary.set.contains(lemma) {
            if var r = records[lemma] {
                r.count += 1
                r.lastAt = date
                records[lemma] = r          // keep .known if self-marked earlier
            } else {
                records[lemma] = Record(state: .used, firstAt: date, lastAt: date, count: 1)
                newWords.append(lemma)
            }
        }
        save()
        return newWords
    }

    // MARK: - Expressions (multi-word phrases the user actually used)

    /// Fold this session\'s verified expressions into the long-term pool.
    /// Idempotent per session. Returns the ones seen for the FIRST time.
    @discardableResult
    func ingestExpressions(sessionId: UUID, phrases: [String], at date: Date = Date()) -> [String] {
        guard !ingestedExpressionSessions.contains(sessionId) else { return [] }
        ingestedExpressionSessions.insert(sessionId)
        var added: [String] = []
        for raw in phrases {
            let display = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            let key = display.lowercased()
            if var r = expressionRecords[key] {
                r.count += 1
                r.lastAt = date
                expressionRecords[key] = r
            } else {
                expressionRecords[key] = Record(state: .used, firstAt: date, lastAt: date, count: 1)
                added.append(display)
            }
        }
        saveExpressions()
        return added
    }

    /// Manually save an expression/phrase the user picked to study later
    /// (e.g. a "common phrase" or example from a word card). Unlike
    /// `ingestExpressions`, there's no session — this is a deliberate save.
    /// Returns false if it was already in the pool.
    @discardableResult
    func addExpression(_ phrase: String, at date: Date = Date()) -> Bool {
        let display = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = display.lowercased()
        guard !key.isEmpty else { return false }
        if var r = expressionRecords[key] {
            r.lastAt = date
            expressionRecords[key] = r
            saveExpressions()
            return false
        }
        expressionRecords[key] = Record(state: .known, firstAt: date, lastAt: date, count: 0)
        saveExpressions()
        return true
    }

    func hasExpression(_ phrase: String) -> Bool {
        expressionRecords[phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] != nil
    }

    /// Expressions the user has used, most-recent first (lowercased keys).
    func usedExpressions() -> [String] {
        expressionRecords.sorted { $0.value.lastAt > $1.value.lastAt }.map { $0.key }
    }

    var expressionCount: Int { expressionRecords.count }

    struct ExpressionEntry: Identifiable {
        var id: String { text }
        let text: String       // lowercased key
        let count: Int
        let firstAt: Date
        let lastAt: Date
    }

    /// All accumulated expressions as display rows, most-recent first.
    func expressionEntries() -> [ExpressionEntry] {
        expressionRecords
            .map { ExpressionEntry(text: $0.key, count: $0.value.count,
                                   firstAt: $0.value.firstAt, lastAt: $0.value.lastAt) }
            .sorted { $0.lastAt > $1.lastAt }
    }

    /// The user's own turns where they used this expression — for the
    /// expression detail (text + replayable audio when we have it).
    func sentences(containing phrase: String) -> [SourceSentence] {
        let needle = phrase.lowercased()
        guard !needle.isEmpty else { return [] }
        var out: [SourceSentence] = []
        for sess in SessionStore.shared.load() {
            for t in sess.turns where t.role == .user {
                if t.transcript.lowercased().contains(needle) {
                    out.append(SourceSentence(
                        text: Self.snippet(around: needle, in: t.transcript),
                        audioURL: t.audioURL, source: "Talk"))
                }
            }
        }
        return out
    }

    /// A readable window around the phrase instead of the WHOLE turn — STT
    /// turns can be minutes of unpunctuated speech, which buried the phrase
    /// in a wall of text on the expression detail page.
    static func snippet(around needle: String, in transcript: String,
                        window: Int = 90) -> String {
        guard let range = transcript.range(of: needle, options: [.caseInsensitive]) else {
            return transcript
        }
        let start = transcript.index(range.lowerBound, offsetBy: -window,
                                     limitedBy: transcript.startIndex) ?? transcript.startIndex
        let end = transcript.index(range.upperBound, offsetBy: window,
                                   limitedBy: transcript.endIndex) ?? transcript.endIndex
        var text = String(transcript[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > transcript.startIndex { text = "… " + text }
        if end < transcript.endIndex { text += " …" }
        return text
    }

    /// Fold every ended session into the pool (idempotent) — used to seed the
    /// page from history the first time, and to catch anything missed.
    func backfillFromSessions() {
        for s in SessionStore.shared.load() where s.endedAt != nil {
            let userTexts = s.turns.filter { $0.role == .user }.map { $0.transcript }
            ingest(sessionId: s.id, userTexts: userTexts, at: s.endedAt ?? s.startedAt)
        }
    }

    /// User self-marks a word as known — it also leaves the study notebook.
    func markKnown(_ lemma: String) {
        if records[lemma] == nil {
            records[lemma] = Record(state: .known, firstAt: Date(), lastAt: Date(), count: 0)
            save()
        }
        removeStudying(lemma)
        Analytics.capture("word_known", ["cefr": VocabStore.coreLevelLabel(for: lemma)])
    }

    func unmark(_ lemma: String) {
        records[lemma] = nil
        save()
    }

    // MARK: - Sentences the fluent self said using a word

    struct SourceSentence: Identifiable {
        let id = UUID()
        let text: String
        let audioURL: URL?
        let source: String   // "Talk" / "Watch"
    }

    /// Lines where the fluent self (your clone) used this word — from past
    /// conversations (with replayable audio) and Watch dialogues.
    func sentences(using word: String) -> [SourceSentence] {
        var out: [SourceSentence] = []
        for s in SessionStore.shared.load() {
            for t in s.turns where t.role == .fluentSelf {
                if lemmas(in: [t.transcript]).contains(word) {
                    out.append(SourceSentence(text: t.transcript, audioURL: t.audioURL, source: "Talk"))
                }
            }
        }
        for d in WatchDialogueStore.shared.load() {
            for turn in d.turns where turn.speaker == "user" {
                if lemmas(in: [turn.text]).contains(word) {
                    out.append(SourceSentence(text: turn.text, audioURL: nil, source: "Watch"))
                }
            }
        }
        return out
    }

    /// Core-list lemmas the fluent self spoke that the user has never used or
    /// marked known — natural "words to pick up" from a conversation. Filtered
    /// to the user's level and up: easier words they merely haven't happened
    /// to say would flood the list with noise.
    func pickupWords(fromFluentTexts texts: [String], atOrAbove minLevel: CEFRLevel?) -> [String] {
        let minRank = minLevel.map(CoreVocabulary.levelRank)
        return lemmas(in: texts)
            .filter { records[$0] == nil }
            .compactMap { w -> (word: String, rank: Int)? in
                guard let lv = CoreVocabulary.level(of: w) else { return nil }
                let rank = CoreVocabulary.levelRank(lv)
                if let minRank, rank < minRank { return nil }
                return (w, rank)
            }
            .sorted { $0.rank == $1.rank ? $0.word < $1.word : $0.rank < $1.rank }
            .map(\.word)
    }

    /// Best notebook key for a word the user tapped in a transcript: its lemma
    /// when the lemma is in the core list ("revitalizing" → "revitalize"),
    /// otherwise the cleaned word itself.
    nonisolated static func lookupKey(for raw: String) -> String {
        let w = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard !w.isEmpty else { return w }
        if Self.matchesKorean {
            return KoreanMorph.dictionaryForm(of: w, in: CoreVocabulary.set) ?? w
        }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = w
        tagger.setLanguage(.english, range: w.startIndex..<w.endIndex)
        let lemma = tagger.tag(at: w.startIndex, unit: .word, scheme: .lemma).0?.rawValue.lowercased()
        if let lemma, CoreVocabulary.set.contains(lemma) { return lemma }
        return w
    }

    // MARK: - Lemmatization

    /// NLTagger's lemma scheme doesn't cover Korean, and Korean surface forms
    /// carry particles/conjugation the wordlist headwords don't. Routed by
    /// the CURRENT target language on every call — a switch re-picks the
    /// tokenizer immediately (this was a launch-scoped `static let` before
    /// multi-language).
    nonisolated private static var matchesKorean: Bool {
        LanguageCatalog.language(LanguageScope.active)?.code == "ko"
    }

    private func lemmas(in texts: [String]) -> Set<String> {
        if Self.matchesKorean { return koreanLemmas(in: texts) }
        var out = Set<String>()
        let tagger = NLTagger(tagSchemes: [.lemma])
        for text in texts {
            let lower = text.lowercased()
            tagger.string = lower
            tagger.setLanguage(.english, range: lower.startIndex..<lower.endIndex)
            tagger.enumerateTags(in: lower.startIndex..<lower.endIndex,
                                 unit: .word, scheme: .lemma,
                                 options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, range in
                let lemma = (tag?.rawValue ?? String(lower[range])).lowercased()
                if lemma.count > 1 { out.insert(lemma) }
                return true
            }
        }
        return out
    }

    /// Korean: map each spoken token to a wordlist headword via the
    /// deterministic KoreanMorph heuristic (particle stripping, ending → 다).
    /// Only lexicon hits come back — a candidate that isn't a headword is a
    /// guess we couldn't verify, not a word to track.
    private func koreanLemmas(in texts: [String]) -> Set<String> {
        var out = Set<String>()
        for text in texts {
            let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for token in tokens where !token.isEmpty {
                if let head = KoreanMorph.dictionaryForm(of: token, in: CoreVocabulary.set) {
                    out.insert(head)
                }
            }
        }
        return out
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let dict = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = dict
        }
        if let data = try? Data(contentsOf: metaURL),
           let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            ingestedSessions = ids
        }
        if let data = try? Data(contentsOf: studyingURL),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            studying = list
        }
        if let data = try? Data(contentsOf: expressionsURL),
           let dict = try? JSONDecoder().decode([String: Record].self, from: data) {
            expressionRecords = dict
        }
        if let data = try? Data(contentsOf: expressionsMetaURL),
           let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            ingestedExpressionSessions = ids
        }
        if let data = try? Data(contentsOf: studyingExpressionsURL),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            studyingExpressions = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: [.atomic])
        }
        if let data = try? JSONEncoder().encode(ingestedSessions) {
            try? data.write(to: metaURL, options: [.atomic])
        }
    }

    private func saveStudying() {
        if let data = try? JSONEncoder().encode(studying) {
            try? data.write(to: studyingURL, options: [.atomic])
        }
        // Notebook words show on the home-screen widget — refresh its snapshot.
        StudyWidgetRefresher.schedule()
    }

    private func saveStudyingExpressions() {
        if let data = try? JSONEncoder().encode(studyingExpressions) {
            try? data.write(to: studyingExpressionsURL, options: [.atomic])
        }
        // The Expressions widget shows only bookmarked phrases — refresh it.
        StudyWidgetRefresher.schedule()
    }

    private func saveExpressions() {
        if let data = try? JSONEncoder().encode(expressionRecords) {
            try? data.write(to: expressionsURL, options: [.atomic])
        }
        if let data = try? JSONEncoder().encode(ingestedExpressionSessions) {
            try? data.write(to: expressionsMetaURL, options: [.atomic])
        }
    }
}
