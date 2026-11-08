import CryptoKit
import Foundation

/// The LEVEL TAGGING call (docs/personal-report-plan.md, step 3): which
/// level-map items did the learner produce in one talk, right or wrong?
///
/// Its own call after the summary, never a field in it: the summary schema's
/// order is load-bearing and its prompt is measured, and tagging had to be
/// measured on its own. It was — `scripts/level-tag-probe.py` reads
/// `systemPrompt` and the two line templates below from THIS file, so the
/// prompt cannot drift from the one measured (2026-10-27, gemini-3.6-flash,
/// thinking medium: grammar recall 96%, 0 trap tags over 14 labelled talks).
/// Re-run the probe before touching any of the three.
///
/// The model only REPORTS what it saw — counts and one verbatim quote per
/// verdict. Every quote is checked in code against the learner's own lines
/// (`isTheirs`), and an item whose quote isn't theirs is dropped; the status
/// an item ends up in is decided by `LearnerState.status`, never the model.
enum LevelTagger {
    static let purpose = "level-tag"
    /// Measured: low 91% recall, medium 96%, same zero false tags. The call
    /// runs after the talk and nobody waits on it, so the extra thinking is
    /// free time.
    static let thinkingLevel = "medium"
    /// Thinking spends from this ceiling. At 4096, 16 of 16 talks of 25 to
    /// 140 learner lines came back cut off (2026-11-09); at 8192, the server's
    /// own limit, 2 of 16 did. Those two go to `fallbackThinkingLevel`.
    static let maxTokens = 8192
    /// For a run that still hit the ceiling: 20 of 20 long talks finished.
    /// A slightly lower recall is better than no verdicts for that talk.
    static let fallbackThinkingLevel = "low"

    // MARK: - Prompt (read by scripts/level-tag-probe.py — keep the shape)

    static func grammarLine(_ g: LevelMap.Grammar) -> String {
        "- \(g.id): \(g.name). Counts: \(g.counts). Right: \"\(g.example)\" Wrong: \"\(g.error)\""
    }

    static func functionLine(_ f: LevelMap.Function) -> String {
        "- \(f.id): \(f.name). Counts: \(f.counts)."
    }

    static func systemPrompt(map: LevelMap, targetName: String) -> String {
        let grammarLines = map.grammar.map(grammarLine).joined(separator: "\n")
        let functionLines = map.functions.map(functionLine).joined(separator: "\n")
        return """
        You read one spoken \(targetName) conversation between a language learner (USER) and their fluent future self (AI), and record which items of a fixed list the LEARNER produced.

        GRAMMAR ITEMS — for each item the USER produced, count the times they used it RIGHT and the times they ATTEMPTED it with an error:
        \(grammarLines)

        FUNCTION ITEMS — what the USER did with the language:
        \(functionLines)

        RULES
        - Only USER lines count. A structure only the AI used is not the learner's, even if the learner answers it.
        - An item counts only when the learner's own sentence actually uses that structure. A look-alike is not the item: "I have a car" is not the present perfect; "I will" said as a word is not a future plan unless a verb follows; a bare word like "maybe" is not a modal.
        - ATTEMPTED WITH AN ERROR means they reached for that structure and formed it wrong ("I go yesterday" is a past_simple error; "since two weeks" with the present perfect is a present_perfect_since_for error). Using a simpler structure where a better one fits is NOT an error of the better one — it is simply not produced. ("Did you ever see…" for an experience question IS a present_perfect_experience error, because the item names that exact use.)
        - This is SPEECH from a transcriber: fillers (uh, um), repeated words, false starts, missing punctuation and capital letters, and contractions written out in full are never errors.
        - One error belongs to ONE item — the one it most directly breaks. A missing article is an articles error, not a present_simple error.
        - Be conservative: when unsure whether a structure is there, leave it out.
        - For each verdict give ONE short verbatim quote (3–12 words) copied exactly from a USER line.

        Return JSON only:
        {"grammar": [{"id": "...", "right": 0, "wrong": 0, "right_quote": "", "wrong_quote": ""}], "functions": [{"id": "...", "quote": ""}]}
        Leave right_quote empty when right is 0, wrong_quote empty when wrong is 0. Omit items the learner did not produce.
        """
    }

