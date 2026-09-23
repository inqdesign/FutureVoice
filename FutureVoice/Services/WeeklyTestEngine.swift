import Foundation

/// Builds and grades the weekly test.
///
/// The test is the learner's own week turned into questions — nothing is
/// drawn from a generic bank. Four kinds, each from one shelf of the review
/// loop (see CLAUDE.md "The learning loop"):
///
///   meaning  ← the notebook (words the talks taught, `VocabStore.studying`)
///   gap      ← the fluent self's phrases (`expressionsOffered` / `expressionsUsed`)
///   build    ← the corrections (`DrillStore` cards with what the learner said)
///   listen   ← the fluent self's saved lines (`TurnAudioStore`)
///   speak    ← the fluent self's lines, said out loud and scored like a
///              shadow take (`ShadowTranscriber` + `ShadowEngine`)
///
/// Last week's wrong answers come back as this week's first items
/// (`maxRetake`), and once a month every wrong answer of the month is dealt
/// again as the monthly paper (`buildMonthly`).
///
/// Every grade is computed in code — the only model call is the dictionary
/// lookup that writes a word's meaning, which is free and cached. No LLM
/// ever decides whether an answer was right.
///
/// The paper is shuffled from the test's own id, so the same test reads the
/// same on every open, and a build on two devices from the same material
/// would still differ only by id — which is why the store keeps ONE test
/// per week.
@MainActor
enum WeeklyTestEngine {

    // MARK: - Sizing

    static let maxMeaning = 4
    static let maxGap = 3
    static let maxBuild = 3
    static let maxListen = 2
    static let maxSpeak = 2
    /// Wrong answers of the previous test dealt again this week.
    static let maxRetake = 3
    /// The monthly paper's ceiling.
    static let maxMonthly = 20
    /// A spoken line passes at the shadow browser's own retry bar.
    static let speakPassScore = PracticeStats.retryThreshold
    /// Below this the week has too little in it to be a test — the tab says
    /// so instead of dealing three questions and calling it a week.
    static let minItems = 5
    static let choiceCount = 4
    static let listenChoiceCount = 3
    /// Extra tiles for a build item, taken from the learner's OWN wrong
    /// version — the words the correction removed are the tempting ones.
    static let maxDecoyTiles = 2

    /// How far back the window reaches with no previous test: one week.
    static let defaultWindow: TimeInterval = 7 * 86_400

    // MARK: - Window

    /// The material window: since the last test was built, else one week.
    static func window(lastTest: WeeklyTest?, now: Date) -> (start: Date, end: Date) {
        let start = lastTest?.periodEnd ?? now.addingTimeInterval(-defaultWindow)
        return (min(start, now), now)
    }

    // MARK: - Build

