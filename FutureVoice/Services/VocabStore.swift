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
        /// A `.known` verdict given while the item was IN the notebook — the
        /// learner studied it and then said "I know it". Only those are a
        /// claim worth checking in a call; a word ticked while browsing a
        /// level list, or a core-list top-up waved off the first time it was
        /// dealt, was never studied. Optional so records on disk (and from an
        /// older build over sync) decode as nil = not from the notebook.
        var fromStudying: Bool? = nil
    }

    /// lemma → record. Absent = not yet used/known.
    @Published private(set) var records: [String: Record] = [:]
    /// Words the user collected into their notebook to keep studying.
    @Published private(set) var studying: [String] = []
    /// Words the learner took OUT of the notebook by hand.
    ///
    /// Only `keepFromTalk` reads it, and only to stay out of the way: a talk
    /// that puts an unbookmarked word straight back every time is the app
    /// overruling a decision the learner made. Bookmarking it again clears
    /// the mark, so nothing is permanent.
    @Published private(set) var removedByHand: Set<String> = []
    /// Words `keepFromTalk` put in the notebook BY ITSELF and the learner has
    /// not touched since. Not a fourth state — a provenance mark. A word here
    /// was never studied by anyone: no tap, no deck, no verdict. It leaves
    /// the set the moment the learner does anything to it (bookmarks it by
    /// hand, snoozes it in a deck, takes it out).
    @Published private(set) var autoKept: Set<String> = []
    /// Multi-word expressions the user has used (lowercased key -> record).
    @Published private(set) var expressionRecords: [String: Record] = [:]
    /// Expressions the user bookmarked to keep studying — the phrase-level
    /// analogue of `studying`. Lowercased keys, newest first.
    @Published private(set) var studyingExpressions: [String] = []
    /// Expressions the learner threw OUT of the collection. Not "known" and
    /// not snoozed: not material at all.
    ///
    /// A word can't get here by mistake: a graded one is in `CoreVocabulary`
    /// by definition, and an ungraded one is only ever collected from the
    /// fluent self's own model-written turns — a mistranscription is filtered
    /// out on both paths by construction.
    /// An expression has no such lexicon; its only guard is that the phrase
    /// appears verbatim in the learner's own turns, and a transcriber's error
    /// passes that check every time (it really is in the transcript, letter
    /// for letter). So the learner is the last judge, and their verdict is
    /// kept rather than just deleting the record — the next talk misheard the
    /// same way would otherwise put the same junk straight back.
    @Published private(set) var dismissedExpressions: Set<String> = []
    /// Session id → how many of its user texts are already folded in. A
    /// resumed talk is summarized AGAIN over its whole transcript; counting
    /// texts (instead of the old all-or-nothing session set) lets the second
    /// pass fold in just the new suffix — the old guard silently dropped
    /// every word spoken after a resume from the pool, forever. Legacy
    /// entries carry `Int.max` ("fully ingested, count unknown").
    private var ingestedTextCounts: [String: Int] = [:]
    /// Session id → expression keys already counted for it — key-level for
    /// the same reason: a re-summary must add the resumed portion's phrases
    /// without double-counting the first batch.
    private var ingestedExpressionKeys: [String: Set<String>] = [:]
    /// Sessions whose expressions were ingested before per-key tracking.
    /// What they counted is reconstructable: exactly the expression list
    /// saved on their summary (see `legacyExpressionKeys`).
    private var legacyExpressionSessions: Set<UUID> = []

    private var fileURL: URL
    private var metaURL: URL
    private var studyingURL: URL
    private var expressionsURL: URL
    private var expressionsMetaURL: URL
    private var studyingExpressionsURL: URL
    private var dismissedExpressionsURL: URL
    private var removedByHandURL: URL
    private var autoKeptURL: URL

    init() {
        let dir = LanguageScope.activeDirectory
        fileURL = dir.appendingPathComponent("vocab_pool.json")
        metaURL = dir.appendingPathComponent("vocab_ingested.json")
        studyingURL = dir.appendingPathComponent("vocab_studying.json")
        expressionsURL = dir.appendingPathComponent("vocab_expressions.json")
        expressionsMetaURL = dir.appendingPathComponent("vocab_expressions_ingested.json")
        studyingExpressionsURL = dir.appendingPathComponent("vocab_studying_expressions.json")
        dismissedExpressionsURL = dir.appendingPathComponent("vocab_dismissed_expressions.json")
        removedByHandURL = dir.appendingPathComponent("vocab_removed_by_hand.json")
        autoKeptURL = dir.appendingPathComponent("vocab_auto_kept.json")
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
        dismissedExpressionsURL = dir.appendingPathComponent("vocab_dismissed_expressions.json")
        removedByHandURL = dir.appendingPathComponent("vocab_removed_by_hand.json")
        autoKeptURL = dir.appendingPathComponent("vocab_auto_kept.json")
        records = [:]
        studying = []
        expressionRecords = [:]
        studyingExpressions = []
        dismissedExpressions = []
        removedByHand = []
        autoKept = []
        ingestedTextCounts = [:]
        ingestedExpressionKeys = [:]
        legacyExpressionSessions = []
        load()
    }

    // MARK: - Notebook (study collection)

    func isStudying(_ word: String) -> Bool { studying.contains(word) }

    func addStudying(_ word: String) {
        guard !studying.contains(word) else { return }
        // Opposite verdicts: keeping a word takes back a self-marked "known",
        // exactly as `markKnown` takes back the bookmark — the later tap wins
        // in both directions, so the two can never be lit together. A `.used`
        // record stays: that's evidence the learner said it, not a verdict.
        if records[word]?.state == .known {
            records[word] = nil
            save()
        }
        studying.insert(word, at: 0)   // newest first
        saveStudying()
        if autoKept.remove(word) != nil { saveAutoKept() }
        // Bookmarking it again takes back the "I don't want this" — nothing
        // about that verdict should outlive the learner changing their mind.
        if removedByHand.remove(word.lowercased()) != nil { saveRemovedByHand() }
        // Effort, not a finished word: keeping it means you're still
        // studying it, so it must not tick the daily goal.
        PracticeLog.shared.record(.word)
        Analytics.capture("word_saved", ["cefr": VocabStore.coreLevelLabel(for: word)])
    }

    /// Put the words a finished talk taught into the notebook, without the
    /// learner having to find and tap each one.
    ///
    /// The fluent self says a word, the learner doesn't know it, and it used
    /// to sit in the talk's book waiting to be noticed — so a word the whole
    /// call was about only entered review if you went looking for it. It
    /// enters by itself now. Returns what was actually added.
    ///
    /// Not `addStudying` in a loop, for one reason: that call logs a practice
    /// rep and fires `word_saved`, because keeping a word by hand IS effort.
    /// Nothing here was chosen by the learner, so counting it as their effort
    /// would inflate the daily goal with work nobody did.
    ///
    /// Three kinds of word are skipped, all meaning "not new to them": one
    /// they've already said or marked known, one already in the notebook, and
    /// one they took out of it by hand — putting that last one back every
    /// talk is the app overruling a decision they made.
    @discardableResult
    func keepFromTalk(_ words: [String]) -> [String] {
        var added: [String] = []
        for word in words {
            let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty,
                  records[key] == nil,
                  !studying.contains(key),
                  !removedByHand.contains(key) else { continue }
            studying.insert(key, at: 0)
            autoKept.insert(key)
            added.append(key)
        }
        guard !added.isEmpty else { return [] }
        saveStudying()
        saveAutoKept()
        StudyWidgetRefresher.schedule()
        Analytics.capture("words_kept_from_talk", ["count": added.count])
        return added
    }

    func removeStudying(_ word: String) {
        studying.removeAll { $0 == word }
        saveStudying()
        if autoKept.remove(word) != nil { saveAutoKept() }
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !key.isEmpty, removedByHand.insert(key).inserted { saveRemovedByHand() }
    }

    /// Clear the "they threw this out" mark without bookmarking the word —
    /// for tests and for a full wipe. The learner's own way of clearing it is
    /// simply to bookmark the word again.
    func forgetRemovedByHand(_ word: String) {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if removedByHand.remove(key) != nil { saveRemovedByHand() }
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
            PracticeLog.shared.record(.expression)
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

    // MARK: - Confirmed by use
    //
    // Three states, in order: studying (the deck's 10 min / tomorrow / 3
    // days), KNOWN (the learner's own verdict — "Got it" / "I know it"), and
    // USED — said in a real talk, which outranks both. A known item is a
    // claim; a used one is evidence. Nothing here is a fourth store: a word
    // is confirmed when its record is `.used`, an expression when its count
    // is above zero (a bookmark alone creates a zero-count row).

    /// Said in a real talk — the strongest state there is.
    func isConfirmedWord(_ lemma: String) -> Bool { records[lemma]?.state == .used }

    func isConfirmedExpression(_ phrase: String) -> Bool {
        (expressionRecords[exprKey(phrase)]?.count ?? 0) > 0
    }

    /// Marked known by hand and never yet said in a talk — what the next
    /// call can confirm.
    /// Only verdicts given on something the learner was studying count
    /// (`Record.fromStudying`): the call's chip row and the wrap-up both read
    /// these, and neither may put a word in front of the learner that they
    /// never kept.
    var unconfirmedKnownWords: [String] {
        records.filter { $0.value.state == .known && $0.value.fromStudying == true }.map(\.key)
    }

    var unconfirmedKnownExpressions: [String] {
        expressionRecords.filter {
            $0.value.state == .known && $0.value.count == 0 && $0.value.fromStudying == true
        }.map(\.key)
    }

    /// Mark / unmark an expression as known. Unmarking falls back to `.used`
    /// (it's still an expression the user has met), never deletes the record.
    func setKnownExpression(_ phrase: String, _ known: Bool) {
        let k = exprKey(phrase)
        guard !k.isEmpty else { return }
        let fromStudying: Bool? = known && studyingExpressions.contains(k) ? true : nil
        if var r = expressionRecords[k] {
            r.state = known ? .known : .used
            r.lastAt = Date()
            r.fromStudying = fromStudying
            expressionRecords[k] = r
        } else if known {
            expressionRecords[k] = Record(state: .known, firstAt: Date(), lastAt: Date(), count: 0,
                                          fromStudying: fromStudying)
        }
        if known { PracticeLog.shared.record(.expression, finished: true) }
        saveExpressions()
        // Known-state changes can move a phrase in/out of the widget's studying
        // view is unaffected, but keep the snapshot fresh for the count badge.
        StudyWidgetRefresher.schedule()
    }

    /// Thrown out: never dealt, never listed, never re-collected.
    func isDismissedExpression(_ phrase: String) -> Bool {
        dismissedExpressions.contains(exprKey(phrase))
    }

    /// The learner's verdict that this was never an expression — usually the
    /// transcriber's words rather than theirs. It leaves the collection
    /// entirely: the record, the bookmark and the return date all go, and the
    /// key is remembered so no later talk can re-collect it.
    func dismissExpression(_ phrase: String) {
        let k = exprKey(phrase)
        guard !k.isEmpty, dismissedExpressions.insert(k).inserted else { return }
        expressionRecords[k] = nil
        studyingExpressions.removeAll { $0 == k }
        StudyScheduleStore.shared.clear(.expression, k)
        saveDismissedExpressions()
        saveExpressions()
        saveStudyingExpressions()
        Analytics.capture("expression_dismissed")
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

    /// Fold a finished session's USER turns into the pool. Only texts beyond
    /// what this session already contributed are counted, so a full re-run
    /// after a resume adds the new turns and nothing twice; unchanged = no-op.
    @discardableResult
    func ingest(sessionId: UUID, userTexts: [String], at date: Date = Date()) -> [String] {
        let already = ingestedTextCounts[sessionId.uuidString] ?? 0
        guard userTexts.count > already else { return [] }
        ingestedTextCounts[sessionId.uuidString] = userTexts.count
        var newWords: [String] = []
        // The pool gate stays on the learner's side — a mistranscription must
        // never MINT a word. It may still credit one the app put in front of
        // them: an ungraded word the fluent self taught and they kept would
        // otherwise never be markable as used, so the day's hand would deal it
        // back forever however often they said it.
        func tracked(_ lemma: String) -> Bool {
            CoreVocabulary.set.contains(lemma)
                || records[lemma] != nil
                || studying.contains(lemma)
        }
        var graduated = false
        for lemma in Self.lemmas(in: Array(userTexts.dropFirst(already))) where tracked(lemma) {
            if var r = records[lemma] {
                r.count += 1
                r.lastAt = date
                // Saying it outranks having marked it: a self-declared "known"
                // becomes a confirmed one the moment the word comes out.
                r.state = .used
                records[lemma] = r
            } else {
                records[lemma] = Record(state: .used, firstAt: date, lastAt: date, count: 1)
                newWords.append(lemma)
            }
            // Used in a real talk IS known — the word leaves the notebook and
            // its return date the way `markKnown` takes it out, minus the
            // "thrown out by hand" mark, because nobody threw it out.
            if let i = studying.firstIndex(of: lemma) {
                studying.remove(at: i)
                autoKept.remove(lemma)
                StudyScheduleStore.shared.clear(.word, lemma)
                graduated = true
            }
        }
        save()
        if graduated {
            saveStudying()
            saveAutoKept()
            StudyWidgetRefresher.schedule()
        }
        return newWords
    }

    // MARK: - Expressions (multi-word phrases the user actually used)

    /// Fold this session\'s verified expressions into the long-term pool.
    /// Each phrase is counted at most once per session, so the re-summary of
    /// a resumed talk adds only what the new turns produced. Returns the ones
    /// seen for the FIRST time.
    @discardableResult
    func ingestExpressions(sessionId: UUID, phrases: [String], at date: Date = Date()) -> [String] {
        var counted = ingestedExpressionKeys[sessionId.uuidString]
            ?? legacyExpressionKeys(for: sessionId)
        var added: [String] = []
        var unbookmarked = false
        for raw in phrases {
            let display = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            let key = exprKey(display)
            guard !counted.contains(key) else { continue }
            // Thrown out once, thrown out for good: the same mishearing
            // recurring in a later talk must not re-collect it.
            guard !dismissedExpressions.contains(key) else { continue }
            counted.insert(key)
            if var r = expressionRecords[key] {
                r.count += 1
                r.lastAt = date
                r.state = .used     // said it: confirmed, whatever was marked
                expressionRecords[key] = r
            } else {
                expressionRecords[key] = Record(state: .used, firstAt: date, lastAt: date, count: 1)
                added.append(display)
            }
            // Same rule as words: produced in a talk, so it leaves the
            // bookmarks and the review schedule.
            if let i = studyingExpressions.firstIndex(of: key) {
                studyingExpressions.remove(at: i)
                StudyScheduleStore.shared.clear(.expression, key)
                unbookmarked = true
            }
        }
        ingestedExpressionKeys[sessionId.uuidString] = counted
        saveExpressions()
        if unbookmarked { saveStudyingExpressions() }
        return added
    }

    /// Seed a session's counted-keys from its previous summary — for
    /// sessions ingested before per-key tracking, whose row on disk may
    /// already be overwritten by the time a re-analysis runs (the caller
    /// still holds the old summary in memory). No-op once per-key tracking
    /// has data for the session.
    func notePriorExpressions(sessionId: UUID, phrases: [String]) {
        guard ingestedExpressionKeys[sessionId.uuidString] == nil,
              !phrases.isEmpty else { return }
        ingestedExpressionKeys[sessionId.uuidString] = Set(phrases.map(exprKey))
    }

    /// What a pre-per-key session already counted: the verified list its
    /// summary carries is exactly what was passed to ingest back then.
    private func legacyExpressionKeys(for sessionId: UUID) -> Set<String> {
        guard legacyExpressionSessions.contains(sessionId) else { return [] }
        let phrases = SessionStore.shared.load()
            .first { $0.id == sessionId }?.summary?.expressionsUsed ?? []
        return Set(phrases.map(exprKey))
    }

    /// Manually save an expression/phrase the user picked to study later
    /// (e.g. a "common phrase" or example from a word card). It is a
    /// BOOKMARK — it used to write a `.known` row, which filed "study this
    /// later" as "I already know this". Returns false if already bookmarked.
    @discardableResult
    func addExpression(_ phrase: String) -> Bool {
        guard !exprKey(phrase).isEmpty, !isStudyingExpression(phrase) else { return false }
        setStudyingExpression(phrase, true)
        return true
    }

    /// Has the learner actually PRODUCED this expression (said it in a talk),
    /// as opposed to merely having a row for it?
    ///
    /// Bookmarking writes a `count: 0` row so the phrase shows up in the
    /// notebook, which made `hasExpression` true — and book mastery read that,
    /// so bookmarking an expression silently ticked it off as learned. Mastery
    /// needs evidence: a real use, or an explicit "I know it".
    func hasUsedExpression(_ phrase: String) -> Bool {
        let key = exprKey(phrase)
        guard let record = expressionRecords[key] else { return false }
        return record.state == .known || record.count > 0
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
            records[lemma] = Record(state: .known, firstAt: Date(), lastAt: Date(), count: 0,
                                    fromStudying: studying.contains(lemma) ? true : nil)
            save()
        }
        removeStudying(lemma)
        PracticeLog.shared.record(.word, finished: true)
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
                if Self.lemmas(in: [t.transcript]).contains(word) {
                    out.append(SourceSentence(text: t.transcript, audioURL: t.audioURL, source: "Talk"))
                }
            }
        }
        for d in WatchDialogueStore.shared.load() {
            for turn in d.turns where turn.speaker == "user" {
                if Self.lemmas(in: [turn.text]).contains(word) {
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
        pickupCandidates(fromFluentTexts: texts, atOrAbove: minLevel)
            .filter { records[$0] == nil }
    }

    /// The same words WITHOUT the "you don't know it yet" filter — every
    /// core-list lemma the fluent self used at or above the learner's level.
    ///
    /// This is what a talk BOOK's word chapter must be built from. Deriving it
    /// from `pickupWords` meant the list dropped a word the moment the learner
    /// learned it: the denominator shrank instead of the mastered count
    /// growing, so a book's word progress could never leave 0 — the one thing
    /// it was there to show. The list has to stay put; only the checkmarks
    /// move.
    /// `excludingLemmas`: what the LEARNER said in the same talk. The fluent
    /// self answers about whatever the learner brought up, so its turns are
    /// full of the learner's own words echoed back — "the Nawana app",
    /// "practice English" — and a word you already produce is not something
    /// to pick up. Without this the notebook filled itself with the
    /// learner's everyday vocabulary and then congratulated them for using it.
    func pickupCandidates(fromFluentTexts texts: [String], atOrAbove minLevel: CEFRLevel?,
                          excludingLemmas excluded: Set<String> = []) -> [String] {
        let minRank = minLevel.map(CoreVocabulary.levelRank) ?? 0
        let graded = Self.lemmas(in: texts)
            .compactMap { w -> (word: String, rank: Int)? in
                guard !excluded.contains(w), let lv = CoreVocabulary.level(of: w) else { return nil }
                let rank = CoreVocabulary.levelRank(lv)
                return rank >= minRank ? (w, rank) : nil
            }
            .sorted { $0.rank == $1.rank ? $0.word < $1.word : $0.rank < $1.rank }
            .map(\.word)

        // Words the graded pool doesn't carry. The pool is ~8k content words,
        // so an ordinary noun like "chore" isn't in it — and being absent used
        // to mean being invisible: not in the book's word chapter, not in the
        // day's hand, not even highlighted in the transcript it was said in.
        // A word the whole call was about went unmentioned because a list
        // didn't happen to grade it.
        //
        // They are NOT capped. A cap has to decide which ones die, and with
        // most of them said once there is nothing to decide it by — the first
        // version cut at 8 and let spelling break the tie, which is the very
        // complaint this exists to answer, re-made one level down.
        //
        // What orders them instead is evidence, and there are only two grades
        // of it. A word the fluent self came back to across several turns is
        // what the call was ABOUT, and no graded list can see that, so those
        // lead outright. A word said once is a weaker claim than a curated
        // level match, so those fill whatever the graded words left. Nothing
        // is dropped at either end; the prefix each caller takes does the
        // cutting, over a list already in the right order.
        let offList = Self.offListContentWords(in: texts).filter { !excluded.contains($0.key) }
        let recurring = offList.filter { $0.value > 1 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
        let saidOnce = offList.filter { $0.value == 1 }.keys.sorted()

        return recurring + graded + saidOnce
    }

    /// Content words in `texts` that the graded pool doesn't carry, with how
    /// many of those turns each appeared in.
    ///
    /// TURNS, not occurrences: the question a caller asks of this number is
    /// whether the fluent self kept coming back to the word, and a word said
    /// three times inside one sentence is a verbal tic, not a thread.
    ///
    /// Safe here and nowhere else: this reads the FLUENT SELF's turns, which
    /// are model-written, so no transcriber sits between the word and the
    /// check — the same reason `expressions_offered` needs no lexicon to
    /// stand behind it. The learner's own speech keeps the pool gate, where a
    /// mishearing would otherwise mint a word.
    ///
    /// Four things have to hold, and between them they throw out everything
    /// the pool's absence was protecting against:
    ///
    ///   • the tagger calls it a noun, verb, adjective or adverb — which
    ///     drops articles, pronouns, prepositions and every "oh / wow / uh";
    ///   • it isn't a name — Berlin, Jenny and Kakao are not vocabulary;
    ///   • three letters or more, letters only — no "ux", no stray tokens;
    ///   • the pool didn't leave it out on purpose (`CoreVocabulary.isUngraded`),
    ///     which is what separates "have" from "chore".
    ///
    /// What still gets through is an irregular form the tagger fails to
    /// reduce ("felt" for *feel*) — about one word in sixteen on real talk
    /// text, and deliberately not chased: a stray past tense sitting in a
    /// chapter of 24 costs less than the morphology table that would catch
    /// it, and far less than the call's own subject going unmentioned.
    ///
    /// Empty for Korean by construction: `koreanLemmas` can only return
    /// lexicon hits, because a dictionary form the wordlist can't confirm is
    /// a guess rather than a word to track. Japanese the same, one reason
    /// further: NLTagger has no part of speech for it, so the first filter
    /// above cannot even be asked.
    nonisolated static func offListContentWords(in texts: [String]) -> [String: Int] {
        guard !Self.matchesKorean, !Self.matchesJapanese else { return [:] }
        let language = Self.taggerLanguage
        let content: Set<String> = [
            NLTag.noun.rawValue, NLTag.verb.rawValue,
            NLTag.adjective.rawValue, NLTag.adverb.rawValue
        ]
        var out: [String: Int] = [:]
        var tagger: NLTagger?
        for text in texts {
            // Memoized per TEXT, like `lemmas(in:)` — three tagger schemes
            // over a turn is the single most expensive thing a book build does.
            let seenHere = offListMemo.value(for: text, language: language) {
                let t = tagger ?? NLTagger(tagSchemes: [.lemma, .lexicalClass, .nameType])
                tagger = t
                var found = Set<String>()
                t.string = text
                t.setLanguage(language, range: text.startIndex..<text.endIndex)
                t.enumerateTags(in: text.startIndex..<text.endIndex,
                                unit: .word, scheme: .lemma,
                                options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, range in
                    let lemma = (tag?.rawValue ?? String(text[range])).lowercased()
                    guard lemma.count >= 3,
                          lemma.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }),
                          !CoreVocabulary.set.contains(lemma),
                          !CoreVocabulary.isUngraded(lemma) else { return true }
                    guard let lexical = t.tag(at: range.lowerBound, unit: .word,
                                              scheme: .lexicalClass).0?.rawValue,
                          content.contains(lexical) else { return true }
                    let name = t.tag(at: range.lowerBound, unit: .word,
                                     scheme: .nameType).0?.rawValue
                    guard name == nil || name == NLTag.otherWord.rawValue else { return true }
                    // The tagger passes "Nawana" and "English" as ordinary words
                    // (measured 2026-09-16). The model's own spelling is the
                    // better witness: a capital letter anywhere but the start of
                    // a sentence is a name, a language, a brand — not vocabulary.
                    guard !Self.isCapitalizedMidSentence(text, range) else { return true }
                    found.insert(lemma)
                    return true
                }
                return found
            }
            for lemma in seenHere { out[lemma, default: 0] += 1 }
        }
        return out
    }

    /// Capitalized, and not because it opens a sentence.
    nonisolated private static func isCapitalizedMidSentence(_ text: String,
                                                              _ range: Range<String.Index>) -> Bool {
        guard let first = text[range].first, first.isUppercase else { return false }
        var i = range.lowerBound
        while i > text.startIndex {
            i = text.index(before: i)
            let c = text[i]
            if c.isWhitespace { continue }
            // Straight after a sentence end (or an opening quote after one)
            // capitals are grammar, not a name.
            return !".!?\n\"“‘'(".contains(c)
        }
        return false   // first word of the text
    }

    /// Best notebook key for a word the user tapped in a transcript: its lemma
    /// when the lemma is in the core list ("revitalizing" → "revitalize"),
    /// otherwise the cleaned word itself.
    nonisolated static func lookupKey(for raw: String) -> String {
        let w = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard !w.isEmpty else { return w }
        if Self.matchesKorean {
            return KoreanMorph.dictionaryForm(of: w, in: CoreVocabulary.set,
                                              rank: CoreVocabulary.koreanRank) ?? w
        }
        if Self.matchesJapanese {
            // The whole chunk, not one segment: 疲れた is 疲れ + た, and only
            // the た says the 疲れ is the verb and not the noun.
            return JapaneseMorph.headwords(in: w, lexicon: CoreVocabulary.set,
                                           forms: JapaneseMorph.bundledForms).first?.headword ?? w
        }
        // Memoized per word: a fresh NLTagger per call, and every book build
        // asks this of each of its pickup words, every list row of its word.
        return lookupKeyMemo.value(for: w, language: Self.taggerLanguage) {
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = w
            tagger.setLanguage(Self.taggerLanguage, range: w.startIndex..<w.endIndex)
            let lemma = tagger.tag(at: w.startIndex, unit: .word, scheme: .lemma).0?.rawValue.lowercased()
            if let lemma, !lemma.isEmpty {
                if CoreVocabulary.set.contains(lemma) { return lemma }
                // Ungraded words are tracked by lemma too now, so "chores" has to
                // resolve to "chore" or a transcript's own tokens would never line
                // up with the pickup list built from them — the word would be
                // collected and still not highlighted where it was said. Only when
                // the surface form is itself ungraded: a graded one is already the
                // key it should keep.
                if !CoreVocabulary.set.contains(w) { return lemma }
            }
            return w
        }
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

    /// Japanese: no spaces and no NLTagger lemma, so `JapaneseMorph` does
    /// both the cutting and the headword lookup.
    nonisolated private static var matchesJapanese: Bool {
        LanguageCatalog.language(LanguageScope.active)?.code == "ja"
    }

    /// NLTagger language for the current target. NLLanguage raw values ARE
    /// bare BCP-47 codes ("en", "de"), so the active code maps directly;
    /// an unsupported code just yields nil tags → surface-token fallback.
    nonisolated private static var taggerLanguage: NLLanguage {
        NLLanguage(rawValue: LanguageScope.active)
    }

    /// Headwords spoken across `texts`.
    ///
    /// `nonisolated static` because it's a pure function of text — no records,
    /// no disk — which lets `CarryoverDetector` ask the same question of a
    /// single turn without hopping to the main actor. Lemmatization is
    /// language-specific (English NLTagger vs. `KoreanMorph`) and that
    /// knowledge belongs here, not scattered across callers.
    nonisolated static func lemmas(in texts: [String]) -> Set<String> {
        if Self.matchesKorean { return koreanLemmas(in: texts) }
        if Self.matchesJapanese { return japaneseLemmas(in: texts) }
        let language = Self.taggerLanguage
        var out = Set<String>()
        var tagger: NLTagger?
        for text in texts {
            // Memoized per TEXT (see `TextMemo`): a turn's lemmas never
            // change, and every talk-book build re-asks for the same turns.
            out.formUnion(lemmaMemo.value(for: text, language: language) {
                let t = tagger ?? NLTagger(tagSchemes: [.lemma])
                tagger = t
                var found = Set<String>()
                // Original casing IN, lowercase OUT: German lemmatization reads
                // noun capitalization as a signal, while pool keys stay lowercase
                // (CoreVocabulary matches case-insensitively).
                t.string = text
                t.setLanguage(language, range: text.startIndex..<text.endIndex)
                t.enumerateTags(in: text.startIndex..<text.endIndex,
                                unit: .word, scheme: .lemma,
                                options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, range in
                    let lemma = (tag?.rawValue ?? String(text[range])).lowercased()
                    if lemma.count > 1 { found.insert(lemma) }
                    return true
                }
                return found
            })
        }
        return out
    }

    /// Korean: map each spoken token to a wordlist headword via the
    /// deterministic KoreanMorph heuristic (particle stripping, ending → 다).
    /// Only lexicon hits come back — a candidate that isn't a headword is a
    /// guess we couldn't verify, not a word to track.
    nonisolated private static func koreanLemmas(in texts: [String]) -> Set<String> {
        var out = Set<String>()
        for text in texts {
            // Memoized per TEXT like the tagger path: every candidate of every
            // token is tried against the lexicon, and every talk-book build
            // re-asks for the same turns.
            out.formUnion(lemmaMemo.value(for: text, language: .korean) {
                var found = Set<String>()
                let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                for token in tokens where !token.isEmpty {
                    if let head = KoreanMorph.dictionaryForm(of: token, in: CoreVocabulary.set,
                                                             rank: CoreVocabulary.koreanRank) {
                        found.insert(head)
                    }
                }
                return found
            })
        }
        return out
    }

    /// Japanese: segment, then map each stem to a wordlist headword
    /// (行きました → 行く, わかりません → 分かる). Lexicon hits only, like
    /// Korean — the same guess-versus-word line.
    nonisolated private static func japaneseLemmas(in texts: [String]) -> Set<String> {
        var out = Set<String>()
        for text in texts {
            for hit in JapaneseMorph.headwords(in: text, lexicon: CoreVocabulary.set,
                                               forms: JapaneseMorph.bundledForms) {
                out.insert(hit.headword)
            }
        }
        return out
    }

    // MARK: - Persistence

    /// New on-disk shape of the expressions-ingested meta. The legacy set
    /// rides along so sessions never re-touched keep their guard even after
    /// the file is rewritten in the new format.
    private struct ExpressionMeta: Codable {
        var keysBySession: [String: Set<String>]
        var legacySessions: Set<UUID>
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let dict = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = dict
        }
        if let data = try? Data(contentsOf: metaURL) {
            if let counts = try? JSONDecoder().decode([String: Int].self, from: data) {
                ingestedTextCounts = counts
            } else if let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
                // Pre-count format: how much was folded in is unknown, so
                // freeze those sessions as fully ingested (old behavior).
                ingestedTextCounts = Dictionary(
                    uniqueKeysWithValues: ids.map { ($0.uuidString, Int.max) })
            }
        }
        if let data = try? Data(contentsOf: studyingURL),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            studying = list
        }
        if let data = try? Data(contentsOf: expressionsURL),
           let dict = try? JSONDecoder().decode([String: Record].self, from: data) {
            expressionRecords = dict
        }
        if let data = try? Data(contentsOf: expressionsMetaURL) {
            if let meta = try? JSONDecoder().decode(ExpressionMeta.self, from: data) {
                ingestedExpressionKeys = meta.keysBySession
                legacyExpressionSessions = meta.legacySessions
            } else if let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
                legacyExpressionSessions = ids
            }
        }
        if let data = try? Data(contentsOf: studyingExpressionsURL),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            studyingExpressions = list
        }
        if let data = try? Data(contentsOf: dismissedExpressionsURL),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            dismissedExpressions = Set(list)
        }
        if let data = try? Data(contentsOf: removedByHandURL),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            removedByHand = Set(list)
        }
        if let data = try? Data(contentsOf: autoKeptURL),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            autoKept = Set(list)
        } else if !studying.isEmpty {
            // First run with the mark: nothing on disk says which notebook
            // words the learner kept and which a talk put there, so the
            // conservative reading wins — a word never dealt is treated as
            // auto-kept. The only thing that costs is a "you used what you
            // practiced" row, and that row must never list something the
            // learner didn't practice.
            autoKept = Set(studying.filter {
                StudyScheduleStore.shared.nextReview(.word, $0) == nil
            })
            saveAutoKept()
        }
    }

    private func saveAutoKept() {
        if let data = try? JSONEncoder().encode(Array(autoKept)) {
            try? data.write(to: autoKeptURL, options: [.atomic])
        }
        SyncEngine.noteChanged(.vocabAutoKept)
    }

    /// Notebook words the learner has actually PRACTICED — kept by hand, or
    /// dealt in a deck and put away — as opposed to ones a talk kept for them
    /// that they've never seen. Only these can be "something you studied".
    var practicedStudyingWords: [String] {
        studying.filter {
            !autoKept.contains($0) || StudyScheduleStore.shared.nextReview(.word, $0) != nil
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: [.atomic])
        }
        if let data = try? JSONEncoder().encode(ingestedTextCounts) {
            try? data.write(to: metaURL, options: [.atomic])
        }
        SyncEngine.noteChanged(.vocabRecord)
        SyncEngine.noteChanged(.vocabIngested)
    }

    private func saveStudying() {
        if let data = try? JSONEncoder().encode(studying) {
            try? data.write(to: studyingURL, options: [.atomic])
        }
        // Notebook words show on the home-screen widget — refresh its snapshot.
        StudyWidgetRefresher.schedule()
        SyncEngine.noteChanged(.vocabStudying)
    }

    private func saveStudyingExpressions() {
        if let data = try? JSONEncoder().encode(studyingExpressions) {
            try? data.write(to: studyingExpressionsURL, options: [.atomic])
        }
        // The Expressions widget shows only bookmarked phrases — refresh it.
        StudyWidgetRefresher.schedule()
        SyncEngine.noteChanged(.vocabStudyingExpression)
    }

    private func saveDismissedExpressions() {
        if let data = try? JSONEncoder().encode(Array(dismissedExpressions)) {
            try? data.write(to: dismissedExpressionsURL, options: [.atomic])
        }
        // A dismissed phrase may have been on the Expressions widget.
        StudyWidgetRefresher.schedule()
        SyncEngine.noteChanged(.vocabDismissed)
    }

    private func saveRemovedByHand() {
        if let data = try? JSONEncoder().encode(Array(removedByHand)) {
            try? data.write(to: removedByHandURL, options: [.atomic])
        }
        SyncEngine.noteChanged(.vocabRemovedByHand)
    }

    private func saveExpressions() {
        if let data = try? JSONEncoder().encode(expressionRecords) {
            try? data.write(to: expressionsURL, options: [.atomic])
        }
        if let data = try? JSONEncoder().encode(ExpressionMeta(
            keysBySession: ingestedExpressionKeys,
            legacySessions: legacyExpressionSessions)) {
            try? data.write(to: expressionsMetaURL, options: [.atomic])
        }
        SyncEngine.noteChanged(.vocabExpression)
        SyncEngine.noteChanged(.vocabExpressionIngested)
    }
}

