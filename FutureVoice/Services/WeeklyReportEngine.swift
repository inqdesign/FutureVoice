import Foundation

/// Generates `WeeklyReport`s from accumulated sessions.
///
/// Design philosophy: we don't grade individual sessions (sample too small,
/// scores too noisy). Instead we accumulate transcripts until we have
/// enough material to produce something honest: concrete phrases the user
/// produced for the first time, suggestion patterns that recurred, and
/// vocabulary the user *should* be reaching for but isn't.
///
/// Unlock rules:
///   1. First report unlocks at 5 lifetime ended sessions.
///   2. Subsequent reports unlock when *both* are true:
///      - ≥ 7 days since the previous report's `periodEnd`, AND
///      - ≥ 3 sessions ended since the previous report's `periodEnd`.
///   These thresholds favor honesty over engagement — we'd rather show
///   nothing than show a noisy report.
enum WeeklyReportEngine {

    /// Cumulative user-speaking time required before the first report. "15
    /// minutes of you actually talking" is a more honest sample-size
    /// threshold than "5 sessions" — five 30-second exchanges have nothing
    /// to analyze. Length of practice maps directly to how much material
    /// the model sees, regardless of how many sessions it was spread across.
    static let firstReportMinSeconds: Double = 15 * 60

    /// Additional speaking time needed for each subsequent report.
    static let recurringMinSeconds: Double = 10 * 60
    static let recurringMinDays = 7

    /// Sum of user-turn durations across a list of sessions. Drives every
    /// unlock decision and the progress bar in the UI, so they stay in sync.
    static func totalUserSpeakingSeconds(_ sessions: [Session]) -> Double {
        var total: Double = 0
        for session in sessions {
            for turn in session.turns where turn.role == .user {
                total += Double(turn.durationMs) / 1000.0
            }
        }
        return total
    }

    // MARK: - Unlock state

    enum UnlockState {
        /// No report yet. UI shows X / 15 min progress.
        case lockedFirst(secondsAccumulated: Double, secondsRequired: Double)
        /// At least one report exists; waiting for the next cadence window.
        case lockedNext(daysRemaining: Int, secondsRemaining: Double)
        /// Ready to generate now.
        case ready
    }

    static func unlockState(
        endedSessions: [Session],
        lastReport: WeeklyReport?,
        now: Date = Date()
    ) -> UnlockState {
        if let last = lastReport {
            let newSessions = endedSessions.filter { ($0.endedAt ?? .distantPast) > last.periodEnd }
            let secondsSince = totalUserSpeakingSeconds(newSessions)
            let daysSince = Int(now.timeIntervalSince(last.periodEnd) / 86400)
            let daysRem = max(0, recurringMinDays - daysSince)
            let secRem = max(0, recurringMinSeconds - secondsSince)
            return (daysRem == 0 && secRem == 0)
                ? .ready
                : .lockedNext(daysRemaining: daysRem, secondsRemaining: secRem)
        } else {
            let total = totalUserSpeakingSeconds(endedSessions)
            return total >= firstReportMinSeconds
                ? .ready
                : .lockedFirst(secondsAccumulated: total, secondsRequired: firstReportMinSeconds)
        }
    }

    // MARK: - Generation

