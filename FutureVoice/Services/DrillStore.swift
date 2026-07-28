import Foundation

/// Local persistence + Leitner spaced-repetition scheduling for `DrillCard`s.
/// Mirrors `SessionStore`'s on-disk JSON pattern. Phase 2 will move this
/// (alongside sessions and learner profile) into Supabase.
final class DrillStore {
    static let shared = DrillStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "drills.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent(filename)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - CRUD

    func load() -> [DrillCard] {
        guard let data = try? Data(contentsOf: fileURL),
              let cards = try? decoder.decode([DrillCard].self, from: data) else {
            return []
        }
        // Filter out historical meta-rule cards generated before the
        // tighter summary prompt + ingestion safety net landed. Read-time
        // filter only — we don't rewrite the JSON, so this is a no-op once
        // the bad rows roll off naturally.
        return cards.filter { !Self.looksLikeMetaRule($0.targetPhrase) }
    }

    func save(_ card: DrillCard) {
        var all = load()
        all.removeAll { $0.id == card.id }
        all.append(card)
        write(all)
    }

    func upsertMany(_ cards: [DrillCard]) {
        guard !cards.isEmpty else { return }
        var all = load()
        let newIds = Set(cards.map { $0.id })
        all.removeAll { newIds.contains($0.id) }
        all.append(contentsOf: cards)
        write(all)
    }

    func delete(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        write(all)
    }

    /// Remove every card sourced from a session — used before re-ingesting a
    /// resumed conversation so its cards don't duplicate.
    func deleteForSession(_ sessionId: UUID) {
        var all = load()
        all.removeAll { $0.sourceSessionId == sessionId }
        write(all)
    }

    /// Remove every card minted from one turn — used when the user flags the
    /// turn as misheard by speech-to-text (its corrections drill a sentence
    /// the user never said).
    func deleteForTurn(_ turnId: UUID) {
        var all = load()
        all.removeAll { $0.sourceTurnId == turnId }
        write(all)
    }

    // MARK: - Scheduling

