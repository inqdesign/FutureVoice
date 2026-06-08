import Foundation

/// Deterministic metrics computed from a session's turns. Passed as evidence
/// into the summary prompt so the LLM grounds its 0–100 scores in real numbers
/// instead of vibes. Kept side-effect-free so it can be unit-tested later.
struct ScorecardMetrics: Codable {
    var userTurnCount: Int
    var userWordCount: Int
    var uniqueWordCount: Int
    var typeTokenRatio: Double            // unique / total, 0…1
    var avgWordsPerUserTurn: Double
    var totalUserSpeakingSeconds: Double
    var wordsPerMinute: Double            // 0 when we have no timing
    var suggestionCount: Int              // user turns the LLM flagged with a rephrase
    var suggestionRate: Double            // suggestions / userTurnCount, 0…1
    var selfCorrectionHits: Int           // crude regex count for "I mean", "uh", etc.

    static func compute(turns: [Turn]) -> ScorecardMetrics {
        let userTurns = turns.filter { $0.role == .user }
        let allWords = userTurns
            .flatMap { tokens(in: $0.transcript) }

        let userWordCount = allWords.count
        let uniqueWords = Set(allWords.map { $0.lowercased() })
        let ttr = userWordCount > 0 ? Double(uniqueWords.count) / Double(userWordCount) : 0
        let avgWords = userTurns.isEmpty ? 0 : Double(userWordCount) / Double(userTurns.count)

        let secondsSpoken = userTurns.reduce(0.0) { $0 + Double($1.durationMs) / 1000.0 }
        let wpm: Double
        if secondsSpoken > 0 {
            wpm = (Double(userWordCount) / secondsSpoken) * 60.0
        } else {
            wpm = 0
        }

        let suggestionCount = userTurns.filter { $0.suggestion != nil }.count
        let suggestionRate = userTurns.isEmpty ? 0 : Double(suggestionCount) / Double(userTurns.count)

        let selfCorrections = userTurns.reduce(0) { acc, turn in
            acc + selfCorrectionMatches(in: turn.transcript)
        }

        return ScorecardMetrics(
            userTurnCount: userTurns.count,
            userWordCount: userWordCount,
            uniqueWordCount: uniqueWords.count,
            typeTokenRatio: ttr,
            avgWordsPerUserTurn: avgWords,
            totalUserSpeakingSeconds: secondsSpoken,
            wordsPerMinute: wpm,
            suggestionCount: suggestionCount,
            suggestionRate: suggestionRate,
            selfCorrectionHits: selfCorrections
        )
    }

    /// Compact JSON for inlining into the summary prompt — keeps the model
    /// honest by giving it the numbers it would otherwise guess at.
    func promptJSON() -> String {
        let payload: [String: Any] = [
            "user_turn_count": userTurnCount,
            "user_word_count": userWordCount,
            "unique_word_count": uniqueWordCount,
            "type_token_ratio": String(format: "%.2f", typeTokenRatio),
            "avg_words_per_turn": String(format: "%.1f", avgWordsPerUserTurn),
            "total_user_speaking_seconds": Int(totalUserSpeakingSeconds.rounded()),
            "words_per_minute": Int(wordsPerMinute.rounded()),
            "suggestion_count": suggestionCount,
            "suggestion_rate": String(format: "%.2f", suggestionRate),
            "self_correction_hits": selfCorrectionHits
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Helpers

    private static func tokens(in text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Crude self-correction / hesitation hit count. Phase 1 heuristic only —
    /// real prosody analysis comes later.
    private static let selfCorrectionPatterns: [String] = [
        "I mean", "i mean", "uh ", " uh,", " um ", " um,", "you know,", "like,", "wait,"
    ]

    private static func selfCorrectionMatches(in text: String) -> Int {
        selfCorrectionPatterns.reduce(0) { acc, needle in
            acc + text.components(separatedBy: needle).count - 1
        }
    }
}