    /// Builds a report from sessions in the window. Caller is expected to
    /// have already verified `unlockState == .ready`. Throws if Gemini
    /// returns malformed JSON or if there are no user turns to analyze.
    static func generate(
        endedSessions: [Session],
        lastReport: WeeklyReport?,
        targetLanguage: String,
        now: Date = Date()
    ) async throws -> WeeklyReport {
        // Window: everything since the last report, or everything ever for the first.
        let windowStart = lastReport?.periodEnd ?? .distantPast
        let windowSessions = endedSessions.filter { ($0.endedAt ?? .distantPast) > windowStart }
        guard !windowSessions.isEmpty else { throw WeeklyReportError.noSessions }

        // Prior corpus = user turns from sessions BEFORE the window. Used by
        // the model to decide which phrases are genuinely "new".
        let priorUserUtterances = endedSessions
            .filter { ($0.endedAt ?? .distantPast) <= windowStart }
            .flatMap { $0.turns }
            .filter { $0.role == .user && !$0.excludedFromScoring }
            .map { $0.transcript }

        let windowUserUtterances = windowSessions
            .flatMap { $0.turns }
            .filter { $0.role == .user && !$0.excludedFromScoring }
            .map { $0.transcript }

        guard !windowUserUtterances.isEmpty else { throw WeeklyReportError.noSessions }

        // Suggestion pairs from this window — fed in so Gemini can spot
        // *recurring* corrections rather than treating each turn fresh.
        // Two sources, deduped: live per-turn suggestions AND each session
        // summary's phrase feedback. Older sessions predate per-turn
        // suggestions, so the summary source keeps them analyzable.
        var suggestionPairs: [(said: String, alt: String)] = []
        var seenPairs = Set<String>()
        func addPair(said: String, alt: String) {
            let key = said.lowercased().trimmingCharacters(in: .whitespaces)
                + "→" + alt.lowercased().trimmingCharacters(in: .whitespaces)
            guard !seenPairs.contains(key) else { return }
            seenPairs.insert(key)
            suggestionPairs.append((said, alt))
        }
        for session in windowSessions {
            for turn in session.turns where !turn.excludedFromScoring {
                if let s = turn.suggestion { addPair(said: turn.transcript, alt: s.alternative) }
            }
            for phrase in session.summary?.phrasesUsed ?? [] {
                addPair(said: phrase.userSaid, alt: phrase.fluentAlternative)
            }
        }

        // Measured delivery pooled across the window — evidence the judge
        // cannot get from text: pace (invisible in a transcript), verified
        // grammar-slip density (transcript noise excluded), and each talk's
        // own holistic AI read. Without these the text-only judgment reads
        // the correction pile as error density and defaults to a cautious
        // floor a band or two below the measured profile.
        let windowTurns = windowSessions.flatMap { $0.turns }
        let metrics = ScorecardMetrics.compute(turns: windowTurns)
        let slipCount = windowSessions.reduce(0) { $0 + ($1.summary?.grammarIssues.count ?? 0) }
        let slipsPer10 = metrics.userTurnCount > 0
            ? Double(slipCount) / Double(metrics.userTurnCount) * 10 : 0
        let talkReads = windowSessions.compactMap { $0.summary?.scorecard?.cefrLevel?.uppercased() }
        let deliveryEvidence = """
        - articulation_rate_wpm: \(Int(metrics.articulationRate.rounded())) \
        (words per minute of VOICED speech, pauses removed; 0 = no timing data. \
        Learner bands: <60 A1, 60-85 A2, 85-105 B1, 105-125 B2, 125-145 C1, 145+ C2)
        - avg_words_per_turn: \(Int(metrics.avgWordsPerUserTurn.rounded()))
        - verified_grammar_slips_per_10_turns: \(String(format: "%.1f", slipsPer10)) \
        (transcript-verified real grammar errors only — STT artifacts and style nudges excluded)
        - verified_grammar_slips_per_100_words: \(String(format: "%.1f", metrics.userWordCount > 0 ? Double(slipCount) / Double(metrics.userWordCount) * 100 : 0)) \
        (same slips normalized by words spoken — fairer to long turns. \
        Rough control bands: <1 C1+, 1-2 B2, 2-4 B1, 4-7 A2, 7+ A1)
        - per_talk_ai_reads: \(talkReads.isEmpty ? "(none)" : talkReads.joined(separator: ", "))
        """

        let response: GeminiPayload = try await GeminiClient.shared.sendJSON(
            system: systemPrompt(targetLanguage: targetLanguage,
                                  previousSummary: lastReport?.summary),
            messages: [.init(role: .user, content: userPrompt(
                priorCorpusLines: priorUserUtterances,
                windowTranscripts: windowUserUtterances,
                suggestionPairs: suggestionPairs,
                deliveryEvidence: deliveryEvidence
            ))],
            maxTokens: 2048,
            purpose: "weekly"
        )

        // First-session date in window = periodStart
        let starts = windowSessions.compactMap { $0.endedAt }.sorted()
        let periodStart = starts.first ?? now
        let periodEnd = starts.last ?? now

        return WeeklyReport(
            id: UUID(),
            periodStart: periodStart,
            periodEnd: periodEnd,
            sessionCount: windowSessions.count,
            targetLanguage: targetLanguage,
            newExpressions: response.newExpressions.map {
                LearnedExpression(phrase: $0.phrase, sampleSentence: $0.sampleSentence)
            },
            repeatedMistakes: response.repeatedMistakes.map {
                RepeatedMistake(userSaid: $0.userSaid,
                                fluentAlternative: $0.fluentAlternative,
                                count: $0.count,
                                note: $0.note)
            },
            suggestedExpressions: response.suggestedExpressions.map {
                SuggestedExpression(phrase: $0.phrase,
                                    whenToUse: $0.whenToUse,
                                    example: $0.example)
            },
            summary: response.summary,
            cefrLevel: CEFRLevel(rawValue: response.cefr_level?.lowercased() ?? "")?.rawValue,
            levelRationale: response.level_rationale,
            levelEvidence: deliveryEvidence,
            generatedAt: now
        )
    }