    /// Builds this week's test, or nil when the window holds fewer than
    /// `minItems` gradable things. Reads the active language's stores.
    static func build(
        lastTest: WeeklyTest?,
        appState: AppState,
        now: Date = Date()
    ) async -> WeeklyTest? {
        let (start, end) = window(lastTest: lastTest, now: now)
        let id = UUID()
        var rng = WeeklyTestRandom(seed: id)

        let allSessions = SessionStore.shared.load()
            .filter { $0.archivedAt == nil && $0.mode == .conversation }
        let windowSessions = allSessions.filter {
            guard let ended = $0.endedAt else { return false }
            return ended > start && ended <= end
        }
        let fluentTurns = windowSessions.flatMap { s in
            s.turns.filter { $0.role == .fluentSelf && !$0.excludedFromScoring }
                .map { (session: s, turn: $0) }
        }
        let userTurns = windowSessions.flatMap { s in
            s.turns.filter { $0.role == .user && !$0.excludedFromScoring }
                .map { (session: s, turn: $0) }
        }

        var items: [WeeklyTestItem] = []
        items += await meaningItems(fluentTexts: fluentTurns.map(\.turn.transcript),
                                    appState: appState, rng: &rng)
        items += gapItems(sessions: windowSessions, fluentTurns: fluentTurns,
                          userTurns: userTurns, appState: appState, rng: &rng)
        items += buildItems(start: start, end: end, now: now, rng: &rng)
        let listens = listenItems(fluentTurns: fluentTurns, allSessions: allSessions, rng: &rng)
        items += listens
        items += speakItems(fluentTurns: fluentTurns, sessions: windowSessions,
                            excluding: Set(listens.map { CarryoverDetector.normalized($0.answer) }),
                            rng: &rng)
        // What last week got wrong is asked again first — the test is a
        // review, and a miss is the most certain material there is.
        if let last = lastTest, last.isFinished, !last.isMonthly {
            let fresh = Set(items.map { itemKey($0) })
            items += retakes(from: [last], limit: maxRetake, excluding: fresh,
                             language: appState.targetLanguage, rng: &rng)
        }

        #if DEBUG
        let counts = Dictionary(grouping: items, by: \.kind).mapValues(\.count)
        print("WEEKLYTEST built: sessions=\(windowSessions.count) items=\(counts)")
        #endif
        guard items.count >= minItems else { return nil }
        items.shuffle(using: &rng)
        // A test opens on something you can answer by reading — never on the
        // one item that needs the speaker on.
        if let first = items.first, first.kind == .listen,
           let swap = items.firstIndex(where: { $0.kind != .listen }) {
            items.swapAt(0, swap)
        }
        return WeeklyTest(id: id, targetLanguage: appState.targetLanguage,
                          periodStart: start, periodEnd: end, createdAt: now, items: items)
    }

    // MARK: - Monthly

    /// The monthly paper: every item the given weekly tests got wrong, each
    /// asked once, choices reshuffled. nil under `minItems` — a month with
    /// little wrong in it has nothing to sit.
    static func buildMonthly(from tests: [WeeklyTest], targetLanguage: String,
                             now: Date = Date()) -> WeeklyTest? {
        let id = UUID()
        var rng = WeeklyTestRandom(seed: id)
        var items = retakes(from: tests, limit: maxMonthly, excluding: [],
                            language: targetLanguage, rng: &rng)
        guard items.count >= minItems else { return nil }
        items.shuffle(using: &rng)
        if let first = items.first, first.kind == .listen || first.kind == .speak,
           let swap = items.firstIndex(where: { $0.kind != .listen && $0.kind != .speak }) {
            items.swapAt(0, swap)
        }
        let start = tests.compactMap(\.finishedAt).min() ?? now
        return WeeklyTest(id: id, targetLanguage: targetLanguage, kind: .monthly,
                          periodStart: start, periodEnd: now, createdAt: now, items: items)
    }

    /// Wrong answers of `tests`, newest test first, one per distinct answer,
    /// as fresh items with their choices reshuffled.
    private static func retakes(from tests: [WeeklyTest], limit: Int, excluding: Set<String>,
                                language: String, rng: inout WeeklyTestRandom) -> [WeeklyTestItem] {
        var out: [WeeklyTestItem] = []
        var seen = excluding
        for test in tests.sorted(by: { $0.createdAt > $1.createdAt }) {
            let wrong = Set(test.answers.filter { !$0.correct }.map(\.itemId))
            for item in test.items where wrong.contains(item.id) && isValid(item, language: language) {
                guard out.count < limit else { return out }
                let key = itemKey(item)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                // Build tiles are dealt afresh from the two lines, so a stored
                // item picks up today's decoy rule instead of its old tiles.
                let options = item.kind == .build
                    ? buildTiles(target: item.answer, source: item.prompt, rng: &rng)
                    : item.options.shuffled(using: &rng)
                out.append(WeeklyTestItem(id: UUID(), kind: item.kind, prompt: item.prompt, answer: item.answer,
                                          options: options, sessionId: item.sessionId, turnId: item.turnId,
                                          cardId: item.cardId, note: item.note, isRetake: true))
            }
        }
        return out
    }