/// Per-text memo for the NLTagger passes in `VocabStore.lemmas(in:)`,
/// `offListContentWords(in:)` and `lookupKey(for:)`.
///
/// Why: every talk-book build (`TalkCurriculum.build`) lemmatizes the whole
/// session again — the learner's turns, the fluent self's turns, and each
/// fluent turn once more per shadow candidate — and the home-screen widget
/// refresh rebuilds EVERY book on the main thread after every notebook
/// write. Measured 2026-09-23: 30 books ≈ 515 ms in the simulator, and that
/// ran between a tap on "I know" and the button repainting. A turn's text
/// never changes, so its lemmas are computed once per launch and read back.
///
/// Keyed on the tagger language too — a language switch must not hand
/// German lemmas to an English lookup. Bounded: past `cap` entries the table
/// is dropped whole (a few MB at most; the next build simply warms it again).
/// Lock-guarded because the callers are `nonisolated` and run from detached
/// tasks as well as the main actor.
final class TextMemo<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var table: [String: Value] = [:]
    private let cap: Int

    init(cap: Int = 8000) { self.cap = cap }

    func value(for text: String, language: NLLanguage,
               compute: () -> Value) -> Value {
        let key = language.rawValue + "\u{1}" + text
        lock.lock()
        if let hit = table[key] { lock.unlock(); return hit }
        lock.unlock()
        let value = compute()
        lock.lock()
        if table.count >= cap { table.removeAll(keepingCapacity: true) }
        table[key] = value
        lock.unlock()
        return value
    }

    /// Tests only.
    func removeAll() { lock.lock(); table.removeAll(); lock.unlock() }
}

private let lemmaMemo = TextMemo<Set<String>>()
private let offListMemo = TextMemo<Set<String>>()
private let lookupKeyMemo = TextMemo<String>()
