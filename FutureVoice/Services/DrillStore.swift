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

    /// Remove every card sourced from a session — for deleting the talk
    /// itself. Re-analysis must NOT use this: it wipes Leitner progress —
    /// see `clearUnreviewedCards(for:)`.
    func deleteForSession(_ sessionId: UUID) {
        var all = load()
        all.removeAll { $0.sourceSessionId == sessionId }
        write(all)
    }

    /// Remove only this session's cards that carry no learner progress yet
    /// (box 0, never reviewed) — what a re-analysis clears before rebuilding.
    /// Cards the learner has studied keep their box and schedule.
    func clearUnreviewedCards(for sessionId: UUID) {
        var all = load()
        let before = all.count
        all.removeAll {
            $0.sourceSessionId == sessionId && $0.box == 0 && $0.lastReviewedAt == nil
        }
        if all.count != before { write(all) }
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
    /// "Got it" — the learner asserting they know this line. It GRADUATES the
    /// card to the top rung rather than climbing one, which is what the word
    /// and expression decks have always meant by the same bin: drop on Got it,
    /// the item is known.
    ///
    /// Climbing one rung per correct answer meant five separate "Got it"s
    /// before a card left the to-study pile, so the pile never visibly
    /// shrank and the To study / Known filter looked broken. The three delay
    /// bins are the "not yet" answers and still carry the spacing; the top
    /// rung's own 30-day interval brings a known card back once, much later.
    func markKnown(_ card: DrillCard, at now: Date = Date()) {
        var c = card
        c.timesSeen += 1
        c.timesCorrect += 1
        c.lastReviewedAt = now
        c.box = Self.maxBox
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
        // Normalized (not just lowercased) keys: a live-turn suggestion and
        // the summary's fluent_alternative for the same fix routinely differ
        // only in punctuation, which used to mint the card twice.
        var seenTargets = Set(existing.map { Self.normalizedForMatch($0.targetPhrase) })
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
            let key = Self.normalizedForMatch(target)
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
    /// correction (highest word overlap with the target). Applied at ingest for
    /// new cards AND at render for the cards already in users' stores.
    ///
    /// **Dictation does not punctuate.** The sentence split above is the happy
    /// path and stays first — when the transcript HAS sentences it gives a
    /// clean, whole one. But a live ASR turn routinely arrives as one
    /// unbroken 300-character run ("uh hey I'm doing great and we are um so my
    /// um my brother-in-law uh living in Seoul…"), which splits into exactly
    /// one sentence, and the old fallback then cut a blind 160-char PREFIX.
    /// That is how a card came to strike through the learner's opening words
    /// while correcting something they said half a minute later — the "You
    /// said" and the "Why" on the same card described different sentences,
    /// which reads as the app inventing a mistake. So the fallback now LOCATES
    /// the correction instead of guessing: `matchingWindow` below.
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
            // A single sentence can still be longer than the card — window it
            // rather than prefix-cutting, for the same reason as below.
            return best.count > maxChars ? matchingWindow(in: best, matching: target, maxChars: maxChars) : best
        }
        return matchingWindow(in: trimmed, matching: target, maxChars: maxChars)
    }

    /// The stretch of `text` the correction is actually about, for text with no
    /// sentence boundaries to cut on.
    ///
    /// Slides a word window over the text and keeps the one carrying the most
    /// of the target's vocabulary, each matched word weighted by **1 / how
    /// often it occurs in the whole text**. The weighting is what makes it work
    /// on a ramble: "we", "are" and "so" recur all through a turn and are worth
    /// almost nothing, while "enjoying" occurs once and pins the window to the
    /// place the learner actually said it. A plain count would score the
    /// opening words of the turn just as highly as the sentence being
    /// corrected.
    ///
    /// The window is then grown outward a word at a time for context — never
    /// past `maxChars`, and never mid-word — and each cut end is marked with an
    /// ellipsis so it reads as an excerpt rather than as the whole utterance.
    /// Nothing scoring below one full unique word (`minScore`) is trusted; that
    /// falls back to the old prefix cut, which is at least honest about being
    /// the start of the turn.
    static func matchingWindow(in text: String, matching target: String,
                               maxChars: Int = 160) -> String {
        let minScore = 1.0
        let words = wordRanges(in: text)
        let targetWords = Set(normalizedForMatch(target).split(separator: " ").map(String.init))
        guard !words.isEmpty, !targetWords.isEmpty else {
            return String(text.prefix(maxChars)) + "…"
        }
        var frequency: [String: Int] = [:]
        for word in words { frequency[word.normalized, default: 0] += 1 }

        // Wide enough to hold the corrected sentence plus the filler dictation
        // sprays through it, short enough that it can't span the whole turn.
        let span = max(targetWords.count + 4, 8)
        var bestScore = 0.0
        var bestRange: (lower: Int, upper: Int)?
        for start in words.indices {
            var seen = Set<String>()
            var score = 0.0
            var lower: Int?
            var upper = start
            for index in start..<min(start + span, words.count) {
                let word = words[index].normalized
                guard targetWords.contains(word), !seen.contains(word) else { continue }
                seen.insert(word)
                score += 1.0 / Double(frequency[word] ?? 1)
                if lower == nil { lower = index }
                upper = index
            }
            if let lower, score > bestScore {
                bestScore = score
                bestRange = (lower, upper)
            }
        }
        guard bestScore >= minScore, let bestRange else {
            return String(text.prefix(maxChars)) + "…"
        }

        // Context budget: enough to read as a sentence, not the whole card.
        let budget = min(maxChars, max(96, target.count + 64))
        var lower = bestRange.lower
        var upper = bestRange.upper
        var start = words[lower].range.lowerBound
        var end = words[upper].range.upperBound
        while true {
            var grew = false
            if upper + 1 < words.count,
               text.distance(from: start, to: words[upper + 1].range.upperBound) <= budget {
                upper += 1
                end = words[upper].range.upperBound
                grew = true
            }
            if lower > 0,
               text.distance(from: words[lower - 1].range.lowerBound, to: end) <= budget {
                lower -= 1
                start = words[lower].range.lowerBound
                grew = true
            }
            if !grew { break }
        }
        let fragment = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        let head = start > text.startIndex ? "…" : ""
        let tail = end < text.endIndex ? "…" : ""
        return head + fragment + tail
    }

    /// Words with where they sit in the original string, so a window can be cut
    /// on word boundaries and still carry the text's own punctuation and case.
    private static func wordRanges(in text: String) -> [(normalized: String, range: Range<String.Index>)] {
        var out: [(normalized: String, range: Range<String.Index>)] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index].isNumber else {
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex,
                  text[index].isLetter || text[index].isNumber
                    || text[index] == "'" || text[index] == "’" || text[index] == "-" {
                index = text.index(after: index)
            }
            let range = start..<index
            let normalized = normalizedForMatch(String(text[range]))
            if !normalized.isEmpty { out.append((normalized, range)) }
        }
        return out
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

    /// Whether a card with this target survives `load()`'s read-time filter.
    /// Callers that mint a card outside `ingest` must ask first: a card the
    /// store silently drops on the next read is worse than no card at all —
    /// every lookup for it misses, so every visit mints another one.
    static func isDrillable(_ targetPhrase: String) -> Bool {
        !looksLikeMetaRule(targetPhrase)
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