    /// This test's misses dealt again as a paper of their own — played in
    /// place, never saved. nil when nothing was missed.
    static func retryPaper(from test: WeeklyTest) -> WeeklyTest? {
        var rng = WeeklyTestRandom(seed: UUID())
        let items = retakes(from: [test], limit: maxMonthly, excluding: [],
                            language: test.targetLanguage, rng: &rng)
        guard !items.isEmpty else { return nil }
        var paper = WeeklyTest(id: UUID(), targetLanguage: test.targetLanguage, kind: test.kind,
                               periodStart: test.periodStart, periodEnd: test.periodEnd,
                               createdAt: Date(), items: items)
        paper.startedAt = Date()
        return paper
    }

    /// An item that still passes today's rules. Tests are frozen when built,
    /// so an item minted before a rule existed (the Korean-sourced card of
    /// 2026-09-23) has to be caught wherever a stored item is reused.
    /// `language` is the TEST's own, never the active pointer: a stored item
    /// is judged by the language it was written for.
    static func isValid(_ item: WeeklyTestItem, language: String) -> Bool {
        func ok(_ text: String) -> Bool { isInTargetScript(text, language: language) }
        guard ok(item.answer) else { return false }
        switch item.kind {
        case .build:
            return ok(item.prompt) && item.options.allSatisfy(ok)
        case .gap:
            return ok(item.prompt.replacingOccurrences(of: blankMark, with: "")) && item.options.allSatisfy(ok)
        case .meaning, .listen:
            return item.options.allSatisfy(ok)
        case .speak:
            return true
        }
    }

    /// A test in progress with its not-yet-answered invalid items removed.
    /// Answered ones stay: their answers are on record. Returns nil when
    /// nothing changed.
    static func pruned(_ test: WeeklyTest) -> WeeklyTest? {
        let answered = Set(test.answers.map(\.itemId))
        var changed = false
        var rng = WeeklyTestRandom(seed: test.id)
        var kept: [WeeklyTestItem] = []
        for item in test.items {
            if answered.contains(item.id) { kept.append(item); continue }
            guard isValid(item, language: test.targetLanguage) else { changed = true; continue }
            // An unanswered build item re-deals its tiles under today's rule.
            if item.kind == .build {
                let fresh = buildTiles(target: item.answer, source: item.prompt, rng: &rng)
                if Set(fresh.map(tileKey)) != Set(item.options.map(tileKey)) {
                    var copy = item
                    copy = WeeklyTestItem(id: item.id, kind: .build, prompt: item.prompt, answer: item.answer,
                                          options: fresh, sessionId: item.sessionId, turnId: item.turnId,
                                          cardId: item.cardId, note: item.note, isRetake: item.isRetake)
                    kept.append(copy); changed = true; continue
                }
            }
            kept.append(item)
        }
        guard changed else { return nil }
        var t = test
        t.items = kept
        return t
    }

    /// One identity per thing asked, whatever the wording of the prompt.
    static func itemKey(_ item: WeeklyTestItem) -> String {
        "\(item.kind.rawValue)|\(CarryoverDetector.normalized(item.answer))"
    }

    // MARK: speak