    /// Cards whose `nextReviewAt` is in the past or present, **newest first**.
    /// Recently captured patterns feel fresher and more relevant to the user
    /// than 3-week-old ones from a forgotten session — surfacing those first
    /// keeps the drill connected to whatever they just practiced.
    func due(now: Date = Date()) -> [DrillCard] {
        load()
            .filter { $0.nextReviewAt <= now }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func dueCount(now: Date = Date()) -> Int {
        load().reduce(into: 0) { count, card in
            if card.nextReviewAt <= now { count += 1 }
        }
    }

    /// Promote the card one Leitner box and reschedule.
    func markCorrect(_ card: DrillCard, at now: Date = Date()) {
        var c = card
        c.timesSeen += 1
        c.timesCorrect += 1
        c.lastReviewedAt = now
        c.box = min(c.box + 1, Self.maxBox)
        c.nextReviewAt = now.addingTimeInterval(Self.interval(for: c.box))
        save(c)
    }

    /// Demote and reschedule for soon.
    func markIncorrect(_ card: DrillCard, at now: Date = Date()) {
        var c = card
        c.timesSeen += 1
        c.lastReviewedAt = now
        c.box = max(c.box - 1, 0)
        c.nextReviewAt = now.addingTimeInterval(Self.interval(for: c.box))
        save(c)
    }

    // MARK: - Ingest

    /// Create new drill cards from a freshly-saved session — per-turn suggestions,
    /// the summary's phrase feedback, detected patterns, and explicit drill prompts.
    /// Deduplicates on `targetPhrase` (case-insensitive) against existing cards
    /// so the queue doesn't fill with repeats of the same correction.
    @discardableResult
    func ingest(summary: SessionSummary, turns: [Turn], sessionId: UUID, now: Date = Date()) -> Int {
        let existing = load()
        var seenTargets = Set(existing.map { $0.targetPhrase.lowercased() })
        var newCards: [DrillCard] = []

        // Summary-derived cards quote the user loosely — trace the quote back
        // to the turn it came from so the card can play the user's own audio.
        // Normalized containment (not equality): Gemini's `userSaid` is usually
        // a fragment of the full turn transcript.
        let userTurns = turns.filter { $0.role == .user }
        func sourceTurnId(for phrase: String) -> UUID? {
            let needle = Self.normalizedForMatch(phrase)
            guard !needle.isEmpty else { return nil }
            return userTurns.first { Self.normalizedForMatch($0.transcript).contains(needle) }?.id
        }

        func add(source: String, target: String, reason: String, turnId: UUID? = nil) {
            let key = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seenTargets.contains(key) else { return }
            // Safety net: even with the tightened summary prompt, Gemini
            // occasionally produces meta-rule "phrases" like "using articles
            // correctly". Those tank the drill UX — TTS on a rule is gibberish.
            guard !Self.looksLikeMetaRule(target) else { return }
            seenTargets.insert(key)
            newCards.append(DrillCard(
                sourcePhrase: source,
                targetPhrase: target,
                reason: reason,
                createdAt: now,
                nextReviewAt: now,
                box: 0,
                sourceSessionId: sessionId,
                sourceTurnId: turnId
            ))
        }

        for turn in turns where turn.role == .user {
            if let s = turn.suggestion {
                add(source: turn.transcript, target: s.alternative, reason: s.reason, turnId: turn.id)
            }
        }
        for p in summary.phrasesUsed {
            add(source: p.userSaid, target: p.fluentAlternative, reason: p.reason,
                turnId: sourceTurnId(for: p.userSaid))
        }
        for p in summary.newPatternsDetected {
            add(source: p.mistake, target: p.correction, reason: p.context,
                turnId: sourceTurnId(for: p.mistake))
        }
        for d in summary.suggestedDrills {
            add(source: "", target: d, reason: "Suggested for you to practice.")
        }

        upsertMany(newCards)
        return newCards.count
    }

    // MARK: - Internals

    private static let maxBox = 5

    /// Leitner intervals (in seconds) per box. Box 0 stays due immediately so
    /// new cards surface in the next session.
    private static func interval(for box: Int) -> TimeInterval {
        let days: TimeInterval
        switch box {
        case 0: days = 0
        case 1: days = 1
        case 2: days = 3
        case 3: days = 7
        case 4: days = 14
        default: days = 30
        }
        return days * 24 * 60 * 60
    }

    private func write(_ cards: [DrillCard]) {
        guard let data = try? encoder.encode(cards) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        // Every mutation funnels through here — keep the home-screen widget's
        // snapshot of the due queue in sync.
        StudyWidgetRefresher.schedule()
    }

    /// Lowercased, punctuation stripped, whitespace collapsed — so a summary
    /// quote like "I go to store yesterday." still matches the raw transcript
    /// "i go to store yesterday" despite casing/punctuation drift.
    private static func normalizedForMatch(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let stripped = String(text.unicodeScalars.filter { allowed.contains($0) })
        return stripped
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Heuristic for "this is a rule, not an utterance". Matches the kinds
    /// of meta-rule strings Gemini occasionally produces despite the prompt
    /// telling it not to. Conservative — false-positives just mean a few
    /// missed drill cards, which is fine. False-negatives are what hurt
    /// (TTS reading "using articles correctly" out loud).
    private static func looksLikeMetaRule(_ phrase: String) -> Bool {
        let lower = phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty { return true }

        // Sentence-fragments that point at grammar concepts rather than
        // anything you'd actually say in a conversation.
        let bannedSubstrings = [
            "correctly",            // "using X correctly"
            "properly",
            "appropriately",
            "subject-verb",
            "agreement",
            "tense",
            "article",              // "missing article", "use the article"
            "preposition",          // "missing preposition"
            "vocabulary",
            "register",
            "grammar",
            "pronunciation",
            "fluency",
            "expand your",
            "instead of using",
            "remember to",
            "make sure to",
            "try to use",
            "you should use",
        ]
        for needle in bannedSubstrings where lower.contains(needle) {
            return true
        }

        // Anything that's mostly quoted single-letter / single-word items
        // strung with commas is a rule listing examples, not an utterance.
        // E.g. "using 'a', 'the', 'in', 'on'".
        let quotedItems = lower.components(separatedBy: "'").count - 1
        if quotedItems >= 4 { return true }

        return false
    }
}
