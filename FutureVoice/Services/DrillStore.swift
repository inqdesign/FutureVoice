import Foundation

/// Local persistence + Leitner spaced-repetition scheduling for `DrillCard`s.
/// Mirrors `SessionStore`'s on-disk JSON pattern. Phase 2 will move this
/// (alongside sessions and learner profile) into Supabase.
final class DrillStore: LanguageScopedStore {
    static let shared = DrillStore()

    private var fileURL: URL
    private let filename: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "drills.json") {
        self.filename = filename
        self.fileURL = LanguageScope.activeDirectory.appendingPathComponent(filename)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    func languageScopeDidChange() {
        fileURL = LanguageScope.activeDirectory.appendingPathComponent(filename)
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
        // Also trim multi-sentence targets down to their core sentence —
        // cards ingested before the one-sentence prompt rule carry whole-turn
        // rewrites. Read-time so the backlog is fixed everywhere at once
        // (card UI, TTS, shadow, widget) without a disk migration.
        return cards
            .filter { !Self.looksLikeMetaRule($0.targetPhrase) }
            .map { card in
                var c = card
                c.targetPhrase = Self.coreSentence(of: c.targetPhrase,
                                                   pairedWith: c.sourcePhrase)
                return c
            }
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
        Analytics.capture("drill_reviewed", ["correct": true, "box": c.box])
    }

    /// Demote and reschedule for soon.
    func markIncorrect(_ card: DrillCard, at now: Date = Date()) {
        var c = card
        c.timesSeen += 1
        c.lastReviewedAt = now
        c.box = max(c.box - 1, 0)
        c.nextReviewAt = now.addingTimeInterval(Self.interval(for: c.box))
        save(c)
        Analytics.capture("drill_reviewed", ["correct": false, "box": c.box])
    }

    /// The learner picked WHEN to meet this card again (the drill deck's bin
    /// tray) instead of letting the ladder decide.
    ///
    /// The chosen delay also sets the box — 10 min ≈ box 0, tomorrow ≈ box 1,
    /// three days ≈ box 2 — so the manual pick doesn't strand the card off the
    /// ladder: from the NEXT review on, normal Leitner promotion resumes from
    /// wherever the learner parked it. Never counted as correct; asking to see
    /// a card again is the opposite of recalling it.
    func snooze(_ card: DrillCard, box: Int, until date: Date, at now: Date = Date()) {
        var c = card
        c.timesSeen += 1
        c.lastReviewedAt = now
        c.box = min(max(box, 0), Self.maxBox)
        c.nextReviewAt = date
        save(c)
        Analytics.capture("drill_snoozed", [
            "box": c.box,
            "delay_min": Int(date.timeIntervalSince(now) / 60)
        ])
    }

    /// Credit cards the learner produced unprompted in a real conversation
    /// (`CarryoverDetector`). Saying it live, with no card on screen, is
    /// stronger evidence of retention than any flashcard tap — so it jumps two
    /// boxes and lands no lower than box 3 instead of stepping one at a time.
    /// Cards already past that keep their schedule.
    func markUsedInConversation(ids: [UUID], at now: Date = Date()) {
        guard !ids.isEmpty else { return }
        let wanted = Set(ids)
        var all = load()
        var touched = false
        for index in all.indices where wanted.contains(all[index].id) {
            let promoted = min(max(all[index].box + 2, 3), Self.maxBox)
            guard promoted > all[index].box else { continue }
            all[index].box = promoted
            all[index].lastReviewedAt = now
            all[index].nextReviewAt = now.addingTimeInterval(Self.interval(for: promoted))
            touched = true
            Analytics.capture("drill_used_in_conversation", ["box": promoted])
        }
        if touched { write(all) }
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
            // Safety net mirroring the read-time trim: never persist a
            // multi-sentence whole-turn rewrite as a drill target.
            let target = Self.coreSentence(of: target, pairedWith: source)
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
                // Quote only the sentence the suggestion rewrites, never the
                // whole (possibly minute-long) turn transcript.
                add(source: Self.relevantFragment(of: turn.transcript, matching: s.alternative),
                    target: s.alternative, reason: s.reason, turnId: turn.id)
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

    /// Top Leitner rung — box-5 cards are "learned" (30-day interval). The
    /// drill deck's folder chips read this to bucket graduated cards.
    static let maxBox = 5

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
    /// A user turn can be a minute-long ramble while the suggestion rewrites
    /// ONE sentence of it — quoting the whole transcript blew the drill card
    /// off the screen. Keep the sentence that actually corresponds to the
    /// correction (highest word overlap with the target); fall back to a hard
    /// prefix cut when there's nothing to match against. Applied at ingest for
    /// new cards AND at render for the cards already in users' stores.
    static func relevantFragment(of source: String, matching target: String,
                                 maxChars: Int = 160) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let sentences = trimmed
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let targetWords = Set(normalizedForMatch(target).split(separator: " "))
        if sentences.count > 1, !targetWords.isEmpty,
           let best = sentences.max(by: { overlap($0, targetWords) < overlap($1, targetWords) }),
           overlap(best, targetWords) > 0 {
            return best.count > maxChars ? best.prefix(maxChars) + "…" : best
        }
        return trimmed.prefix(maxChars) + "…"
    }

    /// Target-side twin of `relevantFragment`. Gemini sometimes rewrites a
    /// user's WHOLE multi-sentence turn as the "fluent alternative" — a
    /// paragraph is un-drillable (unreadable card, minute-long TTS, hopeless
    /// shadow). Keep the ONE sentence that corresponds to the correction:
    /// the corrected sentence shares most of its words with what the user
    /// actually said, so highest overlap with the source wins. Unlike the
    /// source fragment this is never ellipsis-cut — the result gets spoken
    /// by TTS and shadowed, so it must stay a complete utterance.
    static func coreSentence(of target: String, pairedWith source: String,
                             maxChars: Int = 140) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let sentences = trimmed
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let sourceWords = Set(normalizedForMatch(source).split(separator: " "))
        guard sentences.count > 1, !sourceWords.isEmpty,
              let best = sentences.max(by: { overlap($0, sourceWords) < overlap($1, sourceWords) }),
              overlap(best, sourceWords) > 0 else { return trimmed }
        // Splitting ate the terminal punctuation — restore it so TTS keeps
        // the sentence's intonation (a dropped "?" flattens a question).
        if let range = trimmed.range(of: best), range.upperBound < trimmed.endIndex,
           ".!?".contains(trimmed[range.upperBound]) {
            return best + String(trimmed[range.upperBound])
        }
        return best
    }

    private static func overlap(_ sentence: String, _ targetWords: Set<Substring>) -> Int {
        Set(normalizedForMatch(sentence).split(separator: " ")).intersection(targetWords).count
    }

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
