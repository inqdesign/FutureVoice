import Foundation

/// Builds and grades the weekly test.
///
/// The test is the learner's own week turned into questions — nothing is
/// drawn from a generic bank. Four kinds, each from one shelf of the review
/// loop (see CLAUDE.md "The learning loop"):
///
///   meaning  ← the notebook (words the talks taught, `VocabStore.studying`)
///   gap      ← the Expressions page's "To study" list (`ExpressionCatalog
///              .toStudy`), in the line it was heard in
///   translate← the corrections (`DrillStore` cards) and the profile's
///              recurring mistakes, asked in a NEW sentence: a native-language
///              line to say in the target language, graded in code against
///              the pattern's required spans and the learner's own wrong
///              forms (replaced `build`, 2026-10-08 — founder: "a mistake is
///              learned by using its pattern again, not by re-reading the
///              sentence it was in")
///   listen   ← the fluent self's saved lines (`TurnAudioStore`), heard and
///              rebuilt from tiles — dictation, not a pick from three
///   speak    ← the fluent self's lines, said out loud and scored like a
///              shadow take (`ShadowTranscriber` + `ShadowEngine`)
///
/// listen and speak take only lines that carry a "To study" expression, and
/// never a call's opening line. A learner reported (2026-10-08) that the
/// test "felt random": the opener's greeting came up to be repeated, and a
/// correction card — one clause since 2026-09-27 — was shuffled into four
/// tiles that rebuilt nothing worth knowing. Every item now has a reason the
/// learner can see: a phrase they are studying, or a sentence they got wrong.
///   grammar  ← the week report's recurring grammar points (`WeekRecap.Coach`),
///              else the profile's recurring mistakes — rule + one of the
///              learner's own lines, rebuilt right from tiles
///   upgrade  ← the week report's leaned-on words — the learner's line with
///              the word marked, pick the better one
///
/// The last few weeks' wrong answers come back in this week's paper
/// (`maxRetake`, from `retakeWeeks` tests) until they are answered right.
/// There is ONE test: a separate monthly paper gathered the same misses
/// and was removed on 2026-10-05 (founder: "don't keep a weekly and a
/// monthly test apart").
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
    static let maxRewrite = 3
    static let maxTranslate = 3
    /// How long a paper waits for its translate items to be written.
    static let translateWait: TimeInterval = 30
    static let maxListen = 2
    static let maxSpeak = 2
    static let maxGrammar = 2
    static let maxUpgrade = 2
    /// How long a paper waits for the week report's coach to be written
    /// when the deck hasn't been opened yet. The writing carries on past it
    /// (and lands in the report); the paper just goes without.
    static let coachWait: TimeInterval = 25
    /// Wrong answers of recent tests dealt again this week.
    static let maxRetake = 5
    /// How many finished weekly papers the retakes are drawn from — about a
    /// month, which is what the monthly paper used to gather.
    static let retakeWeeks = 4
    /// Ceiling for a paper of one test's own misses (`retryPaper`).
    static let maxRetry = 20
    /// A spoken line passes at the shadow browser's own retry bar.
    static let speakPassScore = PracticeStats.retryThreshold
    /// Below this the week has too little in it to be a test — the tab says
    /// so instead of dealing three questions and calling it a week.
    static let minItems = 5
    static let choiceCount = 4
    /// Extra tiles for a build item, taken from the learner's OWN wrong
    /// version — the words the correction removed are the tempting ones.
    static let maxDecoyTiles = 2

    /// How far back the window reaches with no previous test: one week.
    static let defaultWindow: TimeInterval = 7 * 86_400

    // MARK: - Window

    /// The material window: since the last WEEKLY test was built, else one
    /// week. A monthly paper is never the anchor — it is built from the
    /// weeklies, minutes before or after one, and anchoring on it would
    /// start the week's window at that moment (a Saturday that opened the
    /// monthly first then found the weekly "thin").
    static func window(lastTest: WeeklyTest?, now: Date) -> (start: Date, end: Date) {
        let anchor = lastTest.flatMap { $0.isMonthly ? nil : $0 }
        let start = anchor?.periodEnd ?? now.addingTimeInterval(-defaultWindow)
        return (min(start, now), now)
    }

    // MARK: - Build

    /// Builds this week's test, or nil when the window holds fewer than
    /// `minItems` gradable things. Reads the active language's stores.
    /// `lastTest` is the latest WEEKLY paper (`WeeklyTestStore.latestWeekly`);
    /// `recentTests` the finished weekly papers the retakes come from.
    static func build(
        lastTest: WeeklyTest?,
        recentTests: [WeeklyTest] = [],
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
        items += await meaningItems(sessions: windowSessions, appState: appState, rng: &rng)
        // What the Expressions page lists under "To study" — the learner's
        // own study list, and the reason a fluent-self line is worth a
        // question at all.
        let toStudy = ExpressionCatalog.toStudy(scenarios: appState.scenarios, sessions: allSessions)
            .filter { isInTargetScript($0.text) }
        let studyPhrases = toStudy.map { $0.text.lowercased() }
        // A call's first fluent-self line is its greeting — the same few
        // words every call, never the material.
        let openers = Set(allSessions.compactMap { s in s.turns.first { $0.role == .fluentSelf }?.id })
        let teachingTurns = fluentTurns.filter { !openers.contains($0.turn.id) }
        items += gapItems(toStudy: toStudy, sessions: windowSessions, fluentTurns: teachingTurns,
                          allSessions: allSessions, openers: openers, appState: appState, rng: &rng)
        items += await translateItems(start: start, end: end, now: now, sessions: allSessions,
                                      windowSessions: windowSessions, appState: appState, testId: id)
        let listens = listenItems(fluentTurns: teachingTurns, studyPhrases: studyPhrases, rng: &rng)
        items += listens
        items += speakItems(fluentTurns: teachingTurns, studyPhrases: studyPhrases,
                            excluding: Set(listens.map { CarryoverDetector.normalized($0.answer) }),
                            rng: &rng)
        // What the week's report found: grammar that keeps going wrong and
        // words leaned on too often (user, 2026-10-03).
        let coach = await weekCoach(appState: appState, now: now)
        items += await grammarItems(coach: coach, userTurns: userTurns, appState: appState, now: now, rng: &rng)
        items += upgradeItems(coach: coach, userTurns: userTurns, appState: appState, rng: &rng)
        // What recent weeks got wrong is asked again — the test is a
        // review, and a miss is the most certain material there is.
        let sources = (recentTests + [lastTest].compactMap { $0 })
            .filter { $0.isFinished && !$0.isMonthly }
        var unique: [UUID: WeeklyTest] = [:]
        for t in sources { unique[t.id] = t }
        let recent = unique.values.sorted { $0.createdAt > $1.createdAt }.prefix(retakeWeeks)
        if !recent.isEmpty {
            let fresh = Set(items.map { itemKey($0) })
            items += retakes(from: Array(recent), limit: maxRetake, excluding: fresh,
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

    /// Wrong answers of `tests`, newest test first, one per distinct answer,
    /// as fresh items with their choices reshuffled. A miss that a NEWER test
    /// asked again is that test's to report: answered right there, it is
    /// done and never comes back; wrong again, the newer miss is the one dealt.
    static func retakes(from tests: [WeeklyTest], limit: Int, excluding: Set<String>,
                                language: String, rng: inout WeeklyTestRandom) -> [WeeklyTestItem] {
        var out: [WeeklyTestItem] = []
        var seen = excluding
        for test in tests.sorted(by: { $0.createdAt > $1.createdAt }) {
            let wrong = Set(test.answers.filter { !$0.correct }.map(\.itemId))
            let asked = Set(test.items.map { itemKey($0) })
            defer { seen.formUnion(asked) }
            for stored in test.items where wrong.contains(stored.id) && isValid(stored, language: language) {
                guard out.count < limit else { return out }
                // A missed tile item comes back as the rewrite it is now.
                guard let item = stored.kind == .build ? asRewrite(stored) : stored else { continue }
                let key = itemKey(item)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                // Build tiles are dealt afresh from the two lines, so a stored
                // item picks up today's decoy rule instead of its old tiles.
                let options: [String]
                switch item.kind {
                case .build, .grammar: options = buildTiles(target: item.answer, source: item.prompt, rng: &rng)
                case .listen: options = dictationTiles(for: item.answer, rng: &rng)
                default: options = item.options.shuffled(using: &rng)
                }
                out.append(WeeklyTestItem(id: UUID(), kind: item.kind, prompt: item.prompt, answer: item.answer,
                                          options: options, sessionId: item.sessionId, turnId: item.turnId,
                                          cardId: item.cardId, note: item.note, isRetake: true,
                                          rule: item.rule, focus: item.focus, example: item.example))
            }
        }
        return out
    }

    /// This test's misses dealt again as a paper of their own — played in
    /// place, never saved. nil when nothing was missed.
    static func retryPaper(from test: WeeklyTest) -> WeeklyTest? {
        var rng = WeeklyTestRandom(seed: UUID())
        let items = retakes(from: [test], limit: maxRetry, excluding: [],
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
        case .build, .grammar:
            return ok(item.prompt) && item.options.allSatisfy(ok)
        case .rewrite:
            return ok(item.prompt)
        case .translate:
            return true
        case .upgrade:
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
            // An unanswered listen item minted as pick-one-of-three becomes
            // dictation tiles.
            if item.kind == .listen, item.options.contains(where: { $0.contains(" ") && WordSplitter.count($0) > 1 }) {
                kept.append(WeeklyTestItem(id: item.id, kind: .listen, prompt: "", answer: item.answer,
                                           options: dictationTiles(for: item.answer, rng: &rng),
                                           sessionId: item.sessionId, turnId: item.turnId,
                                           cardId: item.cardId, note: item.note, isRetake: item.isRetake))
                changed = true; continue
            }
            // An unanswered tile item becomes the rewrite that replaced it;
            // one whose card is gone leaves the paper.
            if item.kind == .build {
                changed = true
                if let rewrite = asRewrite(item) {
                    kept.append(WeeklyTestItem(id: item.id, kind: rewrite.kind, prompt: rewrite.prompt,
                                               answer: rewrite.answer, options: [],
                                               sessionId: rewrite.sessionId, turnId: rewrite.turnId,
                                               cardId: rewrite.cardId, note: rewrite.note,
                                               isRetake: item.isRetake, focus: rewrite.focus,
                                               example: rewrite.example))
                }
                continue
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

    /// Lines to say out loud: fluent-self sentences of 4–16 words that carry
    /// a phrase on the "To study" list — saying it is studying it — and
    /// never a line the listen items already used. No such line, no item:
    /// a sentence picked for its length alone is what read as random.
    private static func speakItems(
        fluentTurns: [(session: Session, turn: Turn)],
        studyPhrases: [String],
        excluding: Set<String>,
        rng: inout WeeklyTestRandom
    ) -> [WeeklyTestItem] {
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
                let weight = studyPhrases.filter { lower.contains($0) }.count
                guard weight > 0 else { continue }
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
        sessions: [Session], appState: AppState, rng: inout WeeklyTestRandom
    ) async -> [WeeklyTestItem] {
        let vocab = VocabStore.shared
        // The words come from the week's talk BOOKS and nowhere else (user,
        // 2026-10-03): a book's Words chapter is already the fluent self's
        // words at or above the learner's level, minus every word the learner
        // said in that talk — exactly "what this talk taught you". The old
        // sources (the whole notebook, then words the learner had USED this
        // week) could hand a B2 learner "house": a word they had just proven
        // they know, tested as if it were new. Not yet mastered first; a
        // thin week asks fewer word questions rather than reaching outside.
        var unmastered: [String] = []
        var mastered: [String] = []
        var seen = Set<String>()
        for session in sessions.sorted(by: { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }) {
            let book = TalkCurriculum.build(session: session, proficiency: appState.proficiency,
                                            shadowAttempts: [], drillCards: [])
            for item in book.words {
                let w = item.text
                let k = w.lowercased()
                guard !k.isEmpty, !seen.contains(k), isInTargetScript(w) else { continue }
                seen.insert(k)
                if item.masteredAt == nil { unmastered.append(w) } else { mastered.append(w) }
            }
            await Task.yield()
        }
        let candidates = unmastered.shuffled(using: &rng) + mastered.shuffled(using: &rng)

        // Decoys: the graded list at the learner's level leads, the two
        // neighbouring bands follow — a same-class word one band off beats an
        // any-class word at level, and the class is what `meaningDecoys`
        // sorts by. Languages without a graded list (es, fr, it, pt, zh) fall
        // back to the learner's own known/used words — still their
        // vocabulary, still in the target script.
        let language = appState.targetLanguage
        var graded: [String] = []
        for band in decoyBands(around: appState.proficiency) {
            graded += CoreVocabulary.entries
                .filter { $0.level == band && !seen.contains($0.word.lowercased()) }
                .map(\.word)
                .shuffled(using: &rng)
        }
        if graded.count < choiceCount {
            graded += vocab.records.keys
                .filter { !seen.contains($0.lowercased()) && isInTargetScript($0) }
                .shuffled(using: &rng)
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
            let decoys = meaningDecoys(for: word, own: candidates, graded: graded,
                                       language: language, rng: &rng)
            guard decoys.count == choiceCount - 1 else { continue }
            let options = ([word] + decoys).shuffled(using: &rng)
            out.append(WeeklyTestItem(id: UUID(), kind: .meaning, prompt: sense,
                                      answer: word, options: options))
        }
        return out
    }

    /// The learner's level and its two neighbours, nearest first.
    static func decoyBands(around level: CEFRLevel) -> [CEFRLevel] {
        let all = CEFRLevel.allCases
        guard let i = all.firstIndex(of: level) else { return [level] }
        var bands = [level]
        if i > 0 { bands.append(all[i - 1]) }
        if i + 1 < all.count { bands.append(all[i + 1]) }
        return bands
    }

    /// The wrong choices for a meaning item, `choiceCount - 1` of them.
    ///
    /// Same word class as the answer FIRST (`WordClass`): a verb's gloss must
    /// not be answerable by ruling out three nouns, and a Korean predicate's
    /// 다 would give it away against nouns before the gloss is read. Inside a
    /// class the learner's own pool (`own`, the words they are studying — none
    /// of which is trivially out of place) comes before the graded list, which
    /// arrives ordered by band (`decoyBands`) and already shuffled. Only when
    /// the class runs dry do other-class words fill the row, own first. An
    /// answer whose class is unknown takes everything as same-class, which is
    /// the old rule; a word with several classes (run: noun, verb) matches
    /// either.
    static func meaningDecoys(for word: String, own: [String], graded: [String],
                              language: String, rng: inout WeeklyTestRandom) -> [String] {
        func same(_ w: String) -> Bool { WordClass.sameClass(word, w, language: language) }
        let others = own.filter { $0.lowercased() != word.lowercased() }
        let ownSame = others.filter(same)
        let ownRest = others.filter { !same($0) }
        // The graded list is long; classify only until the row could be
        // filled several times over.
        let gradedSame = Array(graded.lazy.filter(same).prefix(30))
        let ordered = ownSame.shuffled(using: &rng) + gradedSame.shuffled(using: &rng)
            + ownRest.shuffled(using: &rng) + graded
        return Array(dedupe(ordered.filter { $0.lowercased() != word.lowercased() },
                            key: { $0.lowercased() }).prefix(choiceCount - 1))
    }

    // MARK: gap

    /// A "To study" expression with its line blanked out, newest first —
    /// the list the learner keeps on the Expressions page, in the sentence
    /// they met it in: this week's talks first, then any talk, then the
    /// scene that taught it. A phrase with no such line is skipped.
    private static func gapItems(
        toStudy: [ExpressionCatalog.Item],
        sessions: [Session],
        fluentTurns: [(session: Session, turn: Turn)],
        allSessions: [Session],
        openers: Set<UUID>,
        appState: AppState,
        rng: inout WeeklyTestRandom
    ) -> [WeeklyTestItem] {
        struct Candidate { let phrase: String; let sentence: String; let session: Session?; let turn: Turn? }
        let anyFluent = allSessions.flatMap { s in
            s.turns.filter { $0.role == .fluentSelf && !$0.excludedFromScoring && !openers.contains($0.id) }
                .map { (session: s, turn: $0) }
        }
        let sceneExamples: [String: String] = Dictionary(
            appState.scenarios.flatMap { sc in
                (sc.curriculum?.expressions ?? []).compactMap { e in
                    e.example.map { (ExpressionCatalog.normalizedKey(e.text), $0) }
                }
            },
            uniquingKeysWith: { first, _ in first })

        var candidates: [Candidate] = []
        for entry in toStudy {
            guard candidates.count < maxGap * 3 else { break }
            if let hit = firstSentence(containing: entry.text, in: fluentTurns)
                ?? firstSentence(containing: entry.text, in: anyFluent) {
                candidates.append(Candidate(phrase: entry.text, sentence: hit.sentence,
                                            session: hit.session, turn: hit.turn))
            } else if let example = sceneExamples[entry.key],
                      example.range(of: entry.text, options: [.caseInsensitive]) != nil,
                      isInTargetScript(example) {
                candidates.append(Candidate(phrase: entry.text, sentence: example, session: nil, turn: nil))
            }
        }

        // Decoys: every other phrase of the week first — they are the ones
        // that could plausibly fit — then the rest of the study list, and the
        // library only to fill the row.
        var weekPool: [String] = []
        for s in sessions {
            weekPool += (s.summary?.expressionsOffered ?? []) + (s.summary?.expressionsUsed ?? [])
        }
        weekPool = dedupe(weekPool + toStudy.map(\.text), key: ExpressionCatalog.normalizedKey)
        let libraryPool = dedupe(ExpressionCatalog.all(scenarios: appState.scenarios).map(\.text),
                                 key: ExpressionCatalog.normalizedKey)

        var out: [WeeklyTestItem] = []
        // Newest first, as the list shows them — the top of it is what the
        // learner is studying now.
        for c in candidates {
            guard out.count < maxGap else { break }
            let key = ExpressionCatalog.normalizedKey(c.phrase)
            func fits(_ p: String) -> Bool {
                ExpressionCatalog.normalizedKey(p) != key && !c.sentence.lowercased().contains(p.lowercased())
                    && isInTargetScript(p)
            }
            let decoys = dedupe(weekPool.filter(fits).shuffled(using: &rng)
                                + libraryPool.filter(fits).shuffled(using: &rng),
                                key: ExpressionCatalog.normalizedKey)
                .prefix(choiceCount - 1)
            guard decoys.count == choiceCount - 1,
                  let prompt = blank(c.phrase, in: c.sentence) else { continue }
            let options = ([c.phrase] + decoys).shuffled(using: &rng)
            out.append(WeeklyTestItem(id: UUID(), kind: .gap, prompt: prompt, answer: c.phrase,
                                      options: options, sessionId: c.session?.id, turnId: c.turn?.id))
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

    /// The corrections touched this window, due first then newest, each as
    /// the learner's WHOLE sentence to say or type again the right way.
    private static func rewriteItems(
        start: Date, end: Date, now: Date, sessions: [Session]
    ) -> [WeeklyTestItem] {
        let cards = DrillStore.shared.load().filter { card in
            guard card.box < DrillStore.maxBox,
                  !card.sourcePhrase.trimmingCharacters(in: .whitespaces).isEmpty,
                  isInTargetScript(card.targetPhrase), isInTargetScript(card.sourcePhrase) else { return false }
            let touched = [card.createdAt, card.lastReviewedAt].compactMap { $0 }
            return touched.contains(where: { $0 > start && $0 <= end })
        }
        let ordered = cards.sorted {
            let aDue = $0.nextReviewAt <= now, bDue = $1.nextReviewAt <= now
            if aDue != bDue { return aDue }
            return $0.createdAt > $1.createdAt
        }
        let byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [WeeklyTestItem] = []
        var seen = Set<String>()
        for card in ordered {
            guard out.count < maxRewrite else { break }
            guard let item = rewriteItem(from: card, sessions: byId) else { continue }
            guard seen.insert(itemKey(item)).inserted else { continue }
            out.append(item)
        }
        return out
    }

    /// One correction card as a rewrite item. What the learner reads is
    /// what they said around the slip: the sentence it sits in, or — when
    /// that sentence runs past `rewriteClauseFrom` words, which a spoken turn
    /// usually does, since the recognizer joins it with commas — just the
    /// comma-bounded clause holding it. The answer is that same span with the
    /// card's fix applied. Hesitation sounds (`SpeechLibrary.fillers`) are
    /// taken out of both: they are not the mistake, and "consistent uh issue"
    /// is hard to read back. `focus` / `example` carry the fix itself (what
    /// was said → what it should be), which is what the grade and the hint
    /// read. nil when the span is still too short or long to write out, or
    /// the fix changes nothing.
    ///
    /// Until the clause cut (2026-10-08, same day as the item) the whole
    /// sentence had to fit 25 words, and the four real spoken turns in
    /// `correction-cases-en.json` were 29–34 words each — so almost no real
    /// correction ever became an item.
    static func rewriteItem(from card: DrillCard, sessions: [UUID: Session],
                            language: String = LanguageScope.active) -> WeeklyTestItem? {
        let was = card.sourcePhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = card.targetPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        var said = was, answer = now
        if let sid = card.sourceSessionId, let tid = card.sourceTurnId,
           let turn = sessions[sid]?.turns.first(where: { $0.id == tid }) {
            for sentence in TalkCurriculum.sentences(in: turn.transcript) {
                guard let range = sentence.range(of: was, options: [.caseInsensitive, .diacriticInsensitive])
                else { continue }
                let span = WordSplitter.count(sentence) > rewriteClauseFrom
                    ? clauseRange(around: range, in: sentence) : sentence.startIndex..<sentence.endIndex
                var clause = String(sentence[span])
                guard let local = clause.range(of: was, options: [.caseInsensitive, .diacriticInsensitive])
                else { continue }
                said = clause
                clause.replaceSubrange(local, with: now)
                answer = clause
                break
            }
        }
        said = withoutFillers(said, language: language)
        answer = withoutFillers(answer, language: language)
        let n = WordSplitter.count(said)
        guard n >= 3, n <= (WordSplitter.spaced ? 25 : 40),
              CarryoverDetector.normalized(said) != CarryoverDetector.normalized(answer) else { return nil }
        return WeeklyTestItem(id: UUID(), kind: .rewrite, prompt: said, answer: answer, options: [],
                              sessionId: card.sourceSessionId, turnId: card.sourceTurnId,
                              cardId: card.id, note: card.reason, focus: was, example: now)
    }

    /// Past this many words a sentence is cut to the clause holding the slip.
    static var rewriteClauseFrom: Int { WordSplitter.spaced ? 16 : 30 }

    /// The comma/semicolon-bounded stretch of `sentence` holding `range`,
    /// trimmed, with any leading conjunction-less comma left out. The slip's
    /// own span is never cut, even when it crosses a comma.
    static func clauseRange(around range: Range<String.Index>, in sentence: String) -> Range<String.Index> {
        let marks: Set<Character> = [",", ";", "、", "，", "；"]
        var lower = range.lowerBound
        while lower > sentence.startIndex {
            let prev = sentence.index(before: lower)
            if marks.contains(sentence[prev]) { break }
            lower = prev
        }
        var upper = range.upperBound
        while upper < sentence.endIndex, !marks.contains(sentence[upper]) {
            upper = sentence.index(after: upper)
        }
        while lower < upper, sentence[lower].isWhitespace { lower = sentence.index(after: lower) }
        while upper > lower, sentence[sentence.index(before: upper)].isWhitespace {
            upper = sentence.index(before: upper)
        }
        return lower..<upper
    }

    /// `text` with the language's hesitation sounds taken out, and the
    /// commas they leave behind tidied. Spaced languages drop whole words
    /// only; Japanese drops the sound wherever it stands, with its 、.
    static func withoutFillers(_ text: String, language: String) -> String {
        let fillers = Set(SpeechLibrary.fillers(language).map { $0.lowercased() })
            .subtracting(["este"])   // Spanish "this" as often as a filler
        guard !fillers.isEmpty else { return text }
        var out: String
        if WordSplitter.spaced {
            let kept = text.split(separator: " ", omittingEmptySubsequences: true).filter { word in
                let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                return !fillers.contains(bare)
            }
            out = kept.joined(separator: " ")
        } else {
            out = text
            for f in fillers.sorted(by: { $0.count > $1.count }) {
                out = out.replacingOccurrences(of: f + "、", with: "")
                out = out.replacingOccurrences(of: f, with: "")
            }
        }
        // ", ," and a leading comma are what a removed "um," leaves behind.
        while out.contains(", ,") { out = out.replacingOccurrences(of: ", ,", with: ",") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: ",、 ").union(.whitespaces))
    }

    // MARK: translate

    /// One mistake a translate item can be built on: what was said, what it
    /// should be, why, and the card it came from (for write-back).
    struct Slip { let was: String; let now: String; let why: String; let cardId: UUID? }

    /// The mistakes to build on: this window's correction cards, due first
    /// then newest, then the profile's recurring mistakes — deduped.
    static func slips(start: Date, end: Date, now: Date, profile: LearnerProfile,
                      sessions: [Session] = []) -> [Slip] {
        let cards = DrillStore.shared.load().filter { card in
            guard card.box < DrillStore.maxBox,
                  !card.sourcePhrase.trimmingCharacters(in: .whitespaces).isEmpty,
                  isInTargetScript(card.targetPhrase), isInTargetScript(card.sourcePhrase) else { return false }
            let touched = [card.createdAt, card.lastReviewedAt].compactMap { $0 }
            return touched.contains(where: { $0 > start && $0 <= end })
        }.sorted {
            let aDue = $0.nextReviewAt <= now, bDue = $1.nextReviewAt <= now
            if aDue != bDue { return aDue }
            return $0.createdAt > $1.createdAt
        }
        var out: [Slip] = []
        var seen = Set<String>()
        func add(_ s: Slip) {
            guard seen.insert(CarryoverDetector.normalized(s.was)).inserted else { return }
            out.append(s)
        }
        for c in cards { add(Slip(was: c.sourcePhrase, now: c.targetPhrase, why: c.reason, cardId: c.id)) }
        let fresh = now.addingTimeInterval(-Double(GrammarFocus.freshDays) * 86_400)
        // A profile pattern only when the learner really said it in a talk
        // (`GrammarFocus.evidence`) — its frequency was inflated for weeks.
        for p in profile.recurringMistakes where p.lastSeenAt >= fresh
            && isInTargetScript(p.mistake) && isInTargetScript(p.correction)
            && GrammarFocus.evidence(p, sessions: sessions, now: now) >= 1 {
            add(Slip(was: p.mistake, now: p.correction, why: p.context, cardId: nil))
        }
        return Array(out.prefix(10))
    }

    private struct TranslatePayload: Decodable {
        struct Item: Decodable {
            let source: Int
            let point: String
            let native: String
            let answer: String
            let orders: [String]?
            let decoys: [String]?
            let tip: String?
        }
        let items: [Item]
    }

    /// New sentences that need the grammar the learner got wrong, laid from
    /// word tiles. One model call writes each sentence, the other word orders
    /// that are just as right, and trap words built from the learner's own
    /// mistake; code grades the laid tiles against that closed set. A free
    /// answer (typed or said) was tried first and could not be graded
    /// exactly: a slip elsewhere passed and a synonym failed (founder,
    /// 2026-10-08: "that limit can't be there"). Nothing when the target IS
    /// the native language (there is nothing to translate from) or the call
    /// fails.
    private static func translateItems(
        start: Date, end: Date, now: Date, sessions: [Session], windowSessions: [Session],
        appState: AppState, testId: UUID
    ) async -> [WeeklyTestItem] {
        let target = appState.targetLanguage, native = appState.nativeLanguage
        guard !LanguageCatalog.sameLanguage(target, native) else { return [] }
        let list = slips(start: start, end: end, now: now, profile: appState.learnerProfile,
                         sessions: sessions)
        guard !list.isEmpty else { return [] }
        let topics = windowSessions.compactMap { $0.topic }
            .filter { !$0.isEmpty }.prefix(6)
        let targetName = LanguageCatalog.englishName(target)
        let nativeName = LanguageCatalog.englishName(native)
        let system = """
            You write a short translation quiz for a \(targetName) learner whose own \
            language is \(nativeName), level \(appState.proficiency.rawValue.uppercased()). \
            They answer by laying word tiles in order. You get mistakes they really \
            made. Pick up to \(maxTranslate) of them, each a DIFFERENT grammar point \
            (skip pure word choice or a slip with no rule behind it), and for each \
            write ONE new everyday sentence that cannot be said right without that \
            grammar point.

            Return {"items":[{"source":n,"point":"...","native":"...","answer":"...",\
            "orders":["..."],"decoys":["..."],"tip":"..."}]}
            - source: the number of the mistake it is built on.
            - native: the sentence in \(nativeName), casual and spoken, the way they'd \
              say it to a friend, 6–12 words, about ordinary life (these were their \
              topics: \(topics.joined(separator: "; "))). NOT their original sentence.
            - answer: the most natural \(targetName) way to say it, at their level, \
              5–12 words. Its words are the tiles, so there must be ONE wording: no \
              optional words, nothing a learner could naturally say differently \
              with other words.
            - orders: every OTHER order of exactly the same words that is just as \
              correct. Go through each time, place and duration phrase ("for two \
              years", "yesterday", "at midnight") and each adverb, and list the \
              sentence with it at the front too wherever that is natural — a \
              learner who lays a right order and is marked wrong stops trusting \
              the test. [] only if the order is truly fixed.
            - decoys: 2–3 single words built from their mistake (e.g. "since", "am" \
              for "I am working here since 2020") that make the sentence WRONG \
              wherever they go, and are not in answer.
            - point: the grammar point in \(nativeName), 2–5 words. tip: one line in \
              \(nativeName) on when it applies, at most 14 words.
            JSON only.
            """
        let user = list.enumerated().map { i, s in
            "\(i + 1). said \"\(s.was)\" → should be \"\(s.now)\"\(s.why.isEmpty ? "" : " (\(s.why))")"
        }.joined(separator: "\n")
        let task = Task { @MainActor () -> TranslatePayload? in
            try? await GeminiClient.shared.sendJSON(
                system: system, messages: [.init(role: .user, content: user)],
                maxTokens: 3000, purpose: "weekly-test",
                idempotencyKey: "weekly-test-translate:\(testId.uuidString)",
                requestTimeout: translateWait)
        }
        guard let payload = await task.value else { return [] }
        var rng = WeeklyTestRandom(seed: testId)
        var out: [WeeklyTestItem] = []
        var points = Set<String>()
        for it in payload.items {
            guard out.count < maxTranslate, list.indices.contains(it.source - 1) else { continue }
            let slip = list[it.source - 1]
            guard let item = translateItem(it.native, answer: it.answer, orders: it.orders ?? [],
                                           decoys: it.decoys ?? [], point: it.point, tip: it.tip,
                                           slip: slip, target: target, rng: &rng),
                  points.insert(it.point.lowercased()).inserted else { continue }
            out.append(item)
        }
        return out
    }

    /// A model-written translate item, or nil. Kept only when the answer is a
    /// tileable sentence in the target script; `orders` keep only the ones
    /// made of exactly the answer's words; a decoy must be one target-script
    /// word the answer doesn't use. Tiles = the answer's words + decoys.
    static func translateItem(_ native: String, answer: String, orders: [String], decoys: [String],
                              point: String, tip: String?, slip: Slip, target: String,
                              rng: inout WeeklyTestRandom) -> WeeklyTestItem? {
        let words = WordSplitter.words(answer)
        let keys = words.map(tileKey)
        guard words.count >= 3, words.count <= (WordSplitter.spaced ? 14 : 20),
              isInTargetScript(answer, language: target), !native.isEmpty,
              CarryoverDetector.normalized(native) != CarryoverDetector.normalized(answer) else { return nil }
        let sameWords = keys.sorted()
        let kept = dedupe(orders.filter {
            let k = WordSplitter.words($0).map(tileKey)
            return k.sorted() == sameWords && k != keys
        }, key: { WordSplitter.words($0).map(tileKey).joined(separator: " ") })
        let answerKeys = Set(keys)
        let traps = dedupe(decoys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            !$0.isEmpty && WordSplitter.count($0) == 1 && !answerKeys.contains(tileKey($0))
                && isInTargetScript($0, language: target)
        }, key: tileKey).prefix(3)
        var tiles = (words + traps).shuffled(using: &rng)
        if tiles.count > 2, tiles.map(tileKey) == keys { tiles.swapAt(0, tiles.count - 1) }
        return WeeklyTestItem(id: UUID(), kind: .translate, prompt: native, answer: answer, options: tiles,
                              cardId: slip.cardId, note: tip, rule: point,
                              focus: slip.was, example: slip.now, orders: kept)
    }

    /// A stored tile item (`build`) as the rewrite that replaced it, read
    /// from its card. nil when the card is gone.
    static func asRewrite(_ item: WeeklyTestItem) -> WeeklyTestItem? {
        guard let id = item.cardId,
              let card = DrillStore.shared.load().first(where: { $0.id == id }) else { return nil }
        let sessions = Dictionary(SessionStore.shared.load().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        guard var out = rewriteItem(from: card, sessions: sessions) else { return nil }
        out.isRetake = item.isRetake
        return out
    }

    /// A line's own words, shuffled and never in order — the listen item's
    /// tiles. No decoys: the ear supplies the difficulty.
    static func dictationTiles(for text: String, rng: inout WeeklyTestRandom) -> [String] {
        let words = WordSplitter.words(text)
        var tiles = words.shuffled(using: &rng)
        if tiles.count > 2, tiles.map(tileKey) == words.map(tileKey) { tiles.swapAt(0, tiles.count - 1) }
        return tiles
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

    // MARK: report (grammar · upgrade)

    /// The closed week's report coach. Written here when the deck hasn't
    /// been opened yet — saved into the report, so the deck shows the same
    /// read and it is paid for once — but the paper waits at most
    /// `coachWait` for it.
    private static func weekCoach(appState: AppState, now: Date) async -> WeekRecap.Coach? {
        let recap = WeekRecapStore.shared.lastWeek(now: now)
        if let coach = recap.coach { return coach }
        guard recap.hasActivity else { return nil }
        final class Box { var done = false; var coach: WeekRecap.Coach? }
        let box = Box()
        let target = appState.targetLanguage, level = appState.proficiency
        Task { @MainActor in
            defer { box.done = true }
            guard let written = try? await WeekRecapCoach.write(for: recap, targetLanguage: target,
                                                                level: level) else { return }
            // The deck may have written it meanwhile; keep the first.
            var latest = WeekRecapStore.shared.recap(endingAt: recap.end) ?? recap
            if latest.coach == nil {
                latest.coach = written
                WeekRecapStore.shared.save(latest)
            }
            box.coach = latest.coach
        }
        let deadline = Date().addingTimeInterval(coachWait)
        while !box.done, Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return box.coach
    }

    /// The first sentence of the window's learner lines that QUOTES `span`
    /// (the report's quotes were checked against every language's lines; this
    /// keeps them to the active one), with the span's range in it.
    private static func learnerSentence(
        quoting span: String, in userTurns: [(session: Session, turn: Turn)], maxWords: Int
    ) -> (sentence: String, range: Range<String.Index>, session: Session, turn: Turn)? {
        let needle = span.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        for entry in userTurns {
            for sentence in TalkCurriculum.sentences(in: entry.turn.transcript) {
                guard let range = sentence.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                let n = WordSplitter.count(sentence)
                guard n >= 3, n <= maxWords, isInTargetScript(sentence) else { continue }
                return (sentence, range, entry.session, entry.turn)
            }
        }
        return nil
    }

    /// One item per recurring grammar point: the rule, one of the learner's
    /// own lines with the mistake in it, rebuilt right from tiles (the wrong
    /// words ride along as decoys — `buildTiles`). The report's points come
    /// first; when it has none (or none found this week's lines) the
    /// profile's recurring mistakes stand in, named by `GrammarFocus`.
    private static func grammarItems(
        coach: WeekRecap.Coach?, userTurns: [(session: Session, turn: Turn)],
        appState: AppState, now: Date, rng: inout WeeklyTestRandom
    ) async -> [WeeklyTestItem] {
        let maxWords = WordSplitter.spaced ? 12 : 18
        var out: [WeeklyTestItem] = []
        var seen = Set<String>()
        func make(rule: String, tip: String, was: String, now fixed: String) -> WeeklyTestItem? {
            guard let hit = learnerSentence(quoting: was, in: userTurns, maxWords: maxWords) else { return nil }
            let answer = hit.sentence.replacingCharacters(in: hit.range, with: fixed)
            guard isInTargetScript(answer),
                  CarryoverDetector.normalized(answer) != CarryoverDetector.normalized(hit.sentence),
                  seen.insert(CarryoverDetector.normalized(answer)).inserted else { return nil }
            return WeeklyTestItem(id: UUID(), kind: .grammar, prompt: hit.sentence, answer: answer,
                                  options: buildTiles(target: answer, source: hit.sentence, rng: &rng),
                                  sessionId: hit.session.id, turnId: hit.turn.id,
                                  note: tip.isEmpty ? nil : tip, rule: rule, focus: was)
        }
        for pattern in coach?.grammar ?? [] {
            guard out.count < maxGrammar else { break }
            for example in pattern.examples.shuffled(using: &rng) {
                if let item = make(rule: pattern.rule, tip: pattern.tip, was: example.was, now: example.now) {
                    out.append(item); break
                }
            }
        }
        guard out.count < maxGrammar else { return out }
        let fresh = now.addingTimeInterval(-Double(GrammarFocus.freshDays) * 86_400)
        let patterns = appState.learnerProfile.recurringMistakes
            .filter { $0.frequency >= GrammarFocus.minFrequency && $0.lastSeenAt >= fresh }
        for pattern in patterns {
            guard out.count < maxGrammar else { break }
            guard learnerSentence(quoting: pattern.mistake, in: userTurns, maxWords: maxWords) != nil,
                  let named = await GrammarFocus.describe(pattern, target: appState.targetLanguage,
                                                          native: appState.nativeLanguage),
                  let item = make(rule: named.label, tip: named.tip, was: pattern.mistake, now: pattern.correction)
            else { continue }
            out.append(item)
        }
        return out
    }

    /// One item per leaned-on word: the learner's line with it marked, and
    /// the report's better word among three that don't belong — the week's
    /// other better words first, then graded words of the same class one
    /// band above the learner (the band the report reaches for).
    private static func upgradeItems(
        coach: WeekRecap.Coach?, userTurns: [(session: Session, turn: Turn)],
        appState: AppState, rng: inout WeeklyTestRandom
    ) -> [WeeklyTestItem] {
        guard let upgrades = coach?.upgrades, !upgrades.isEmpty else { return [] }
        let language = appState.targetLanguage
        let all = CEFRLevel.allCases
        let level = appState.proficiency
        let oneUp = all.firstIndex(of: level).map { all[min($0 + 1, all.count - 1)] } ?? level
        var graded: [String] = []
        for band in decoyBands(around: oneUp) {
            graded += CoreVocabulary.entries.filter { $0.level == band }.map(\.word).shuffled(using: &rng)
        }
        var out: [WeeklyTestItem] = []
        for u in upgrades.shuffled(using: &rng) {
            guard out.count < maxUpgrade else { break }
            guard isInTargetScript(u.better), isInTargetScript(u.instead),
                  let hit = learnerSentence(quoting: u.instead, in: userTurns,
                                            maxWords: WordSplitter.spaced ? 25 : 35) else { continue }
            let taken = Set(([u.better, u.instead] + WordSplitter.words(hit.sentence)).map { $0.lowercased() })
            func fits(_ w: String) -> Bool { !taken.contains(w.lowercased()) && isInTargetScript(w) }
            let week = upgrades.map(\.better).filter(fits).shuffled(using: &rng)
            let sameClass = graded.lazy.filter(fits)
                .filter { WordClass.sameClass(u.better, $0, language: language) }.prefix(30)
            let decoys = dedupe(week + Array(sameClass).shuffled(using: &rng) + graded.filter(fits),
                                key: { $0.lowercased() }).prefix(choiceCount - 1)
            guard decoys.count == choiceCount - 1 else { continue }
            out.append(WeeklyTestItem(id: UUID(), kind: .upgrade, prompt: hit.sentence, answer: u.better,
                                      options: ([u.better] + decoys).shuffled(using: &rng),
                                      sessionId: hit.session.id, turnId: hit.turn.id,
                                      note: u.note.isEmpty ? nil : u.note, focus: u.instead,
                                      example: u.rewritten.isEmpty ? nil : u.rewritten))
        }
        return out
    }

    // MARK: listen

    private static func listenItems(
        fluentTurns: [(session: Session, turn: Turn)],
        studyPhrases: [String],
        rng: inout WeeklyTestRandom
    ) -> [WeeklyTestItem] {
        // Picking a line out of three was a length test, not a listening
        // test (user, 2026-09-24). The line is HEARD and rebuilt from its own
        // word tiles with the text hidden — dictation, so the difficulty is
        // the sentence's own. Whole turns only: the saved audio is the turn.
        // Only a line carrying a "To study" phrase: hearing it is the point.
        func fits(_ text: String) -> Bool {
            let n = WordSplitter.count(text)
            let lower = text.lowercased()
            return n >= 4 && n <= (WordSplitter.spaced ? 14 : 18) && isInTargetScript(text)
                && studyPhrases.contains { lower.contains($0) }
        }
        let withAudio = fluentTurns.filter {
            fits($0.turn.transcript) && TurnAudioStore.shared.url(for: $0.turn.id) != nil
        }
        var out: [WeeklyTestItem] = []
        var seen = Set<String>()
        for entry in withAudio.shuffled(using: &rng) {
            guard out.count < maxListen else { break }
            let text = entry.turn.transcript
            let key = CarryoverDetector.normalized(text)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(WeeklyTestItem(id: UUID(), kind: .listen, prompt: "", answer: text,
                                      options: dictationTiles(for: text, rng: &rng),
                                      sessionId: entry.session.id, turnId: entry.turn.id))
        }
        return out
    }

    // MARK: - Grading

    /// A choice item: the picked option against the answer.
    static func isCorrect(_ item: WeeklyTestItem, chosen: String) -> Bool {
        CarryoverDetector.normalized(chosen) == CarryoverDetector.normalized(item.answer)
    }

    /// A build item: the tiles in the order the learner laid them.
    /// Laid tiles that are exactly the answer's words — no trap, none left
    /// out — in an order the item doesn't list. The one case code can't
    /// settle: the grammar point is already proved (every word of the right
    /// form, no wrong one), and only whether the ORDER is natural is open.
    static func isReorder(_ item: WeeklyTestItem, tiles: [String]) -> Bool {
        let laid = tiles.map(tileKey)
        return laid.sorted() == WordSplitter.words(item.answer).map(tileKey).sorted()
            && !isCorrect(item, tiles: tiles)
    }

    private struct OrderVerdict: Decodable { let natural: Bool }

    /// Is `laid` a natural order of the answer's words, meaning the same?
    /// The model generating the item lists the orders it can think of and
    /// measurably misses one in about twelve ("For two years I have worked
    /// here" unlisted beside "I have worked here for two years", probe
    /// 2026-10-08). Asked only for `isReorder` answers, so it judges word
    /// order and nothing else; a failed call is the old verdict, wrong.
    static func orderIsNatural(_ item: WeeklyTestItem, laid: String, language: String) async -> Bool {
        let name = LanguageCatalog.englishName(language)
        // Told the point and the learner's slip, or it accepts the slip
        // itself as "understandable" ("I explained to the landlord the
        // situation", 2 of 6 on the default model without them; 0 of 3 on
        // flash-lite with them, which then misses only a debatable order —
        // 33/36 over 12 cases, probe 2026-10-08).
        let system = """
            A learner laid word tiles to say a \(name) sentence. They used exactly \
            the words of the model answer, in a different order. Judge only the \
            order: is it grammatical and natural, meaning the same — something a \
            careful teacher would accept? Unusual but correct emphasis (a time \
            phrase moved to the front) is fine. The quiz tests one grammar point, \
            given below with the learner's earlier mistake; an order that repeats \
            that mistake is NOT acceptable, even if a listener would understand it.
            Return {"natural": true} or {"natural": false}.
            """
        var user = ""
        if let rule = item.rule { user += "Grammar point: \(rule)\n" }
        if let was = item.focus, let now = item.example { user += "Their earlier mistake: \(was) → \(now)\n" }
        user += "Model answer: \(item.answer)\nTheir order: \(laid)"
        let v: OrderVerdict? = try? await GeminiClient.shared.sendJSON(
            system: system, messages: [.init(role: .user, content: user)],
            model: .flashLite31, maxTokens: 400, purpose: "weekly-test",
            idempotencyKey: "weekly-test-order:\(item.id.uuidString):\(CarryoverDetector.normalized(laid))",
            requestTimeout: 10, fastThinking: true)
        return v?.natural ?? false
    }

    /// A tile item: the tiles in the order the learner laid them — the
    /// answer's order, or (translate) another order the item lists as just
    /// as right.
    static func isCorrect(_ item: WeeklyTestItem, tiles: [String]) -> Bool {
        let laid = tiles.map(tileKey)
        return ([item.answer] + (item.orders ?? [])).contains { WordSplitter.words($0).map(tileKey) == laid }
    }

    /// A rewrite item: what the learner said or typed. Right when it is the
    /// answer sentence, or when it carries the fix (every word the fix added,
    /// none it removed — `CarryoverDetector.showsTheFix`, the rule that
    /// credits a correction in a talk) inside most of the sentence, so a
    /// reply of the fixed word alone is not a rewrite. Nothing else counts
    /// against it: how the rest is worded is the learner's.
    ///
    /// Everything is compared through `ShadowEngine.expandForDiff` first:
    /// dictation writes "I've" as "I have" and digits for numbers, and an
    /// answer said right must not fail on how the recognizer spelled it.
    /// Spaces are compared away too (Korean spacing is the recognizer's).
    static func isCorrect(_ item: WeeklyTestItem, rewritten: String,
                          language: String = LanguageScope.active) -> Bool {
        // Hesitation is never the mistake, in the slip or in the answer.
        func expand(_ t: String) -> String {
            ShadowEngine.expandForDiff(withoutFillers(t, language: language), language: language)
        }
        func squeezed(_ t: String) -> String {
            CarryoverDetector.normalized(expand(t)).replacingOccurrences(of: " ", with: "")
        }
        let given = CarryoverDetector.normalized(expand(rewritten))
        guard !given.isEmpty else { return false }
        if given.contains(CarryoverDetector.normalized(expand(item.answer)))
            || squeezed(rewritten).contains(squeezed(item.answer)) { return true }
        guard let rawWas = item.focus, let rawNow = item.example else { return false }
        let was = expand(rawWas), now = expand(rawNow)
        let rewritten = expand(rewritten)
        // A pure reorder adds and drops nothing; only the fix itself shows it.
        let fixKey = CarryoverDetector.normalized(now)
        guard CarryoverDetector.fixChangesWords(from: was, to: now) else {
            return !fixKey.isEmpty && given.contains(fixKey)
        }
        return CarryoverDetector.showsTheFix(from: was, to: now, inText: rewritten)
            && CarryoverDetector.sharedWordRatio(of: expand(item.answer), in: rewritten) >= 0.6
    }

    /// The words the fix put in — the hint a rewrite item offers.
    static func hintWords(_ item: WeeklyTestItem) -> String? {
        guard let was = item.focus, let now = item.example else { return nil }
        let added = CarryoverDetector.addedWords(from: was, to: now)
        return added.isEmpty ? now : added.joined(separator: " · ")
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

    /// The tiles the answer doesn't use — a build item's decoys, i.e. the
    /// learner's own words the correction replaced. Read off the item (tiles
    /// minus the answer's words, as a multiset) so items already on disk
    /// need nothing new. Empty for dictation, which has no decoys.
    static func decoyTiles(of item: WeeklyTestItem) -> [String] {
        var needed: [String: Int] = [:]
        for word in WordSplitter.words(item.answer) { needed[tileKey(word), default: 0] += 1 }
        return item.options.filter { tile in
            let key = tileKey(tile)
            if let n = needed[key], n > 0 { needed[key] = n - 1; return false }
            return true
        }
    }

    // MARK: - Writing back

    /// What a finished test does to the review loop. Runs once per test
    /// (the store stamps `appliedAt`); an answer is a claim, so nothing here
    /// retires anything — see CLAUDE.md "USED outranks KNOWN".
    ///
    ///   meaning  right → the word waits 3 days · wrong → back in the notebook, due now
    ///   gap      right → the phrase waits 3 days · wrong → bookmarked, due now
    ///   rewrite  right → one Leitner rung up · wrong → one rung down (build alike)
    ///   listen   nothing to write; recognition is not production
    ///   grammar  nothing to write; its corrections already carry cards
    ///   upgrade  wrong → the better word in the notebook, due now
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
            case .build, .rewrite, .translate:
                guard let id = item.cardId, let card = cards[id] else { continue }
                if answer.correct { DrillStore.shared.markCorrect(card, at: now) }
                else { DrillStore.shared.markIncorrect(card, at: now) }
                PracticeLog.shared.record(.drill)
            case .upgrade:
                // Missed: the better word goes in the notebook, due now. Right
                // is a recognition, not a use — nothing to claim.
                guard !answer.correct else { continue }
                let better = item.answer
                if WordSplitter.count(better) > 1 {
                    if !vocab.isStudyingExpression(better) { vocab.setStudyingExpression(better, true) }
                    ReviewQueue.retire(.expression, better)
                } else {
                    vocab.addStudying(better)
                    ReviewQueue.retire(.word, better)
                }
            case .listen, .speak, .grammar:
                // Recognition writes nothing; a spoken line is already on
                // file as a shadow attempt, saved by the screen that heard it.
                // A grammar point has no card of its own — the corrections it
                // was found in already have theirs.
                break
            }
        }
    }

    // MARK: - Helpers

    /// `TextScript.isInTargetScript`, defaulting to the active language.
    static func isInTargetScript(_ text: String, language: String = LanguageScope.active) -> Bool {
        TextScript.isInTargetScript(text, language: language)
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