    /// Lines to say out loud: fluent-self sentences of 4–16 words, the ones
    /// carrying a phrase the summary offered first — that is what the talk
    /// was teaching — and never a line the listen items already used.
    private static func speakItems(
        fluentTurns: [(session: Session, turn: Turn)],
        sessions: [Session],
        excluding: Set<String>,
        rng: inout WeeklyTestRandom
    ) -> [WeeklyTestItem] {
        let offered = Set(sessions.flatMap { $0.summary?.expressionsOffered ?? [] }.map { $0.lowercased() })
        struct Line { let text: String; let session: Session; let lineId: UUID; let weight: Int }
        var lines: [Line] = []
        var seen = excluding
        for entry in fluentTurns {
            let parts = TalkCurriculum.sentences(in: entry.turn.transcript)
            for (index, sentence) in parts.enumerated() {
                let n = WordSplitter.count(sentence)
                guard n >= 4, n <= 16, isInTargetScript(sentence) else { continue }
                let key = CarryoverDetector.normalized(sentence)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let lower = sentence.lowercased()
                let weight = offered.filter { lower.contains($0) }.count
                // The line's identity is the talk book's: a one-sentence turn
                // keeps its turn id (its recorded audio matches the text), a
                // sentence cut from a longer turn gets the book's sentence id.
                // The turn's audio must never play for a sentence — it carries
                // the neighbours too (heard on device, 2026-09-23).
                let lineId = parts.count == 1 ? entry.turn.id
                    : TalkCurriculum.sentenceLineId(for: entry.turn.id, index: index)
                lines.append(Line(text: sentence, session: entry.session, lineId: lineId, weight: weight))
            }
        }
        let shuffled = lines.shuffled(using: &rng).sorted { $0.weight > $1.weight }
        return shuffled.prefix(maxSpeak).map {
            WeeklyTestItem(id: UUID(), kind: .speak, prompt: "", answer: $0.text, options: [],
                           sessionId: $0.session.id, turnId: $0.lineId)
        }
    }

    // MARK: meaning

    private static func meaningItems(
        fluentTexts: [String], appState: AppState, rng: inout WeeklyTestRandom
    ) async -> [WeeklyTestItem] {
        let vocab = VocabStore.shared
        let weekLemmas = VocabStore.lemmas(in: fluentTexts)
        // Notebook words the week's talks used lead; the rest of the notebook
        // follows; words the learner produced this week close the list.
        var candidates: [String] = []
        var seen = Set<String>()
        func add(_ w: String) {
            let k = w.lowercased()
            guard !k.isEmpty, !seen.contains(k), isInTargetScript(w) else { return }
            seen.insert(k); candidates.append(w)
        }
        vocab.studying.filter { weekLemmas.contains($0.lowercased()) }.forEach(add)
        vocab.studying.forEach(add)
        vocab.usedWords(withinDays: 7).forEach(add)

        // Decoys: the learner's own pool first (all words they are studying,
        // so none is trivially out of place), then the graded list at their
        // level — same part of speech where the tagger can tell, so a verb's
        // gloss isn't answered by ruling out three nouns.
        let level = appState.proficiency
        // Languages without a graded list (es, fr, it, pt, zh) fall back to
        // the learner's own known/used words — still their vocabulary, still
        // in the target script.
        var graded = CoreVocabulary.entries
            .filter { $0.level == level && !seen.contains($0.word.lowercased()) }
            .map(\.word)
            .shuffled(using: &rng)
        if graded.count < choiceCount {
            graded += vocab.records.keys
                .filter { !seen.contains($0.lowercased()) && isInTargetScript($0) }
                .shuffled(using: &rng)
        }
        func decoys(for word: String) -> [String] {
            let pos = WordLore.partOfSpeech(word)
            let own = candidates.filter { $0.lowercased() != word.lowercased() }
            let samePOS = graded.filter { pos == nil || WordLore.partOfSpeech($0) == pos }
            return Array((own.shuffled(using: &rng) + samePOS.prefix(30).shuffled(using: &rng) + graded)
                .prefix(choiceCount - 1))
        }

        var out: [WeeklyTestItem] = []
        for word in candidates {
            guard out.count < maxMeaning else { break }
            guard let entry = await WordLore.entry(for: word, native: appState.nativeLanguage,
                                                   target: appState.targetLanguage),
                  let sense = entry.senses.first?.meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sense.isEmpty,
                  // A gloss that just repeats the word teaches nothing and
                  // gives the answer away.
                  !sense.lowercased().contains(word.lowercased())
            else { continue }
            let decoys = decoys(for: word)
            guard decoys.count == choiceCount - 1 else { continue }
            let options = ([word] + decoys).shuffled(using: &rng)
            out.append(WeeklyTestItem(id: UUID(), kind: .meaning, prompt: sense,
                                      answer: word, options: options))
        }
        return out
    }