    /// Appended to the transcript when the talk carries verified fixes. NOT
    /// in the measured prompt (the probe's cases carry none, so a probe run
    /// sends the identical message), and it is a hint, not an instruction:
    /// the slips are already in the lines above.
    static let fixesHeader = "CORRECTIONS ALREADY CHECKED — real slips in the USER lines above, each with its right form. Use them to see which item each error breaks; never count one twice:"

    static func fixLine(was: String, now: String) -> String {
        "- \"\(was)\" → \"\(now)\""
    }

    // MARK: - Input

    /// The learner lines that may be judged: evidence only (not misheard,
    /// not read off the coach, not a tutor drill) and not empty.
    static func evidenceLines(_ turns: [Turn]) -> [String] {
        turns.filter(\.isEvidence)
            .map { $0.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// `USER:` / `AI:` lines, the probe's format. A learner line that isn't
    /// evidence is left out entirely rather than labelled: it was not their
    /// own sentence, and the model has nothing to do with it.
    static func transcript(_ turns: [Turn]) -> String {
        turns.compactMap { turn -> String? in
            let text = turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            switch turn.role {
            case .fluentSelf: return "AI: \(text)"
            case .user: return turn.isEvidence ? "USER: \(text)" : nil
            }
        }.joined(separator: "\n")
    }

    /// The talk's verified fixes: the live call's per-turn `fixes` on
    /// evidence turns, then the summary's phrase fixes whose quote is the
    /// learner's (the same gate `SessionSummarizer` applied), one per slip.
    static func fixes(in session: Session) -> [(was: String, now: String)] {
        let evidence = evidenceLines(session.turns)
        var seen = Set<String>()
        var out: [(was: String, now: String)] = []
        func add(_ was: String, _ now: String) {
            let w = was.trimmingCharacters(in: .whitespacesAndNewlines)
            let n = now.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalized(w)
            guard !w.isEmpty, !n.isEmpty, !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            out.append((w, n))
        }
        for turn in session.turns where turn.isEvidence {
            for fix in turn.suggestion?.fixes ?? [] { add(fix.was, fix.now) }
        }
        for phrase in session.summary?.phrasesUsed ?? [] where isTheirs(phrase.userSaid, in: evidence) {
            add(phrase.userSaid, phrase.fluentAlternative)
        }
        return out
    }

    static func userMessage(for session: Session) -> String {
        var message = transcript(session.turns)
        let fixes = fixes(in: session)
        if !fixes.isEmpty {
            message += "\n\n" + fixesHeader + "\n"
                + fixes.map { fixLine(was: $0.was, now: $0.now) }.joined(separator: "\n")
        }
        return message
    }

    /// What the learner said in this talk, hashed: a talk that is resumed
    /// (or has a line marked misheard) and summarized again is tagged again,
    /// its old contribution REPLACED; the same talk summarized twice is not.
    static func fingerprint(_ turns: [Turn]) -> String {
        let joined = evidenceLines(turns).joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - The quote check (mirrors the probe's `norm` / `theirs`)

    static let fillers: Set<String> = ["uh", "um", "er", "erm", "ah", "hmm", "mm", "eh"]

    /// Lowercased words with punctuation, fillers and stutters ("I am I am")
    /// removed — the transcriber's noise, which a quote may fairly leave out
    /// ("I am working on a new app" from "I am uh I am working on uh a new
    /// app"). A typographic apostrophe reads as a plain one, so a model's
    /// "I’m" still matches the recognizer's "I'm".
    static func normalized(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        var cleaned = String.UnicodeScalarView()
        for scalar in lowered.unicodeScalars {
            let keep = CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "'"
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
            cleaned.append(keep ? scalar : " ")
        }
        var words = String(cleaned)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !fillers.contains($0) }
        var changed = true
        while changed {
            changed = false
            search: for n in [3, 2, 1] where words.count >= 2 * n {
                for i in 0...(words.count - 2 * n)
                where Array(words[i..<i + n]) == Array(words[i + n..<i + 2 * n]) {
                    words.removeSubrange(i + n..<i + 2 * n)
                    changed = true
                    break search
                }
            }
        }
        return words.joined(separator: " ")
    }

    /// The quote, cleaned, is inside one of the learner's lines, cleaned.
    static func isTheirs(_ quote: String, in lines: [String]) -> Bool {
        let q = normalized(quote)
        return !q.isEmpty && lines.contains { normalized($0).contains(q) }
    }

    // MARK: - The answer

    struct Payload: Decodable {
        struct GrammarHit: Decodable {
            var id: String
            var right: Int
            var wrong: Int
            var rightQuote: String
            var wrongQuote: String

            enum CodingKeys: String, CodingKey {
                case id, right, wrong
                case rightQuote = "right_quote", wrongQuote = "wrong_quote"
            }
            init(id: String, right: Int, wrong: Int, rightQuote: String = "", wrongQuote: String = "") {
                self.id = id; self.right = right; self.wrong = wrong
                self.rightQuote = rightQuote; self.wrongQuote = wrongQuote
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                right = (try? c.decodeIfPresent(Int.self, forKey: .right)) ?? 0
                wrong = (try? c.decodeIfPresent(Int.self, forKey: .wrong)) ?? 0
                rightQuote = (try? c.decodeIfPresent(String.self, forKey: .rightQuote)) ?? ""
                wrongQuote = (try? c.decodeIfPresent(String.self, forKey: .wrongQuote)) ?? ""
            }
        }
        struct FunctionHit: Decodable {
            var id: String
            var quote: String
            init(id: String, quote: String) { self.id = id; self.quote = quote }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                quote = (try? c.decodeIfPresent(String.self, forKey: .quote)) ?? ""
            }
            enum CodingKeys: String, CodingKey { case id, quote }
        }
        var grammar: [GrammarHit]
        var functions: [FunctionHit]

        init(grammar: [GrammarHit], functions: [FunctionHit]) {
            self.grammar = grammar; self.functions = functions
        }
        // One malformed entry costs that entry, not the talk.
        init(from decoder: Decoder) throws {
            struct Lossy<T: Decodable>: Decodable {
                let value: T?
                init(from decoder: Decoder) throws { value = try? T(from: decoder) }
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            grammar = ((try? c.decodeIfPresent([Lossy<GrammarHit>].self, forKey: .grammar)) ?? nil)?
                .compactMap(\.value) ?? []
            functions = ((try? c.decodeIfPresent([Lossy<FunctionHit>].self, forKey: .functions)) ?? nil)?
                .compactMap(\.value) ?? []
        }
        enum CodingKeys: String, CodingKey { case grammar, functions }
    }

    /// A verdict above this is the model counting something else (every
    /// article in a monologue) — kept, but not allowed to swamp the state.
    static let maxCountPerTalk = 20
    static let maxQuoteLength = 160

    /// The payload checked against the map and the learner's lines. An item
    /// not on the map, with no use, or with a quote that isn't the learner's
    /// is dropped (`dropped` counts the last kind — the measure of how often
    /// the model put words in their mouth). Same rule as the probe: BOTH
    /// quotes a verdict needs must be theirs.
    static func verify(_ payload: Payload, map: LevelMap, evidence: [String])
        -> (items: [LearnerState.ItemTag], dropped: Int) {
        let grammarIds = Set(map.grammar.map(\.id))
        let functionIds = Set(map.functions.map(\.id))
        var items: [LearnerState.ItemTag] = []
        var taken = Set<String>()
        var dropped = 0
        func clip(_ q: String) -> String {
            let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.count > maxQuoteLength ? String(t.prefix(maxQuoteLength)) : t
        }
        for hit in payload.grammar where grammarIds.contains(hit.id) && !taken.contains(hit.id) {
            let right = min(max(hit.right, 0), maxCountPerTalk)
            let wrong = min(max(hit.wrong, 0), maxCountPerTalk)
            guard right + wrong > 0 else { continue }
            let rightOK = right == 0 || isTheirs(hit.rightQuote, in: evidence)
            let wrongOK = wrong == 0 || isTheirs(hit.wrongQuote, in: evidence)
            guard rightOK && wrongOK else { dropped += 1; continue }
            var quotes: [LearnerState.Quote] = []
            if wrong > 0 { quotes.append(.init(text: clip(hit.wrongQuote), right: false)) }
            if right > 0 { quotes.append(.init(text: clip(hit.rightQuote), right: true)) }
            items.append(.init(id: hit.id, kind: .grammar, right: right, wrong: wrong, quotes: quotes))
            taken.insert(hit.id)
        }
        for hit in payload.functions where functionIds.contains(hit.id) && !taken.contains(hit.id) {
            guard isTheirs(hit.quote, in: evidence) else { dropped += 1; continue }
            // A function is DONE or not; one talk counts once.
            items.append(.init(id: hit.id, kind: .function, right: 1, wrong: 0,
                               quotes: [.init(text: clip(hit.quote), right: true)]))
            taken.insert(hit.id)
        }
        return (items, dropped)
    }

    // MARK: - The call

    struct Outcome {
        var tag: LearnerState.SessionTag
        var dropped: Int
    }

    /// A fresh key per request. The server treats a repeated key as a retry
    /// only for ten minutes and answers 409 after that, so a key made from
    /// the talk alone refused every later attempt, and each refusal counted
    /// as a failure of the talk. The `level-tag:` prefix is what the server
    /// reads; the daily cap still counts every request.
    static func requestKey(sessionId: UUID, fingerprint: String) -> String {
        "level-tag:\(sessionId.uuidString):\(fingerprint):\(UUID().uuidString.prefix(8))"
    }

    /// Tags one talk. Nil when the language has no map or the learner said
    /// nothing that counts; throws only on the network/decode.
    static func tag(_ session: Session) async throws -> Outcome? {
        guard let map = LevelMap.load(session.targetLanguage) else { return nil }
        let evidence = evidenceLines(session.turns)
        guard !evidence.isEmpty else { return nil }
        let fingerprint = fingerprint(session.turns)
        let system = systemPrompt(map: map,
                                  targetName: LanguageCatalog.englishName(session.targetLanguage))
        // `longRunning`: medium thinking over a long talk can pass the 60 s
        // ceiling the other sessions have, and a run nobody waits on has no
        // reason to give up there. It is also not the live call's pool.
        func send(thinking: String) async throws -> Payload {
            try await GeminiClient.longRunning.sendJSON(
                system: system,
                messages: [.init(role: .user, content: userMessage(for: session))],
                model: .flash36,
                maxTokens: maxTokens,
                purpose: purpose,
                idempotencyKey: requestKey(sessionId: session.id, fingerprint: fingerprint),
                thinkingLevel: thinking)
        }
        let payload: Payload
        do {
            payload = try await send(thinking: thinkingLevel)
        } catch GeminiError.truncated {
            payload = try await send(thinking: fallbackThinkingLevel)
        }
        let (items, dropped) = verify(payload, map: map, evidence: evidence)
        let talkDate = session.turns.last?.timestamp ?? session.endedAt ?? session.startedAt
        let tag = LearnerState.SessionTag(talkDate: talkDate, taggedAt: Date(),
                                          fingerprint: fingerprint, mapVersion: map.version,
                                          items: items)
        return Outcome(tag: tag, dropped: dropped)
    }
}
