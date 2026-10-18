import CryptoKit
import Foundation

/// The quick quiz's WRITTEN questions: grammar, and the level's expressions
/// (2026-10-18, founder: "words, expressions and grammar"; then "someone who
/// has made no scene and had no call still gets a quiz at their level — drop
/// the rule that it must be the learner's own").
///
/// Each is a NEW everyday line with a blank and four choices, exactly one of
/// which fits. They are written by one model call per batch and kept on disk
/// (`quiz_stock.json`, per language), so most quizzes ask nothing of the
/// model: a batch is written only when a kind has fewer than `refillBelow`
/// unasked questions, and a quiz waits for it at most `writeWait` — past
/// that it goes without and the batch lands for the next.
///
/// - grammar: the learner's own recurring grammar points first — the ones
///   the call's grammar focus trusts (`GrammarFocus.candidates`: said in two
///   talks or more, judged a grammar point by `describe`) — and, when there
///   are fewer than `minPoints` of those, the grammar of their level.
/// - expression: common expressions of their level (collocations, phrasal
///   verbs, set phrases). The learner's OWN study list is asked by
///   `QuickQuizEngine` from the lines they heard; these fill in around it.
///
/// Never the learner's transcript: every line is written fresh, so nothing a
/// recognizer misheard can become an answer.
///
/// The model writes; code decides what is kept (one blank, four distinct
/// choices in the target script, the answer among them) and grades. Then a
/// SECOND call, not told the answer, marks every choice that makes the line
/// correct, and a question is kept only when that is the answer alone
/// (`check`). Measured on the first prompt (ko/en/de, 24 questions): 3 had
/// two right answers ("밤을 새워서 / 새우느라고 피곤해요", "ate a / the
/// sandwich"); the check dropped all three, plus a few stricter calls.
@MainActor
enum QuickQuizStock {
    enum Kind: String, Codable, CaseIterable { case grammar, expression }

    struct Stored: Codable, Identifiable {
        var id = UUID()
        let kind: Kind
        /// grammar: the point's name · expression: what it means (native).
        let point: String
        let tip: String
        let sentence: String
        let answer: String
        let wrong: [String]
        var asked: Int = 0
        let createdAt: Date
    }

    /// Below this many unasked questions of either kind, a batch is written.
    static let refillBelow = 5
    /// Questions asked of the model per kind; about a third fail the check.
    static let batchPerKind = 8
    /// The learner's own points the batch is built on, at most.
    static let maxPoints = 4
    /// With fewer of the learner's own points, the level's grammar fills in.
    static let minPoints = 2
    /// How long a quiz waits for a batch it needs now.
    static let writeWait: TimeInterval = 12
    /// A question is retired once asked this often; the stock is capped.
    static let maxAsked = 2
    static let maxStored = 60

    private static var fileURL: URL {
        LanguageScope.activeDirectory.appendingPathComponent("quiz_stock.json")
    }