    // MARK: gap

    private static func gapItems(
        sessions: [Session],
        fluentTurns: [(session: Session, turn: Turn)],
        userTurns: [(session: Session, turn: Turn)],
        appState: AppState,
        rng: inout WeeklyTestRandom
    ) -> [WeeklyTestItem] {
        struct Candidate { let phrase: String; let sentence: String; let session: Session; let turn: Turn }
        var candidates: [Candidate] = []
        var seen = Set<String>()
        func collect(_ phrases: [String], in turns: [(session: Session, turn: Turn)]) {
            for phrase in phrases {
                let key = ExpressionCatalog.normalizedKey(phrase)
                guard !key.isEmpty, !seen.contains(key), isInTargetScript(phrase) else { continue }
                guard let hit = firstSentence(containing: phrase, in: turns) else { continue }
                seen.insert(key)
                candidates.append(Candidate(phrase: phrase, sentence: hit.sentence,
                                            session: hit.session, turn: hit.turn))
            }
        }
        // The fluent self's phrases first — what the week offered and the
        // learner hasn't said — then the ones the learner did use.
        for s in sessions { collect(s.summary?.expressionsOffered ?? [], in: fluentTurns) }
        for s in sessions { collect(s.summary?.expressionsUsed ?? [], in: userTurns) }

        // Decoys: every other phrase of the week first — they are the ones
        // that could plausibly fit — and the library only to fill the row.
        var weekPool = candidates.map(\.phrase)
        for s in sessions {
            weekPool += (s.summary?.expressionsOffered ?? []) + (s.summary?.expressionsUsed ?? [])
        }
        weekPool = dedupe(weekPool, key: ExpressionCatalog.normalizedKey)
        let libraryPool = dedupe(ExpressionCatalog.all(scenarios: appState.scenarios).map(\.text),
                                 key: ExpressionCatalog.normalizedKey)

        var out: [WeeklyTestItem] = []
        for c in candidates.shuffled(using: &rng) {
            guard out.count < maxGap else { break }
            let key = ExpressionCatalog.normalizedKey(c.phrase)
            func fits(_ p: String) -> Bool {
                ExpressionCatalog.normalizedKey(p) != key && !c.sentence.lowercased().contains(p.lowercased())
            }
            let decoys = dedupe(weekPool.filter(fits).shuffled(using: &rng)
                                + libraryPool.filter(fits).shuffled(using: &rng),
                                key: ExpressionCatalog.normalizedKey)
                .prefix(choiceCount - 1)
            guard decoys.count == choiceCount - 1,
                  let prompt = blank(c.phrase, in: c.sentence) else { continue }
            let options = ([c.phrase] + decoys).shuffled(using: &rng)
            out.append(WeeklyTestItem(id: UUID(), kind: .gap, prompt: prompt, answer: c.phrase,
                                      options: options, sessionId: c.session.id, turnId: c.turn.id))
        }
        return out
    }

    /// The first sentence in `turns` containing `phrase`, case-insensitive,
    /// short enough to read as one line. Sentences come from
    /// `TalkCurriculum.sentences(in:)` so a gap item never shows a whole turn.
    private static func firstSentence(
        containing phrase: String, in turns: [(session: Session, turn: Turn)]
    ) -> (sentence: String, session: Session, turn: Turn)? {
        let needle = phrase.lowercased()
        for entry in turns {
            for sentence in TalkCurriculum.sentences(in: entry.turn.transcript) {
                guard sentence.lowercased().contains(needle) else { continue }
                let n = WordSplitter.count(sentence)
                guard n >= 4, n <= 30, isInTargetScript(sentence) else { continue }
                return (sentence, entry.session, entry.turn)
            }
        }
        return nil
    }

    static let blankMark = "______"

    /// `sentence` with the first case-insensitive occurrence of `phrase`
    /// replaced by the blank mark.
    static func blank(_ phrase: String, in sentence: String) -> String? {
        guard let range = sentence.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        return sentence.replacingCharacters(in: range, with: blankMark)
    }

