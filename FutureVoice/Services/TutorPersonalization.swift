import Foundation

/// What this learner keeps getting wrong, for the material written for them
/// (docs/learner-record.md). A lesson or a model answer that needs one of
/// these forms practices the right one, inside the thing they came to say.
/// Empty leaves both prompts exactly as they were.
enum LearnerWeakPoints {
    static let maxPoints = 3

    /// Mistakes seen across several talks first; a new learner has none of
    /// those yet, so their latest ones stand in.
    static func lines(profile: LearnerProfile, sessions: [Session], now: Date = Date()) -> [String] {
        let proven = GrammarFocus.candidates(from: profile, sessions: sessions, now: now).map(\.pattern)
        let chosen = proven.isEmpty
            ? profile.recurringMistakes.sorted { $0.lastSeenAt > $1.lastSeenAt }
            : proven
        return chosen.prefix(maxPoints).map { "- \"\($0.mistake)\" → \"\($0.correction)\" (\($0.context))" }
    }

    /// Measured 2026-11-09 on a job-interview lesson, 6 runs: the weak forms
    /// appeared in every lesson, against 0 of 4 without this.
    static func plannerBlock(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        return """


        What this learner keeps getting wrong, from their own talks:
        \(lines.joined(separator: "\n"))
        Where the situation really needs one of these forms, write that challenge so it can't be said without it, and use the right form in its "example". Aim for two such challenges. Never bend a sentence to fit one: a form that doesn't belong in natural speech here is left out, and a word from the list above is not a word you have to use. The lesson stays about what they asked for, and "title" names that.
        """
    }

    static func goalPrepBlock(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        return """

        WHAT THIS LEARNER KEEPS GETTING WRONG (from their own talks)
        \(lines.joined(separator: "\n"))
        The model answer is what they will memorize: where it naturally needs one of these forms, use the right form. Never bend a sentence to fit one. If the answer uses one, the "summary" tip names it.
        """
    }
}

/// A second reader for lines a learner will memorize. The writer leaves
/// mistakes behind ("a opportunity", "gain an experience"), and this model
/// never wrote them. Measured 2026-11-09: 20 of 24 bad lines fixed, 2 of 96
/// good lines touched across five languages, 0.9 s. A failed check keeps the
/// lines as written.
enum MaterialCheck {
    static func system(target: String) -> String {
        """
        You check lines a \(target) learner will memorize and say out loud in real life. Numbered lines follow.
        For each line: would a native speaker say it exactly like this? Fix a line ONLY if it has a real error (grammar, article, a word that doesn't go with its neighbour) or no native speaker would ever say it. A plain or simple line is fine: never improve style, never make a line fancier or longer, never change a contraction, a speech level or a fact. A word that is right stays, even if another would be nicer: never swap it for a synonym. Make the smallest change that makes it right.
        Return STRICT JSON: {"fixes": [{"n": 1, "line": "the corrected line"}]}. No fixes: {"fixes": []}.
        """
    }

    /// Applies a reply to the lines it was asked about, ignoring a fix that
    /// names no line, is empty or rewrites far more than a correction would.
    static func apply(_ fixes: [(n: Int, line: String)], to lines: [String]) -> [String] {
        var out = lines
        for fix in fixes where lines.indices.contains(fix.n - 1) {
            let line = fix.line.trimmingCharacters(in: .whitespacesAndNewlines)
            let was = lines[fix.n - 1]
            guard !line.isEmpty, line.count <= was.count + max(12, was.count / 3) else { continue }
            out[fix.n - 1] = line
        }
        return out
    }

    static func corrected(_ lines: [String], language: String, purpose: String) async -> [String] {
        guard !lines.isEmpty else { return lines }
        struct Reply: Decodable {
            struct Fix: Decodable { let n: Int; let line: String }
            let fixes: [Fix]
        }
        let numbered = lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        guard let reply: Reply = try? await GeminiClient.shared.sendJSON(
            system: system(target: LanguageCatalog.englishName(language)),
            messages: [.init(role: .user, content: numbered)],
            model: .flashLite31, maxTokens: 2048, purpose: purpose,
            idempotencyKey: "material-check:\(UUID().uuidString)", requestTimeout: 8)
        else { return lines }
        let usable = reply.fixes.filter { TextScript.isInTargetScript($0.line, language: language) }
        return apply(usable.map { (n: $0.n, line: $0.line) }, to: lines)
    }

    /// The same for a paragraph, sentence by sentence.
    static func correctedText(_ text: String, language: String, purpose: String) async -> String {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
            if let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { sentences.append(t) }
        }
        let fixed = await corrected(sentences, language: language, purpose: purpose)
        var out = text
        for (old, new) in zip(sentences, fixed) where old != new {
            out = out.replacingOccurrences(of: old, with: new)
        }
        return out
    }
}