    // MARK: - Prompt

    private static func systemPrompt(targetLanguage: String, previousSummary: String?) -> String {
        var s = """
        You analyze a learner's spoken \(LanguageCatalog.englishName(targetLanguage)) practice across many \
        conversation sessions and produce a single concise report.

        Output strict JSON matching this shape:
        {
          "summary": "1-2 sentences on the trend vs. last report (or this period in general if no prior).",
          "cefr_level": "a1|a2|b1|b2|c1|c2",
          "level_rationale": "2-3 sentences justifying cefr_level by CITING the evidence numbers",
          "newExpressions": [
            { "phrase": "...", "sampleSentence": "the user's own sentence containing the phrase" }
          ],
          "repeatedMistakes": [
            { "userSaid": "...", "fluentAlternative": "...", "count": 2, "note": "one sentence on what to focus on" }
          ],
          "suggestedExpressions": [
            { "phrase": "...", "whenToUse": "short context cue", "example": "example sentence using it" }
          ]
        }

        Hard rules:
        - cefr_level: ONE holistic CEFR estimate of the user's SPEAKING from
          ALL of this window's utterances pooled together — a much larger
          sample than one conversation, so commit to your best read. Anchor
          on the standard CEFR speaking can-do descriptors — range and
          precision of vocabulary, grammatical control across the errors you
          see, how far ideas get developed — AND on the objective vocab
          profile you receive (words they actually produced, graded against
          the CEFR word list). Judge ONLY from this evidence: no prior about
          what learners "usually" are, no anchoring on any self-reported
          level. Lowercase.
          Weigh the MEASURED DELIVERY block as hard evidence:
          * Fluency is INVISIBLE in a transcript — take it from
            articulation_rate_wpm and its band table, never from text alone.
          * The transcripts are speech-to-text output: recognition noise is
            NOT the learner's error. Judge grammatical control from
            verified_grammar_slips_per_10_turns (transcript-verified real
            errors), not from how clean the raw text looks.
          * The suggestion pairs include STYLISTIC "more natural" rephrasings,
            not only errors — never read the pair count as error density.
          * per_talk_ai_reads are independent holistic reads of each single
            conversation; without strong contrary evidence your pooled level
            should land within one band of their median, and the pooled
            sample being LARGER usually supports the higher end the evidence
            allows, not the cautious floor.
          * The overall level is the profile's CENTER OF GRAVITY across the
            four dimensions — NOT the minimum. Per the official descriptors,
            grammatical accuracy caps the overall only to the degree errors
            IMPAIR COMMUNICATION: frequent slips whose meaning stays clear
            are compatible with B2 ("does not make errors which cause
            misunderstanding"); accuracy caps at B1 only when errors
            regularly obscure what the speaker means. An uneven profile
            (e.g. C1 pace, B2 vocabulary, B1 accuracy) therefore reads B2
            overall unless the transcripts show meaning actually breaking
            down. State in level_rationale whether the errors you saw
            obscure meaning or not — that judgment decides the boundary.
        - level_rationale: 2-3 plain sentences the learner will read,
          justifying cefr_level by NAMING the concrete evidence — the pace
          number and its band, the slip density, the per-talk reads, the
          vocab profile — and, when the level sits below some evidence band,
          saying exactly WHICH evidence held it down. Never vague ("overall
          performance suggests…"); always cite numbers you were given.
        - newExpressions: ONLY include 2+ word collocations / idioms / phrasal verbs the user used in THIS window's transcripts that do NOT appear in the prior corpus. Skip single words. Skip filler.
        - repeatedMistakes: ONLY include patterns where the same fluent alternative shows up 2+ times in this window's suggestion pairs (you'll receive the pairs). Don't invent mistakes.
        - suggestedExpressions: Phrases the user did NOT produce but would fit topics they discussed. Each must be naturally usable; no textbook phrases like "the early bird catches the worm" unless the topic genuinely called for it.
        - Cap each array at 5 items. Quality over quantity.
        - "summary" must be honest: if nothing notable changed, say so.
        - Reply with JSON only. No prose around it.
        """
        if let prev = previousSummary {
            s += "\n\nPrevious report summary (for trend comparison):\n\(prev)"
        }
        return s
    }