    // MARK: build

    private static func buildItems(
        start: Date, end: Date, now: Date, rng: inout WeeklyTestRandom
    ) -> [WeeklyTestItem] {
        let cards = DrillStore.shared.load().filter { card in
            guard card.box < DrillStore.maxBox,
                  !card.sourcePhrase.trimmingCharacters(in: .whitespaces).isEmpty,
                  isInTargetScript(card.targetPhrase), isInTargetScript(card.sourcePhrase) else { return false }
            let touched = [card.createdAt, card.lastReviewedAt].compactMap { $0 }
            guard touched.contains(where: { $0 > start && $0 <= end }) else { return false }
            // An unspaced language's "words" are segments — a particle is
            // one — so a plain sentence runs longer in tiles.
            let n = WordSplitter.count(card.targetPhrase)
            return n >= 3 && n <= (WordSplitter.spaced ? 12 : 18)
        }
        // Due cards first (the test is a review), then the newest.
        let ordered = cards.sorted {
            let aDue = $0.nextReviewAt <= now, bDue = $1.nextReviewAt <= now
            if aDue != bDue { return aDue }
            return $0.createdAt > $1.createdAt
        }
        var out: [WeeklyTestItem] = []
        var seen = Set<String>()
        for card in ordered {
            guard out.count < maxBuild else { break }
            let key = DrillStore.matchKey(card.targetPhrase)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let tiles = buildTiles(target: card.targetPhrase, source: card.sourcePhrase, rng: &rng)
            // The same trim the drill card does: a turn can be a rambling
            // paragraph of fillers, and only the sentence the correction is
            // about belongs on a test card.
            let said = DrillStore.relevantFragment(of: card.sourcePhrase,
                                                   matching: card.targetPhrase, maxChars: 120)
            out.append(WeeklyTestItem(id: UUID(), kind: .build, prompt: said,
                                      answer: card.targetPhrase, options: tiles,
                                      sessionId: card.sourceSessionId, turnId: card.sourceTurnId,
                                      cardId: card.id, note: card.reason))
        }
        return out
    }

    /// The target's words plus up to `maxDecoyTiles` decoys, shuffled. A tile
    /// set that spells the answer in order is not a test.
    ///
    /// A decoy is a word the correction REPLACED — "very" where the fluent
    /// line says "really" — never one it merely left out. "I felt the intro
    /// section took too long" → "I felt like the intro took a bit too long"
    /// drops "section" in passing; a learner who lays "the intro section
    /// took" has said something fluent and was marked wrong for it (device,
    /// 2026-09-23). Aligning the two lines tells the cases apart: a gap where
    /// BOTH sides have words is a substitution and its source words tempt; a
    /// gap with source words alone is an omission and they stay off the table.
    static func buildTiles(target: String, source: String, rng: inout WeeklyTestRandom) -> [String] {
        let targetWords = WordSplitter.words(target)
        let decoys = dedupe(replacedWords(source: WordSplitter.words(source), target: targetWords)
            .filter { isInTargetScript($0) }, key: tileKey)
            .shuffled(using: &rng)
            .prefix(maxDecoyTiles)
        var tiles = (targetWords + decoys).shuffled(using: &rng)
        // Don't hand the sentence back in order.
        if tiles.count > 2, tiles.map(tileKey) == targetWords.map(tileKey) {
            tiles.swapAt(0, tiles.count - 1)
        }
        return tiles
    }

    // MARK: listen