    static func load() -> [Stored] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Stored].self, from: data) else { return [] }
        return list
    }

    private static func save(_ list: [Stored]) {
        guard let data = try? JSONEncoder().encode(Array(list.suffix(maxStored))) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The one batch being written, shared by the prewarm and a quiz.
    private static var writing: Task<[Stored]?, Never>?
    private static var lastFailure = Date.distantPast

    private static func startWriting(appState: AppState) -> Task<[Stored]?, Never> {
        if let writing { return writing }
        let task = Task { @MainActor () -> [Stored]? in
            let result = await writeBatch(appState: appState)
            if result == nil { lastFailure = Date() }
            writing = nil
            return result
        }
        writing = task
        return task
    }

    private static var needsBatch: Bool {
        let unasked = load().filter { $0.asked == 0 }
        return Kind.allCases.contains { kind in unasked.filter { $0.kind == kind }.count < refillBelow }
    }

    /// Fill the stock before anyone opens a quiz, so the first one is full
    /// (the Talk tab calls this when the quiz button appears).
    static func prewarm(appState: AppState) {
        // A batch that just failed (offline, signed out) is not retried on
        // every return to the tab.
        guard needsBatch, Date().timeIntervalSince(lastFailure) > 600 else { return }
        _ = startWriting(appState: appState)
    }

    /// What can be asked now, least-asked first — grammar one per point.
    /// Writes a batch first when the stock is low, waiting only when there
    /// is too little to ask without it. Nothing is marked asked here: the
    /// quiz marks what it actually used (`markAsked`).
    static func available(appState: AppState, grammar: Int, expressions: Int) async
        -> (grammar: [QuickQuizItem], expressions: [QuickQuizItem]) {
        var stock = load().filter { $0.asked < maxAsked }
        if needsBatch {
            let writing = startWriting(appState: appState)
            let short = stock.filter { $0.kind == .grammar }.count < grammar
                || stock.filter { $0.kind == .expression }.count < expressions
            if short {
                let waited = await withTaskGroup(of: [Stored]?.self) { group in
                    group.addTask { await writing.value }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: UInt64(writeWait * 1_000_000_000))
                        return nil
                    }
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    return first
                }
                if waited != nil { stock = load().filter { $0.asked < maxAsked } }
            }
        }
        let ordered = stock.sorted { ($0.asked, $0.createdAt) < ($1.asked, $1.createdAt) }

        var points = Set<String>()
        let g = ordered.filter { $0.kind == .grammar }
            .filter { points.insert($0.point.lowercased()).inserted }
            .prefix(grammar)
        var phrases = Set<String>()
        let e = ordered.filter { $0.kind == .expression }
            .filter { phrases.insert(CarryoverDetector.normalized($0.answer)).inserted }
            .prefix(expressions)
        return (g.map(item), e.map(item))
    }

    private static func item(_ q: Stored) -> QuickQuizItem {
        switch q.kind {
        case .grammar:
            return QuickQuizItem(kind: .grammar, prompt: q.sentence, answer: q.answer,
                                 options: ([q.answer] + q.wrong).shuffled(),
                                 heading: q.point.isEmpty ? nil : q.point,
                                 note: q.tip.isEmpty ? nil : q.tip, stockId: q.id)
        case .expression:
            // The meaning is the note: it says what was just picked.
            let meaning = [q.point, q.tip].filter { !$0.isEmpty }.joined(separator: " · ")
            return QuickQuizItem(kind: .expression, prompt: q.sentence, answer: q.answer,
                                 options: ([q.answer] + q.wrong).shuffled(),
                                 note: meaning.isEmpty ? nil : "\(q.answer) — \(meaning)", stockId: q.id)
        }
    }

    /// Count the questions a quiz actually asked.
    static func markAsked(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var all = load()
        for i in all.indices where ids.contains(all[i].id) { all[i].asked += 1 }
        save(all)
    }

    // MARK: - Writing

    /// The batch as written. Read one question at a time: measured on the
    /// first device runs (2026-10-18), half the batches failed whole because
    /// ONE item came back as a string or under another key ("question" for
    /// "sentence"). A question that can't be read is skipped, never the batch.
    private struct Payload: Decodable {
        struct Item {
            let kind: Kind
            let point: String
            let tip: String?
            let sentence: String
            let answer: String
            let wrong: [String]
        }
        let items: [Item]

        private enum Keys: String, CodingKey { case items, questions }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let raw = (try? c.decode([Loose].self, forKey: .items))
                ?? (try? c.decode([Loose].self, forKey: .questions)) ?? []
            items = raw.compactMap(\.item)
        }
    }

    /// One element of `items`, whatever shape it arrived in.
    private struct Loose: Decodable {
        let item: Payload.Item?


        private struct AnyKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            // An object written out as a JSON string.
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                let data = Data(text.utf8)
                item = (try? JSONDecoder().decode(Loose.self, from: data))?.item
                return
            }
            guard let c = try? decoder.container(keyedBy: AnyKey.self) else { item = nil; return }
            func string(_ names: String...) -> String? {
                for n in names {
                    if let v = try? c.decode(String.self, forKey: AnyKey(stringValue: n)),
                       !v.trimmingCharacters(in: .whitespaces).isEmpty { return v }
                }
                return nil
            }
            func strings(_ names: String...) -> [String]? {
                for n in names {
                    if let v = try? c.decode([String].self, forKey: AnyKey(stringValue: n)) { return v }
                }
                return nil
            }
            guard let sentence = string("sentence", "question", "text", "prompt"),
                  let answer = string("answer", "correct", "correct_answer") else { item = nil; return }
            var wrong = strings("wrong", "wrong_choices", "distractors", "incorrect") ?? []
            if wrong.isEmpty, let all = strings("choices", "options") {
                wrong = all.filter { $0 != answer }
            }
            let kind: Kind = (string("type", "kind") ?? "").lowercased().hasPrefix("expr") ? .expression : .grammar
            item = Payload.Item(kind: kind,
                                point: string("point", "meaning", "grammar_point", "grammar") ?? "",
                                tip: string("tip", "explanation", "why"),
                                sentence: sentence, answer: answer, wrong: wrong)
        }
    }

    /// Writes one batch into the stock. Returns what was added, nil on failure.
    @discardableResult
    static func writeBatch(appState: AppState) async -> [Stored]? {
        let target = appState.targetLanguage
        let native = appState.nativeLanguage
        let sessions = SessionStore.shared.load()
        var own: [(label: String, was: String, now: String)] = []
        for c in GrammarFocus.candidates(from: appState.learnerProfile, sessions: sessions) {
            guard own.count < maxPoints else { break }
            guard let named = await GrammarFocus.describe(c.pattern, target: target, native: native) else { continue }
            own.append((named.label, c.pattern.mistake, c.pattern.correction))
        }

        let targetName = LanguageCatalog.englishName(target)
        let nativeName = LanguageCatalog.englishName(native)
        let level = appState.proficiency.rawValue.uppercased()
        let spokenTopics = sessions.compactMap(\.topic).filter { !$0.isEmpty }.suffix(6)
        let system = """
            You write quick quiz questions for a \(targetName) learner whose own \
            language is \(nativeName), level \(level). Each question is ONE everyday \
            \(targetName) sentence with exactly one blank "\(WeeklyTestEngine.blankMark)" \
            and four choices for it. Exactly ONE choice is correct. Two types:

            Return {"items":[{"type":"grammar|expression","point":"...","tip":"...","sentence":"...","answer":"...","wrong":["...","...","..."]}]}
            - sentence: spoken and ordinary, \(WordSplitter.spaced ? "5–12 words" : "8–25 characters"), \
              at their level, about everyday life\(spokenTopics.isEmpty ? "" : " (their recent topics: \(spokenTopics.joined(separator: "; ")))").
            - The sentence must leave ONLY the answer possible. Never write a blank \
              two choices could both fill, not even casually. Keep one speech level \
              throughout; never let choices differ only in politeness.
            - type "grammar": the blank replaces the 1–3 words a grammar point \
              decides. If a tense is tested, put a time word in the sentence; if a \
              particle or article, make the meaning clear. wrong: three forms that \
              are clearly wrong here for a grammar reason, the same kind of word as \
              the answer, the ones a learner would really reach for. point: the \
              grammar point in \(nativeName), 2–5 words. tip: one line in \(nativeName), \
              at most 14 words, on why the answer fits here.
            - type "expression": the answer is a common expression a \(level) learner \
              should know — a collocation, phrasal verb or set phrase of 2–4 words — \
              and the blank replaces all of it. wrong: three real expressions of the \
              same shape that do not fit this sentence's meaning; never a synonym of \
              the answer. point: what the expression means, in \(nativeName), at most \
              8 words. tip: "".
            - Every sentence, answer and choice is in \(targetName). point and tip are \
              in \(nativeName).
            Write \(batchPerKind) grammar questions (at most 2 per grammar point) and \
            \(batchPerKind) expression questions (each a different expression), each \
            sentence new. JSON only.
            """
        var user: String
        if own.isEmpty {
            user = "This learner has no recurring grammar slips on file yet."
        } else {
            user = "Grammar points this learner keeps getting wrong (their slip → the right form):\n"
                + own.enumerated().map { i, p in "\(i + 1). \(p.label): \"\(p.was)\" → \"\(p.now)\"" }
                    .joined(separator: "\n")
        }
        if own.count < minPoints {
            user += "\nAlso use grammar points a \(level) learner of \(targetName) is working on."
        }
        let known = Set(load().filter { $0.kind == .expression }.map { $0.answer.lowercased() })
        if !known.isEmpty {
            user += "\nExpressions already used — pick others: " + known.sorted().joined(separator: ", ")
        }

        let key = SHA256.hash(data: Data((system + user + "\(Date().timeIntervalSince1970)").utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        let payload: Payload
        do {
            payload = try await GeminiClient.shared.sendJSON(
                system: system, messages: [.init(role: .user, content: user)],
                maxTokens: 6000, purpose: "quiz",
                idempotencyKey: "quiz-stock:\(key)", requestTimeout: 45)
        } catch {
            Telemetry.log("quiz_stock_batch", ["stage": "write", "error": String(describing: error).prefix(200).description])
            return nil
        }

        var seen = Set(load().map { CarryoverDetector.normalized($0.sentence) })
        var written: [Stored] = []
        for it in payload.items {
            guard let q = validated(it, language: target),
                  seen.insert(CarryoverDetector.normalized(q.sentence)).inserted else { continue }
            written.append(q)
        }
        let added = await check(written, targetName: targetName, key: key)
        // One row per batch: how many were written, survived code, survived
        // the second reading — the only record of what the drop rate is.
        Telemetry.log("quiz_stock_batch", ["stage": "done", "written": "\(payload.items.count)",
                                             "valid": "\(written.count)", "kept": "\(added.count)",
                                             "kept_expressions": "\(added.filter { $0.kind == .expression }.count)",
                                             "own_points": "\(own.count)", "lang": target])
        guard !added.isEmpty else { return nil }
        save(load() + added)
        return added
    }

    private struct Verdicts: Decodable {
        struct Result: Decodable { let n: Int; let ok: [String] }
        let results: [Result]
    }

    /// Keeps the questions whose ONLY working choice is the answer, as judged
    /// by a call that is never told which one was meant. A failed check keeps
    /// nothing: an unchecked question is the bug this exists for.
    private static func check(_ questions: [Stored], targetName: String, key: String) async -> [Stored] {
        guard !questions.isEmpty else { return [] }
        let system = """
            You check fill-in-the-blank questions for \(targetName) learners. For each \
            numbered question, fill the blank with EACH choice in turn and decide \
            whether the resulting sentence is correct, natural \(targetName) that a \
            native speaker would accept in everyday speech (casual speech counts). \
            Judge each choice on its own; more than one, or none, may work.
            Return {"results":[{"n":1,"ok":["choice", ...]}]} listing every choice \
            that works. JSON only.
            """
        let user = questions.enumerated().map { i, q in
            "\(i + 1). \(q.sentence)\n   choices: \(([q.answer] + q.wrong).sorted().joined(separator: " | "))"
        }.joined(separator: "\n")
        let v: Verdicts
        do {
            v = try await GeminiClient.shared.sendJSON(
                system: system, messages: [.init(role: .user, content: user)],
                maxTokens: 4000, purpose: "quiz",
                idempotencyKey: "quiz-stock-check:\(key)", requestTimeout: 45)
        } catch {
            Telemetry.log("quiz_stock_batch", ["stage": "check", "error": String(describing: error).prefix(200).description])
            return []
        }
        let norm = CarryoverDetector.normalized
        return v.results.compactMap { r in
            guard questions.indices.contains(r.n - 1) else { return nil }
            let q = questions[r.n - 1]
            return r.ok.map(norm) == [norm(q.answer)] ? q : nil
        }
    }

    /// Code's half: one blank, four distinct choices, all in the target
    /// script, the answer not among the wrong ones.
    private static func validated(_ it: Payload.Item, language: String) -> Stored? {
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        // The model's blank comes back as "___" or "____" as often as ours.
        let blank = WeeklyTestEngine.blankMark
        let sentence = clean(it.sentence).replacingOccurrences(
            of: "_{2,}", with: blank, options: .regularExpression)
        let answer = clean(it.answer)
        let wrong = it.wrong.map(clean).filter { !$0.isEmpty }
        guard sentence.components(separatedBy: blank).count == 2,
              !answer.isEmpty, wrong.count == 3,
              Set(([answer] + wrong).map(CarryoverDetector.normalized)).count == 4,
              ([answer] + wrong).allSatisfy({ TextScript.isInTargetScript($0, language: language) }),
              TextScript.isInTargetScript(sentence.replacingOccurrences(of: blank, with: answer),
                                          language: language)
        else { return nil }
        return Stored(kind: it.kind, point: clean(it.point), tip: clean(it.tip ?? ""), sentence: sentence,
                      answer: answer, wrong: wrong, createdAt: Date())
    }
}
