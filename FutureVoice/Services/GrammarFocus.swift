import CryptoKit
import Foundation

/// Coach mode's GRAMMAR focus (2026-09-30): the slip this learner keeps
/// making, named once at the top of the call and watched for the rest of it.
///
/// Coach mode began as words only — "Try using · profound" under a question
/// built for it. The founder asked for a coach that goes past words: "if
/// they keep making the same grammar mistake, tell them to mind the tense".
/// The material was already on disk: every summary folds its
/// `new_patterns_detected` into `LearnerProfile.recurringMistakes` with a
/// frequency, and every live turn carries its `fixes`. Nothing read them
/// back during a call.
///
/// Three pieces, all here:
/// - `pick` chooses ONE pattern per call — seen at least twice, heard within
///   `freshDays`, not retired — highest frequency first. One focus, because
///   a coach naming three things at once is naming none.
/// - `describe` names it in the learner's language ("과거 시제") with one
///   line of what to watch — coaching, so native; the pair itself stays in
///   the target language. Cached per pattern, so it is written once.
/// - `isRepeat` judges each live correction: is this the SAME slip again?
///   A model call, because "the same mistake" is a category (a tense, an
///   article) and no string test sees that `goed`→`went` and `buyed`→
///   `bought` are one thing. It only answers yes/no; the COUNT is code.
///
/// Retirement is by evidence: a pattern focused in `retireAfterCleanCalls`
/// calls with no repeat, and not re-detected by a summary since
/// (`lastSeenAt` would move), steps aside for the next one. A re-detection
/// brings it straight back.
struct GrammarFocus: Equatable {
    let pattern: LearnerPattern
    let label: String
    let tip: String

    var key: String { LearnerProfile.patternKey(pattern) }

    static let minFrequency = 2
    static let freshDays = 45
    static let retireAfterCleanCalls = 2

    func record(repeats: Int) -> GrammarFocusRecord {
        GrammarFocusRecord(patternKey: key, label: label, mistake: pattern.mistake,
                           correction: pattern.correction, repeats: repeats)
    }

    // MARK: - Pick

    static func pick(from profile: LearnerProfile, sessions: [Session],
                     now: Date = Date()) -> LearnerPattern? {
        let fresh = now.addingTimeInterval(-Double(freshDays) * 86_400)
        return profile.recurringMistakes
            .filter { $0.frequency >= minFrequency && $0.lastSeenAt >= fresh }
            .filter { !isRetired($0, sessions: sessions) }
            .sorted { ($0.frequency, $0.lastSeenAt) > ($1.frequency, $1.lastSeenAt) }
            .first
    }

    static func isRetired(_ pattern: LearnerPattern, sessions: [Session]) -> Bool {
        let key = LearnerProfile.patternKey(pattern)
        let clean = sessions.filter {
            guard let f = $0.grammarFocus, f.patternKey == key, f.repeats == 0 else { return false }
            return ($0.endedAt ?? $0.startedAt) > pattern.lastSeenAt
        }
        return clean.count >= retireAfterCleanCalls
    }

    // MARK: - Describe

    private struct Description: Codable { let label: String; let tip: String }
    private static let cacheKey = "futurevoice.coach.focusDescriptions"

    /// Name the pattern in `native`. nil when the call fails — the call then
    /// runs without a focus rather than with an unnamed one.
    @MainActor
    static func describe(_ pattern: LearnerPattern, target: String,
                         native: String) async -> GrammarFocus? {
        let key = "\(LearnerProfile.patternKey(pattern))|\(native)"
        var cache = (UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: [String: String]]) ?? [:]
        if let hit = cache[key], let label = hit["label"], let tip = hit["tip"] {
            return GrammarFocus(pattern: pattern, label: label, tip: tip)
        }
        let nativeName = LanguageCatalog.englishName(native)
        let targetName = LanguageCatalog.englishName(target)
        let system = """
            A \(targetName) learner keeps making one mistake. Name the grammar \
            point it belongs to, for a label they read mid-call, and say in one \
            short sentence what to watch for.

            Return {"label": "...", "tip": "..."}, both in \(nativeName):
            - label: the grammar point as a learner would say it, 2–4 words \
              (e.g. "past tense", "articles a/the", "subject particle"). Not \
              the example, not a sentence.
            - tip: one plain sentence, at most 12 words, about WHEN it applies. \
              Friendly, never scolding, no grammar jargon beyond the label.
            """
        let content = """
            They said: "\(pattern.mistake)"
            Fluent: "\(pattern.correction)"
            Note: \(pattern.context)
            """
        guard let d: Description = try? await GeminiClient.background.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: content)],
            model: .flashLite31, maxTokens: 200, purpose: "coach",
            idempotencyKey: "coach-focus:\(Self.digest(key))", requestTimeout: 8,
            fastThinking: true) else { return nil }
        let label = d.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = d.tip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        cache[key] = ["label": label, "tip": tip]
        UserDefaults.standard.set(cache, forKey: cacheKey)
        return GrammarFocus(pattern: pattern, label: label, tip: tip)
    }

    private static func digest(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Repeat

    private struct Verdict: Decodable { let same: Bool }

    /// Is any of this turn's fixes the same kind of slip as the focus?
    @MainActor
    func isRepeat(_ fixes: [TurnFix], turnId: UUID) async -> Bool {
        guard !fixes.isEmpty else { return false }
        let list = fixes.map { "- \"\($0.was)\" → \"\($0.now)\"" }.joined(separator: "\n")
        let system = """
            A language learner is working on one recurring mistake. Decide \
            whether any of the new corrections is the SAME KIND of mistake — \
            the same grammar point, even with different words (a wrong past \
            form is a wrong past form whatever the verb). A different point \
            that happens to sit in the same sentence does not count.
            Return {"same": true} or {"same": false}. When unsure, false.
            """
        let content = """
            Recurring mistake: "\(pattern.mistake)" → "\(pattern.correction)" (\(pattern.context))
            New corrections:
            \(list)
            """
        let v: Verdict? = try? await GeminiClient.background.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: content)],
            model: .flashLite31, maxTokens: 100, purpose: "coach",
            idempotencyKey: "coach-repeat:\(turnId.uuidString)", requestTimeout: 8,
            fastThinking: true)
        return v?.same ?? false
    }
}