    private static func listenItems(
        fluentTurns: [(session: Session, turn: Turn)],
        allSessions: [Session],
        rng: inout WeeklyTestRandom
    ) -> [WeeklyTestItem] {
        func fits(_ text: String) -> Bool {
            let n = WordSplitter.count(text)
            return n >= 4 && n <= 20 && isInTargetScript(text)
        }
        let withAudio = fluentTurns.filter {
            fits($0.turn.transcript) && TurnAudioStore.shared.url(for: $0.turn.id) != nil
        }
        // Decoys: other fluent lines of a similar length — this week's first,
        // then any talk's.
        var decoyPool = fluentTurns.map(\.turn.transcript).filter(fits)
        decoyPool += allSessions.flatMap { $0.turns }
            .filter { $0.role == .fluentSelf && fits($0.transcript) }
            .map(\.transcript)
        decoyPool = dedupe(decoyPool, key: { CarryoverDetector.normalized($0) })

        var out: [WeeklyTestItem] = []
        var seen = Set<String>()
        for entry in withAudio.shuffled(using: &rng) {
            guard out.count < maxListen else { break }
            let text = entry.turn.transcript
            let key = CarryoverDetector.normalized(text)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let decoys = decoyPool
                .filter { CarryoverDetector.normalized($0) != key }
                .shuffled(using: &rng)
                .prefix(listenChoiceCount - 1)
            guard decoys.count == listenChoiceCount - 1 else { continue }
            let options = ([text] + decoys).shuffled(using: &rng)
            out.append(WeeklyTestItem(id: UUID(), kind: .listen, prompt: "", answer: text,
                                      options: options, sessionId: entry.session.id,
                                      turnId: entry.turn.id))
        }
        return out
    }

    // MARK: - Grading

    /// A choice item: the picked option against the answer.
    static func isCorrect(_ item: WeeklyTestItem, chosen: String) -> Bool {
        CarryoverDetector.normalized(chosen) == CarryoverDetector.normalized(item.answer)
    }

    /// A build item: the tiles in the order the learner laid them.
    static func isCorrect(_ item: WeeklyTestItem, tiles: [String]) -> Bool {
        tiles.map(tileKey) == WordSplitter.words(item.answer).map(tileKey)
    }

