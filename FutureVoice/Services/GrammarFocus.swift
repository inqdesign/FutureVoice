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
/// - `pick` chooses ONE pattern per call — SAID in at least `minTalks`
///   different talks within `freshDays` (`evidence`, counted from the
///   transcripts, not the profile's frequency), a grammar point and not a
///   word choice (`describe`), not retired — most talks first. One focus, because
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
    /// How many talks the learner actually SAID this slip in — the reason
    /// it is the focus, shown on the strip. 0 when not counted.
    var talks: Int = 0

    var key: String { LearnerProfile.patternKey(pattern) }

    static let minFrequency = 2
    static let freshDays = 45
    static let retireAfterCleanCalls = 2
    /// A focus needs the slip in at least this many different talks.
    static let minTalks = 2

    func record(repeats: Int) -> GrammarFocusRecord {
        GrammarFocusRecord(patternKey: key, label: label, mistake: pattern.mistake,
                           correction: pattern.correction, repeats: repeats)
    }

    // MARK: - Pick

    /// The talks (within `freshDays`) in which the learner really said
    /// `pattern.mistake` — quoted from their own turns, the summary's
    /// `isTheirs` rule. This, not `frequency`, is the evidence: frequency
    /// was inflated for weeks by summaries copying the profile's patterns
    /// back out (fixed 2026-10-08), and a count the learner can't trace to
    /// a talk is what made the strip read as random — one founder's only
    /// pattern stood at 5 while appearing in none of their talks' text.
    static func evidence(_ pattern: LearnerPattern, sessions: [Session], now: Date = Date()) -> Int {
        let fresh = now.addingTimeInterval(-Double(freshDays) * 86_400)
        return sessions.filter { s in
            guard s.archivedAt == nil, (s.endedAt ?? s.startedAt) >= fresh else { return false }
            return s.turns.contains { t in
                t.role == .user && !t.excludedFromScoring
                    && ConversationEngine.quotes(pattern.mistake, from: t.transcript)
            }
        }.count
    }

    /// Patterns said in at least `minTalks` talks, not retired, most talks
    /// first. Grammar or not is decided later, by `describe`.
    static func candidates(from profile: LearnerProfile, sessions: [Session],
                           now: Date = Date()) -> [(pattern: LearnerPattern, talks: Int)] {
        profile.recurringMistakes
            .filter { !isRetired($0, sessions: sessions) }
            .map { (pattern: $0, talks: evidence($0, sessions: sessions, now: now)) }
            .filter { $0.talks >= minTalks }
            .sorted { ($0.talks, $0.pattern.lastSeenAt) > ($1.talks, $1.pattern.lastSeenAt) }
    }

    /// This call's focus: the first candidate that is a GRAMMAR point
    /// (`describe` turns a word mix-up away — "한글 → 한국어" is vocabulary,
    /// and a strip calling it the call's grammar focus was the other half
    /// of the report). nil = no strip.
    @MainActor
    static func pick(from profile: LearnerProfile, sessions: [Session], target: String,
                     native: String, now: Date = Date()) async -> GrammarFocus? {
        for c in candidates(from: profile, sessions: sessions, now: now).prefix(3) {
            guard var focus = await describe(c.pattern, target: target, native: native) else { continue }
            focus.talks = c.talks
            return focus
        }
        return nil
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

    private struct Description: Codable { let label: String; let tip: String; let grammar: Bool? }
    /// v2 (2026-10-08) carries the grammar-or-word verdict; v1 entries
    /// lack it and are asked again.
    private static let cacheKey = "futurevoice.coach.focusDescriptions.v2"

    /// Name the pattern in `native`. nil when the call fails — the call then
    /// runs without a focus rather than with an unnamed one — and nil when
    /// the slip is a word choice rather than a grammar point (verdict cached).
    @MainActor
    static func describe(_ pattern: LearnerPattern, target: String,
                         native: String) async -> GrammarFocus? {
        let key = "\(LearnerProfile.patternKey(pattern))|\(native)"
        var cache = (UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: [String: String]]) ?? [:]
        if let hit = cache[key], let label = hit["label"], let tip = hit["tip"] {
            guard hit["grammar"] != "false" else { return nil }
            return GrammarFocus(pattern: pattern, label: label, tip: tip)
        }
        let nativeName = LanguageCatalog.englishName(native)
        let targetName = LanguageCatalog.englishName(target)
        let system = """
            A \(targetName) learner keeps making one mistake. Name the grammar \
            point it belongs to, for a label they read mid-call, and say in one \
            short sentence what to watch for.

            First decide: is it a GRAMMAR point (a form, an ending, word order, \
            an article, a particle, a tense — a rule that applies to other words \
            too), or a WORD choice (one word or name confused with another, a \
            collocation)? Set "grammar" to true or false.

            Return {"grammar": true, "label": "...", "tip": "..."}, label and tip in \(nativeName):
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
            idempotencyKey: "coach-focus-v2:\(Self.digest(key))", requestTimeout: 8,
            fastThinking: true) else { return nil }
        let label = d.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = d.tip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        let grammar = d.grammar ?? true
        cache[key] = ["label": label, "tip": tip, "grammar": grammar ? "true" : "false"]
        UserDefaults.standard.set(cache, forKey: cacheKey)
        guard grammar else { return nil }
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
