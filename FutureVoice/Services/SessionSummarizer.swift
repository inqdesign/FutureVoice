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

    /// What the wrap-up screen is allowed to say it is doing.
    ///
    /// Every field is a REAL count, reported at the point in `summarize` where
    /// that work actually finished — a wrap-up that narrates steps it isn't
    /// taking is worse than a spinner, because the next one is disbelieved
    /// too. `nil` means "not done yet"; the numbers below are the same ones
    /// the summary sheet then shows.
    ///
    /// The shape is a growing struct rather than a stream of events so a view
    /// can render it with no state of its own, and a caller that ignores it
    /// costs nothing.
    struct Progress: Equatable {
        // ── While the model is writing. The summary is ONE call that takes
        // most of the wait, and it writes its sections in a fixed order, so
        // the section it has finished is a real, observable fact — see
        // `absorb(partial:)`. Without these the board sat on step one and
        // then completed all at once, which is a spinner with extra steps.
        /// The transcript has been read and titled.
        var readBack = false
        /// `phrases_used` — the lines worth saying differently.
        var wroteCorrections = false
        /// `suggested_drills` — the review cards.
        var wroteDrills = false
        /// `expressions_used`.
        var wroteExpressions = false
        /// `grammar_errors`.
        var wroteGrammar = false

        // ── Final counts, once the local pass has verified everything. Each
        // is the number the summary sheet then shows.
        /// Corrected lines the talk produced.
        var phrases: Int?
        /// Words + expressions the learner used that are new to their pool.
        var words: Int?
        /// Expressions the fluent self used that the learner can take.
        var offered: Int?
        /// Corrections that survived the "they really said this" check.
        var corrections: Int?
        /// Things they'd been studying that came out unprompted.
        var carryovers: Int?
        /// Review cards minted from this talk.
        var cards: Int?
        /// Everything above is final.
        var finished = false

        /// Read the model's half-written JSON for which sections are DONE.
        ///
        /// A section is finished when the key AFTER it has appeared — the
        /// cheapest check that can't be fooled by a value still being written,
        /// and it needs no incremental JSON parsing. Key order is the schema's
        /// order in `ConversationEngine.summarySystemPrompt`; if that order
        /// changes, this reports the wrong step (never a wrong NUMBER — every
        /// count below still comes from the finished payload).
        mutating func absorb(partial: String) {
            guard !partial.isEmpty else { return }
            readBack = readBack || partial.contains("\"phrases_used\"")
            wroteCorrections = wroteCorrections || partial.contains("\"new_patterns_detected\"")
            wroteDrills = wroteDrills || partial.contains("\"expressions_used\"")
            wroteExpressions = wroteExpressions || partial.contains("\"weak_vocab_areas\"")
            wroteGrammar = wroteGrammar || partial.contains("\"overall_note\"")
        }
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
    static func summarize(session: Session, appState: AppState,
                          onProgress: ((Progress) -> Void)? = nil) async throws -> Result {
        let turns = session.turns
        let sessionId = session.id
        var progress = Progress()
        func report(_ edit: (inout Progress) -> Void) {
            edit(&progress)
            onProgress?(progress)
        }

        let systemP = ConversationEngine.summarySystemPrompt(
            targetLanguage: session.targetLanguage,
            nativeLanguage: appState.nativeLanguage,
            profile: appState.learnerProfile,
            knownAboutUser: appState.persona?.knownFacts ?? [],
            // What a talk is allowed to yield follows how much was said in it.
            expressionBudget: ConversationEngine.expressionBudget(
                fluentTurns: turns.filter { $0.role == .fluentSelf }.count)
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
        // STREAMED, unlike the other analysis calls (see CLAUDE.md), and not
        // for latency: nothing here can be used before the payload closes, and
        // `sendJSONStreamAccumulating` still returns the fully decoded object,
        // so the result is byte-for-byte what the buffered call produced. What
        // the stream buys is the only honest way to move the wrap-up screen
        // while the model writes — a call that takes most of the wait and
        // reports nothing leaves the board on step one until everything
        // finishes at once. A deploy without SSE degrades to buffering, and
        // then `onPartial` simply never fires.
        func request() async throws -> ClaudeSummaryPayload {
            try await GeminiClient.shared.sendJSONStreamAccumulating(
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
                // 4096 until 2026-08-19: the expression budget now scales with
                // the talk (up to 14 per side), and the failures that were
                // showing up on the long talks this ceiling has to cover —
                // 9, 11, 25 and 31 turns, all NSCocoaErrorDomain 4864, a JSON
                // the decoder couldn't read — are what running out of room
                // mid-object looks like when the model stops short of the
                // MAX_TOKENS flag. Free headroom, so take it.
                maxTokens: 8192,
                purpose: "summary",
                idempotencyKey: "summary:\(sessionId.uuidString):\(turns.count)",
                onPartial: { partial in report { $0.absorb(partial: partial) } }
            )
        }

        let payload: ClaudeSummaryPayload
        do {
            payload = try await request()
        } catch let error where error.isMalformedModelOutput {
            // The learner did nothing wrong and has nothing to fix — the model
            // wrote a shape we couldn't read. Ask once more before making the
            // end of a talk look like a failure. Free: `record_free_usage`
            // dedupes on the idempotency key, so the second attempt neither
            // charges nor spends a slot of the daily cap, and the wait is one
            // request on a screen that is already showing a wrap-up.
            Telemetry.log("talk_summary_retry", [
                "detail": error.decodeDetail ?? "unknown",
                "turns": String(turns.count),
            ])
            payload = try await request()
        }
        var computed = payload.toDomain()
        report { $0.phrases = computed.phrasesUsed.count }

        // Fold the user's spoken words into the long-term vocab pool; the
        // freshly-used words ride along on the summary so the wrap-up can
        // celebrate concrete progress. The pool accepts each text once, so
        // when a RESUMED talk is summarized again the fresh batch covers only
        // the new turns — merge with the previous summary's list instead of
        // overwriting it, or every resume erased "words you used first".
        let userTexts = turns.filter { $0.role == .user }.map { $0.transcript }
        let freshWords = VocabStore.shared.ingest(
            sessionId: sessionId, userTexts: userTexts)
        let priorWords = session.summary?.newWordsUsed ?? []
        computed.newWordsUsed = priorWords + freshWords.filter { !priorWords.contains($0) }

        // Keep only expressions that literally appear in the user's own
        // turns — the LLM occasionally paraphrases, and we never show or
        // store an expression they didn't actually say.
        //
        // Compared with punctuation and casing stripped, the SAME way the
        // grammar quotes below are checked. A raw substring match silently
        // dropped good expressions over a comma, an apostrophe form or a
        // capital letter, which is why a talk full of usable phrases could
        // end up with one odd survivor.
        let haystack = CarryoverDetector.normalized(userTexts.joined(separator: " "))
        let verifiedExpressions = computed.expressionsUsed.filter { phrase in
            let needle = CarryoverDetector.normalized(phrase)
            return !needle.isEmpty && haystack.contains(needle)
        }
        #if DEBUG
        let dropped = computed.expressionsUsed.count - verifiedExpressions.count
        if dropped > 0 {
            NSLog("EXPRCAPTURE dropped %d of %d as not-verbatim", dropped, computed.expressionsUsed.count)
        }
        #endif
        computed.expressionsUsed = verifiedExpressions
        report { $0.words = freshWords.count + verifiedExpressions.count }
        // A pre-per-key-tracking session being re-analyzed: what it already
        // counted is its previous summary's list — seed the store so those
        // don't count twice (no-op when per-key data exists).
        VocabStore.shared.notePriorExpressions(
            sessionId: sessionId, phrases: session.summary?.expressionsUsed ?? [])
        VocabStore.shared.ingestExpressions(
            sessionId: sessionId, phrases: verifiedExpressions)

        // The other direction: phrases the FLUENT SELF used. Same verbatim
        // guard against ITS turns, and cheaper to satisfy — that text is
        // model-written, so there is no transcriber between the phrase and
        // the check. Anything the learner already produced is dropped: it is
        // evidence, and it is in the list above.
        //
        // A resumed talk re-summarizes from turn one, so the previous take's
        // phrases are merged rather than replaced — the same rule
        // `newWordsUsed` follows, for the same reason.
        let fluentHaystack = CarryoverDetector.normalized(
            turns.filter { $0.role == .fluentSelf }.map(\.transcript).joined(separator: " "))
        let alreadyMine = Set(verifiedExpressions.map(CarryoverDetector.normalized))
        var seenOffered = Set<String>()
        let verifiedOffered = computed.expressionsOffered.filter { phrase in
            let needle = CarryoverDetector.normalized(phrase)
            guard !needle.isEmpty, !alreadyMine.contains(needle),
                  !haystack.contains(needle),          // they said it too — not new material
                  fluentHaystack.contains(needle) else { return false }
            return seenOffered.insert(needle).inserted
        }
        let priorOffered = session.summary?.expressionsOffered ?? []
        computed.expressionsOffered = priorOffered + verifiedOffered.filter {
            !priorOffered.contains($0)
        }
        report { $0.offered = computed.expressionsOffered.count }

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
        report { $0.corrections = computed.grammarIssues.count }

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
        report { $0.carryovers = carryovers.count }

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

        // Clear cards from a previous analysis of THIS session (resume
        // re-summarizes the whole thing, and so does a regenerate) so they
        // don't pile up — but ONLY the untouched ones. A card the learner
        // has already reviewed carries Leitner progress a re-analysis must
        // not reset; ingest's dedupe skips re-minting the survivors.
        DrillStore.shared.clearUnreviewedCards(for: sessionId)
        let mintedCards = DrillStore.shared.ingest(summary: computed, turns: turns,
                                                   sessionId: sessionId)
        report { $0.cards = mintedCards }
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
        // The other memory: what the talk taught the fluent self about the
        // PERSON. A learner tells their future self about their job once, out
        // loud, and expects it to be known next week — so it's written into
        // the same profile they fill in by hand and read back through
        // `personaBlock`. Capped at 3 a session: this is a notebook, not a
        // transcript, and the model volunteers more than it should when a talk
        // ran long.
        let learned = payload.about_user
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 140 }
            .prefix(3)
            .map { PersonaNote(text: $0, sessionId: sessionId, learnedAt: Date()) }
        // A plain free talk is where the fluent self gets to know someone —
        // a scenario casts it as a barista and a Find-people call as a
        // stranger, and neither of those met the learner. Stamping this is
        // what retires the first-call framing.
        let wasIntroTalk = session.counterpartId == nil && existingTopic.isEmpty
        if !learned.isEmpty || (wasIntroTalk && appState.persona?.metAt == nil) {
            appState.rememberAboutUser(
                Array(learned),
                metAt: wasIntroTalk ? (session.endedAt ?? Date()) : nil)
        }
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

        report { $0.finished = true }
        return Result(summary: computed, session: saved)
    }
}