    /// Source words that sit in a substitution gap of the source↔target
    /// alignment: the words the correction swapped for others.
    static func replacedWords(source: [String], target: [String]) -> [String] {
        let a = source.map(tileKey), b = target.map(tileKey)
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var out: [String] = []
        var gapSource: [String] = [], gapTargetCount = 0
        func closeGap() {
            if gapTargetCount > 0 { out += gapSource }
            gapSource = []; gapTargetCount = 0
        }
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] { closeGap(); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { gapSource.append(source[i]); i += 1 }
            else { gapTargetCount += 1; j += 1 }
        }
        gapSource += source[i...]
        gapTargetCount += b.count - j
        closeGap()
        return out
    }

    /// Which laid tiles are where the answer wants them, and which of the
    /// answer's own words never arrived.
    ///
    /// Painting every tile red when one word is out of place says nothing —
    /// the learner had eight of nine right (seen on device, 2026-09-23). The
    /// longest common subsequence against the answer is what separates
    /// "in the right order" from "what went wrong": a tile inside it is
    /// placed correctly, everything else is the mistake.
    struct TileCheck {
        /// One per laid tile, in the order they were laid.
        var correct: [Bool]
        /// One per word of the answer.
        var answerMatched: [Bool]
    }

    static func tileCheck(tiles: [String], answer: String) -> TileCheck {
        let a = tiles.map(tileKey)
        let b = WordSplitter.words(answer).map(tileKey)
        guard !a.isEmpty, !b.isEmpty else {
            return TileCheck(correct: Array(repeating: false, count: a.count),
                             answerMatched: Array(repeating: false, count: b.count))
        }
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var correct = Array(repeating: false, count: a.count)
        var matched = Array(repeating: false, count: b.count)
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                correct[i] = true; matched[j] = true; i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return TileCheck(correct: correct, answerMatched: matched)
    }

    /// Tiles joined back into the sentence the learner built.
    static func sentence(fromTiles tiles: [String]) -> String {
        tiles.joined(separator: WordSplitter.spaced ? " " : "")
    }

    static func tileKey(_ word: String) -> String { CarryoverDetector.normalized(word) }

    // MARK: - Writing back

    /// What a finished test does to the review loop. Runs once per test
    /// (the store stamps `appliedAt`); an answer is a claim, so nothing here
    /// retires anything — see CLAUDE.md "USED outranks KNOWN".
    ///
    ///   meaning  right → the word waits 3 days · wrong → back in the notebook, due now
    ///   gap      right → the phrase waits 3 days · wrong → bookmarked, due now
    ///   build    right → one Leitner rung up · wrong → one rung down
    ///   listen   nothing to write; recognition is not production
    static func apply(_ test: WeeklyTest, now: Date = Date()) {
        let vocab = VocabStore.shared
        let cards = Dictionary(uniqueKeysWithValues: DrillStore.shared.load().map { ($0.id, $0) })
        let threeDays: TimeInterval = 3 * 86_400
        let byId = Dictionary(uniqueKeysWithValues: test.items.map { ($0.id, $0) })
        for answer in test.answers {
            guard let item = byId[answer.itemId] else { continue }
            switch item.kind {
            case .meaning:
                let word = item.answer
                if answer.correct {
                    PracticeLog.shared.record(.word)
                    if vocab.isStudying(word) { ReviewQueue.snooze(.word, word, for: threeDays) }
                } else {
                    vocab.addStudying(word)              // records the rep itself
                    ReviewQueue.retire(.word, word)      // clears the return date → due now
                }
            case .gap:
                let phrase = item.answer
                if answer.correct {
                    PracticeLog.shared.record(.expression)
                    if vocab.isStudyingExpression(phrase) {
                        ReviewQueue.snooze(.expression, phrase, for: threeDays)
                    }
                } else {
                    if !vocab.isStudyingExpression(phrase) { vocab.setStudyingExpression(phrase, true) }
                    else { PracticeLog.shared.record(.expression) }
                    ReviewQueue.retire(.expression, phrase)
                }
            case .build:
                guard let id = item.cardId, let card = cards[id] else { continue }
                if answer.correct { DrillStore.shared.markCorrect(card, at: now) }
                else { DrillStore.shared.markIncorrect(card, at: now) }
                PracticeLog.shared.record(.drill)
            case .listen, .speak:
                // Recognition writes nothing; a spoken line is already on
                // file as a shadow attempt, saved by the screen that heard it.
                break
            }
        }
    }

    // MARK: - Helpers

    /// Whether `text` is written in the target language's script. A talk
    /// where the learner slipped into their own language still mints
    /// correction cards and transcripts; a test item built on one of those
    /// asks nonsense ("한번 나올게 해줘 시계" → tiles in two scripts, seen on
    /// device 2026-09-23). Letters of the expected script must be at least
    /// nine in ten of all letters; digits and punctuation don't count.
    static func isInTargetScript(_ text: String, language: String = LanguageScope.active) -> Bool {
        var letters = 0, matching = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if scriptMatches(scalar, language: language) { matching += 1 }
        }
        guard letters > 0 else { return false }
        return Double(matching) / Double(letters) >= 0.9
    }

    private static func scriptMatches(_ scalar: Unicode.Scalar, language: String) -> Bool {
        let v = scalar.value
        let hangul = (0xAC00...0xD7A3).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v)
        let kana = (0x3040...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) || (0xFF66...0xFF9F).contains(v)
        let han = (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x20000...0x2A6DF).contains(v)
        let latin = v < 0x0250 || (0x1E00...0x1EFF).contains(v)
        switch language {
        case "ko": return hangul
        case "ja": return kana || han
        case "zh", "zh-Hans", "zh-Hant": return han
        default: return latin
        }
    }

    private static func dedupe(_ list: [String], key: (String) -> String) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert(key($0)).inserted }
    }
}

/// SplitMix64 seeded from a test id, so a paper shuffles the same way on
/// every open. `SystemRandomNumberGenerator` would reorder the choices each
/// time the screen redrew.
struct WeeklyTestRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UUID) {
        let b = seed.uuid
        let hi = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        state = hi &+ 0x9E37_79B9_7F4A_7C15
    }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
