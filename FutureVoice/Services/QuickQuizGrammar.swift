import CryptoKit
import Foundation

/// The quick quiz's grammar questions (2026-10-18, founder: "words,
/// expressions and grammar").
///
/// A grammar question is a NEW everyday line with a blank and four forms for
/// it, exactly one of which fits. They are written by one model call per
/// batch and kept on disk (`quiz_grammar.json`, per language), so most
/// quizzes ask nothing of the model: a batch is written only when fewer than
/// `refillBelow` unasked questions are left, and a quiz waits for it at most
/// `writeWait` — past that it goes without and the batch lands for the next.
///
/// What the questions are ABOUT: the learner's own recurring grammar points
/// first — the ones the call's grammar focus trusts (`GrammarFocus.candidates`:
/// said in two talks or more, judged a grammar point by `describe`) — and,
/// when there are fewer than `minPoints` of those, the grammar a learner at
/// their level is working on. Never the learner's transcript: the line is
/// written fresh, so nothing a recognizer misheard can become an answer.
///
/// The model writes; code decides what is kept (one blank, four distinct
/// choices in the target script, the answer among them) and grades. Then a
/// SECOND call, not told the answer, marks every choice that makes the line
/// correct, and a question is kept only when that is the answer alone
/// (`check`). Measured on the first prompt (ko/en/de, 24 questions): 3 had
/// two right answers ("밤을 새워서 / 새우느라고 피곤해요", "ate a / the
/// sandwich"); the check dropped all three, plus a few stricter calls.
@MainActor
enum QuickQuizGrammar {
    struct Stored: Codable, Identifiable {
        var id = UUID()
        let point: String
        let tip: String
        let sentence: String
        let answer: String
        let wrong: [String]
        var asked: Int = 0
        let createdAt: Date
    }

    /// Below this many unasked questions, a batch is written.
    static let refillBelow = 6
    static let batchSize = 10
    /// The learner's own points the batch is built on, at most.
    static let maxPoints = 4
    /// With fewer of the learner's own points, the level's grammar fills in.
    static let minPoints = 2
    /// How long a quiz waits for a batch it needs now.
    static let writeWait: TimeInterval = 12
    /// A question is retired once asked this often; the stock is capped.
    static let maxAsked = 2
    static let maxStored = 40

    private static var fileURL: URL {
        LanguageScope.activeDirectory.appendingPathComponent("quiz_grammar.json")
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
        load().filter { $0.asked == 0 }.count < refillBelow
    }

    /// Fill the stock before anyone opens a quiz, so the first one has
    /// grammar in it (the Talk tab calls this when the quiz button appears).
    static func prewarm(appState: AppState) {
        // A batch that just failed (offline, signed out) is not retried on
        // every return to the tab.
        guard needsBatch, Date().timeIntervalSince(lastFailure) > 600 else { return }
        _ = startWriting(appState: appState)
    }

    /// Up to `count` questions, least-asked first and one per grammar point,
    /// marked as asked. Writes a batch first when the stock is low.
    static func items(appState: AppState, count: Int) async -> [QuickQuizItem] {
        var stock = load().filter { $0.asked < maxAsked }
        if needsBatch {
            let writing = startWriting(appState: appState)
            if stock.count < count {
                // Nothing to ask without it: wait, but not for long.
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

        var picked: [Stored] = []
        var points = Set<String>()
        for q in stock.sorted(by: { ($0.asked, $0.createdAt) < ($1.asked, $1.createdAt) }) {
            guard picked.count < count else { break }
            guard points.insert(q.point.lowercased()).inserted else { continue }
            picked.append(q)
        }
        guard !picked.isEmpty else { return [] }

        let ids = Set(picked.map(\.id))
        var all = load()
        for i in all.indices where ids.contains(all[i].id) { all[i].asked += 1 }
        save(all)

        return picked.map { q in
            QuickQuizItem(kind: .grammar, prompt: q.sentence, answer: q.answer,
                          options: ([q.answer] + q.wrong).shuffled(),
                          heading: q.point, note: q.tip.isEmpty ? nil : q.tip)
        }
    }

    // MARK: - Writing

    private struct Payload: Decodable {
        struct Item: Decodable {
            let point: String
            let tip: String?
            let sentence: String
            let answer: String
            let wrong: [String]
        }
        let items: [Item]
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
            You write quick grammar questions for a \(targetName) learner whose own \
            language is \(nativeName), level \(level). Each question is ONE everyday \
            \(targetName) sentence with exactly one blank "\(WeeklyTestEngine.blankMark)" \
            and four choices for it. Exactly ONE choice is correct.

            Return {"items":[{"point":"...","tip":"...","sentence":"...","answer":"...","wrong":["...","...","..."]}]}
            - sentence: spoken and ordinary, \(WordSplitter.spaced ? "5–12 words" : "8–25 characters"), \
              at their level, about everyday life\(spokenTopics.isEmpty ? "" : " (their recent topics: \(spokenTopics.joined(separator: "; ")))"). \
              The blank replaces 1–3 words: the part the grammar point decides.
            - The sentence must leave ONLY the answer possible. If a tense is tested, \
              put a time word in the sentence; if a particle or article, make the \
              meaning clear. Never write a blank two choices could both fill, not \
              even casually.
            - wrong: three forms that are clearly wrong in THIS sentence for a \
              grammar reason, the same kind of word as the answer, and the ones a \
              learner would really reach for. Never a synonym of the answer. Never \
              a choice that differs only in politeness or speech level: keep one \
              speech level throughout.
            - point: the grammar point in \(nativeName), 2–5 words. tip: one line in \
              \(nativeName), at most 14 words, on why the answer fits here.
            - Every sentence, answer and choice is in \(targetName). point and tip are \
              in \(nativeName).
            Write \(batchSize) questions, at most 2 per grammar point, each sentence new. JSON only.
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

        let key = SHA256.hash(data: Data((system + user + "\(Date().timeIntervalSince1970)").utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        let payload: Payload
        do {
            payload = try await GeminiClient.shared.sendJSON(
                system: system, messages: [.init(role: .user, content: user)],
                maxTokens: 3000, purpose: "quiz",
                idempotencyKey: "quiz-grammar:\(key)", requestTimeout: 30)
        } catch {
            Telemetry.log("quiz_grammar_batch", ["stage": "write", "error": String(describing: error).prefix(200).description])
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
        Telemetry.log("quiz_grammar_batch", ["stage": "done", "written": "\(payload.items.count)",
                                             "valid": "\(written.count)", "kept": "\(added.count)",
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
                maxTokens: 2000, purpose: "quiz",
                idempotencyKey: "quiz-grammar-check:\(key)", requestTimeout: 30)
        } catch {
            Telemetry.log("quiz_grammar_batch", ["stage": "check", "error": String(describing: error).prefix(200).description])
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
        return Stored(point: clean(it.point), tip: clean(it.tip ?? ""), sentence: sentence,
                      answer: answer, wrong: wrong, createdAt: Date())
    }
}
