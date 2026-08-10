import Foundation

/// Turning a finished talk into its review material: the summary itself, and
/// everything the app DERIVES from it — vocabulary, expressions, verified
/// grammar evidence, drill cards, carryover credit, the learner profile.
///
/// This is one place because it runs from two moments that must produce
/// IDENTICAL results:
///   • End of a live call (`ConversationView.endSession`), and
///   • "Generate it again" from the talk's book, when that first attempt
///     failed (`ConversationDetailView`).
/// The second exists because the first can fail — network, credits, a
/// truncated response — and the talk is saved BEFORE the analysis runs. A
/// session stuck at `summary == nil` isn't half a book, it's no book at all:
/// no drills, no scorecard, and nothing folded into the next conversation's
/// prompt. Until this type existed, that state was permanent.
@MainActor
enum SessionSummarizer {

    struct Result {
        let summary: SessionSummary
        /// The session as persisted — summary attached, and `topic` filled in
        /// from the generated title when the talk had no picked topic.
        let session: Session
    }

    /// Whether a saved talk still owes the learner its review material.
    /// Turn-count guard mirrors `endSession`: an empty talk has nothing to
    /// analyze and must not offer a button that can only fail.
    static func needsSummary(_ session: Session) -> Bool {
        session.summary == nil && session.turns.contains { $0.role == .user }
    }