    private static func userPrompt(
        priorCorpusLines: [String],
        windowTranscripts: [String],
        suggestionPairs: [(said: String, alt: String)],
        deliveryEvidence: String
    ) -> String {
        let prior = priorCorpusLines.isEmpty ? "(none — first report)" :
            priorCorpusLines.prefix(500).joined(separator: "\n")
        let window = windowTranscripts.prefix(500).joined(separator: "\n")
        let pairs = suggestionPairs.isEmpty ? "(none)" :
            suggestionPairs.prefix(100).map { "- user said: \"\($0.said)\"\n  fluent: \"\($0.alt)\"" }.joined(separator: "\n")
        return """
        # PRIOR CORPUS (user utterances from earlier sessions, before this window)
        \(prior)

        # THIS WINDOW (user utterances during the period being analyzed)
        \(window)

        # OBJECTIVE VOCAB PROFILE (distinct words in this window, graded against the CEFR word list — measured, not opinion)
        \(vocabProfileLine(windowTranscripts))

        # MEASURED DELIVERY (deterministic, from the live mic + verified analysis — NOT visible in the text above)
        \(deliveryEvidence)

        # SUGGESTION PAIRS THIS WINDOW (the avatar's fluent rephrasings — includes purely stylistic upgrades, not only errors)
        \(pairs)
        """
    }

    /// Deterministic CEFR distribution of the window's distinct words —
    /// hard evidence for the pooled cefr_level judgment.
    static func vocabProfileLine(_ utterances: [String]) -> String {
        var counts: [CEFRLevel: Int] = [:]
        var seen = Set<String>()
        for line in utterances {
            for token in line.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                where !token.isEmpty && !seen.contains(token) {
                seen.insert(token)
                if let lv = CoreVocabulary.level(ofSurface: token) {
                    counts[lv, default: 0] += 1
                }
            }
        }
        return CEFRLevel.allCases
            .map { "\($0.rawValue.uppercased()): \(counts[$0] ?? 0)" }
            .joined(separator: ", ")
    }

    // MARK: - Internal decode shapes

    private struct GeminiPayload: Decodable {
        struct NewExpr: Decodable { let phrase: String; let sampleSentence: String }
        struct Mistake: Decodable { let userSaid: String; let fluentAlternative: String; let count: Int; let note: String }
        struct Suggested: Decodable { let phrase: String; let whenToUse: String; let example: String }
        let summary: String
        let cefr_level: String?
        let level_rationale: String?
        let newExpressions: [NewExpr]
        let repeatedMistakes: [Mistake]
        let suggestedExpressions: [Suggested]
    }
}

enum WeeklyReportError: Error, LocalizedError {
    case noSessions
    var errorDescription: String? {
        switch self {
        case .noSessions: return "No new sessions to analyze."
        }
    }
}