    /// Analyze `session`, persist it with its summary, and fold the outcome
    /// into every store that learns from a talk.
    ///
    /// Throws only on the Gemini call — everything after it is local. The
    /// caller's already-saved session row is left untouched on a throw, so a
    /// failure is always retryable and never partial.
    static func summarize(session: Session, appState: AppState) async throws -> Result {
        let turns = session.turns
        let sessionId = session.id

        let systemP = ConversationEngine.summarySystemPrompt(
            targetLanguage: session.targetLanguage,
            nativeLanguage: appState.nativeLanguage,
            profile: appState.learnerProfile
        )
        let transcript = ConversationEngine.formatTranscript(turns)
        let metrics = ScorecardMetrics.compute(turns: turns)
        let userMessage = """
        transcript:
        \(transcript)

        metrics:
        \(metrics.promptJSON())
        """
        // Stable idempotency key: retrying — by re-tapping End, or from the
        // book days later — re-runs the SAME logical request without a
        // second charge, as long as the transcript hasn't grown.
        let payload: ClaudeSummaryPayload = try await GeminiClient.shared.sendJSON(
            system: systemP,
            messages: [GeminiClient.Message(role: .user, content: userMessage)],
            // The schema's worst case is big: up to 15 grammar_errors (quote +
            // correction + a NATIVE-language note each), 5 phrases_used, 3-4
            // drills, expressions, and a 6-field scorecard whose notes are
            // also native-language. On top of that gen-3 counts THINKING
            // tokens against this same ceiling. At 1400 a long B2 session ran
            // out mid-JSON and surfaced as "reply hit the token ceiling" on
            // End — the talk was already saved, but its whole review yield
            // was lost. The ceiling is not billed, only tokens actually
            // produced, so the headroom is free.
            maxTokens: 4096,
            purpose: "summary",
            idempotencyKey: "summary:\(sessionId.uuidString):\(turns.count)"
        )
        var computed = payload.toDomain()

        // Fold the user's spoken words into the long-term vocab pool; the
        // freshly-used words ride along on the summary so the wrap-up can
        // celebrate concrete progress.
        let userTexts = turns.filter { $0.role == .user }.map { $0.transcript }
        computed.newWordsUsed = VocabStore.shared.ingest(
            sessionId: sessionId, userTexts: userTexts)

        // Keep only expressions that literally appear in the user's own
        // turns — the LLM occasionally paraphrases, and we never show or
        // store an expression they didn't actually say.
        let haystack = userTexts.joined(separator: " ").lowercased()
        let verifiedExpressions = computed.expressionsUsed.filter { phrase in
            let needle = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !needle.isEmpty && haystack.contains(needle)
        }
        computed.expressionsUsed = verifiedExpressions
        VocabStore.shared.ingestExpressions(
            sessionId: sessionId, phrases: verifiedExpressions)

        // Same guard for grammar evidence: a quote the user can't find in
        // their own words destroys trust in the whole list. Compare with
        // punctuation/casing stripped — STT and the LLM disagree on those
        // even when the words match.
        func normalized(_ s: String) -> String {
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        let normalizedHaystack = normalized(haystack)
        computed.grammarIssues = computed.grammarIssues.filter {
            let needle = normalized($0.quote)
            // A "fix" that only touches punctuation/casing (normalized forms
            // identical) is a transcription nitpick, not a spoken grammar
            // error — drop it.
            return !needle.isEmpty && normalizedHaystack.contains(needle)
                && needle != normalized($0.correction)
        }

        // Did anything they'd been studying actually come out of their mouth?
        // Runs against the drill cards as they stood BEFORE this session's own
        // corrections are ingested below, so a card minted tonight can't be
        // credited as carried into tonight.
        let carryovers = CarryoverDetector.detect(
            in: turns, cards: DrillStore.shared.load(),
            curriculumItems: appState.openCurriculumItems,
            studyingExpressions: VocabStore.shared.studyingExpressions,
            studyingWords: VocabStore.shared.studying,
            sessionId: sessionId, sessionStartedAt: session.startedAt)
        computed.carryovers = carryovers

        // Free-talk sessions (no picked topic) take the summary's generated
        // title so History/Practice lists don't fill with identical
        // "Conversation" rows.
        let generatedTitle = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingTopic = session.topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTopic = existingTopic.isEmpty ? (generatedTitle ?? "") : existingTopic

        var saved = session
        saved.topic = resolvedTopic.isEmpty ? nil : resolvedTopic
        saved.summary = computed
        SessionStore.shared.save(saved)

        // Clear any cards from a previous analysis of THIS session (resume
        // re-summarizes the whole thing, and so does a regenerate) so they
        // don't pile up.
        DrillStore.shared.deleteForSession(sessionId)
        DrillStore.shared.ingest(summary: computed, turns: turns, sessionId: sessionId)
        // Producing a card's phrase live outranks any flashcard tap — credit
        // it against the SRS schedule, not just the wrap-up.
        DrillStore.shared.markUsedInConversation(
            ids: carryovers.filter { $0.source == .drillCard }.compactMap { $0.sourceId })
        // Same principle for book material: producing it live masters it,
        // wherever the book lives.
        appState.markCurriculumItemsUsedInConversation(
            itemIds: carryovers.filter { $0.source == .curriculumItem }.compactMap { $0.sourceId })
        if !carryovers.isEmpty {
            Analytics.capture("carryovers_detected", [
                "count": carryovers.count,
                "from_cards": carryovers.filter { $0.source == .drillCard }.count,
                "from_suggestions": carryovers.filter { $0.source == .suggestion }.count,
            ])
        }
        // Grow the long-term learner profile — the next conversation's system
        // prompt picks these patterns up.
        appState.recordSessionOutcome(summary: computed, turns: turns)
        // Kick off async weekly-report generation if unlock conditions are
        // met. Fires-and-forgets — UI doesn't block on Gemini.
        appState.maybeGenerateWeeklyReport()
        // Fresh cards just landed in the queue — (re)schedule the due
        // reminder. This is the one contextual moment where asking for
        // notification permission makes sense.
        Task { await DrillReminder.reschedule(allowPermissionPrompt: true) }
        // Write tomorrow's call NOW, off the talk that just ended.
        //
        // Not in the morning: iOS won't reliably run background work at a
        // chosen hour, and a call that fails to generate is a call that never
        // rings. Here the app is foreground, the network is up, and the
        // context is as fresh as it will ever be — this session's own topic
        // and phrases. By 8am the script and its audio are already on disk,
        // so the ring works offline and cannot fail.
        appState.refreshDailyCall(force: true)

        return Result(summary: computed, session: saved)
    }
}
