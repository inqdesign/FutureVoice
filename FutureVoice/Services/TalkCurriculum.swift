import Foundation

/// The review material of ONE finished talk — the same anatomy as a Watch
/// book's `ScenarioCurriculum` (words to master + lines to shadow), but
/// DERIVED on demand, never persisted:
///
///   - words        → the fluent self's pickup words (words they used that
///                    the learner hasn't) — mastered through `VocabStore`
///                    exactly like a scenario word
///   - shadow lines → the corrected versions of the learner's own sentences
///                    (`Turn.suggestion`) — mastered by a shadow attempt
///                    scoring ≥ `ScenarioCurriculum.shadowMasteryScore`, or by
///                    the correction's drill card reaching the top Leitner box
///                    (the book page studies corrections as CARDS, so the
///                    card's "Got it" has to be able to finish the book)
///
/// Deriving (instead of storing) keeps a single source of truth: mastery
/// state lives in `VocabStore` / `ShadowAttemptStore`, and old sessions get
/// a curriculum retroactively with zero migration. Only the archived flag is
/// persisted (on `Session.archivedAt`).
@MainActor
enum TalkCurriculum {

    /// A computed curriculum snapshot. Mirrors `ScenarioCurriculum`'s counts
    /// so book cards can render either interchangeably.
    struct Snapshot {
        var words: [ScenarioCurriculum.Item] = []
        var shadowLines: [ScenarioCurriculum.Item] = []

        var totalCount: Int { words.count + shadowLines.count }
        var masteredCount: Int {
            (words + shadowLines).filter { $0.masteredAt != nil }.count
        }
        var progress: Double {
            totalCount == 0 ? 0 : Double(masteredCount) / Double(totalCount)
        }
        var isMastered: Bool { totalCount > 0 && masteredCount == totalCount }
        /// Most recent mastery event — when this book was last studied.
        var lastStudiedAt: Date? {
            (words + shadowLines).compactMap(\.masteredAt).max()
        }
    }

    /// How many pickup words one talk's book keeps — matches the cap the old
    /// detail page used for its chips.
    static let maxWords = 24

    /// How many fluent-self lines a talk offers for shadowing.
    nonisolated static let maxShadowLines = 4

    /// The fluent-self lines worth shadowing, in conversation order.
    ///
    /// Was "the last 4 lines of the call", which made the goodbye the study
    /// material and threw away the middle of every long talk. Each candidate
    /// (4–28 words: below is a greeting, above is unshadowable) is scored by
    /// what it can teach — core-list lemmas at or above the learner's level
    /// count double, other core lemmas once — and ties keep conversation
    /// order. A talk with nothing scoreable falls back to its last lines so
    /// the chapter never goes empty.
    nonisolated static func shadowPicks(session: Session,
                                        proficiency: CEFRLevel) -> [Turn] {
        let candidates = session.turns.filter {
            $0.role == .fluentSelf
                && (4...28).contains($0.transcript.split(separator: " ").count)
        }
        let minRank = CoreVocabulary.levelRank(proficiency)
        func teachScore(_ turn: Turn) -> Int {
            var total = 0
            for lemma in VocabStore.lemmas(in: [turn.transcript]) {
                guard let level = CoreVocabulary.level(of: lemma) else { continue }
                total += CoreVocabulary.levelRank(level) >= minRank ? 2 : 1
            }
            return total
        }
        var scored: [(index: Int, turn: Turn, score: Int)] = []
        for (index, turn) in candidates.enumerated() {
            let score = teachScore(turn)
            if score > 0 { scored.append((index, turn, score)) }
        }
        guard !scored.isEmpty else { return Array(candidates.suffix(maxShadowLines)) }
        scored.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        let picked = scored.prefix(maxShadowLines).sorted { $0.index < $1.index }
        return picked.map { $0.turn }
    }

    /// Stable shadow-line id derived from the source turn — the SAME
    /// transform the transcript's suggestion-shadow has always used
    /// (first byte XOR), so attempts made from either surface land on the
    /// same line and old attempts count retroactively.
    static func shadowLineId(for turnId: UUID) -> UUID {
        var bytes = turnId.uuid
        bytes.0 ^= 0xFF
        return UUID(uuid: bytes)
    }

    static func build(session: Session,
                      proficiency: CEFRLevel,
                      shadowAttempts: [ShadowAttempt],
                      drillCards: [DrillCard]) -> Snapshot {
        var snap = Snapshot()

        // Lemma membership, not a substring regex: the pickup words ARE
        // lemmas, so this is the symmetric test. It credits inflected forms
        // ("went" masters "go") and survives languages that glue particles
        // onto words (Korean "학교에"), both of which the old \b match missed.
        let userLemmas = VocabStore.lemmas(
            in: session.turns.filter { $0.role == .user }.map(\.transcript))
        func saidByUser(_ word: String) -> Bool {
            userLemmas.contains(word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }

        // Words — the fluent self's pickup words, mastered by the same rules
        // as `AppState.refreshScenarioMastery` (in the vocab store, or said
        // by the user themselves).
        // CANDIDATES, not pickupWords: the latter drops every word that has a
        // vocab record, i.e. exactly the ones the learner has since mastered.
        // Built on that, this chapter shrank as you learned instead of filling
        // in, and its progress was pinned at 0 forever.
        let pickups = VocabStore.shared.pickupCandidates(
            fromFluentTexts: session.turns.filter { $0.role == .fluentSelf }.map(\.transcript),
            atOrAbove: proficiency
        ).prefix(maxWords)
        snap.words = pickups.map { w in
            var item = ScenarioCurriculum.Item(text: w, note: "")
            // Mastery time is the REAL study time (vocab record / the talk
            // itself), not the snapshot build time — book shelves order by it.
            let vocabDate = [w, w.lowercased(), VocabStore.lookupKey(for: w)]
                .compactMap { VocabStore.shared.lastAt(of: $0) }.max()
            if let vocabDate {
                item.masteredAt = vocabDate
            } else if saidByUser(w) {
                item.masteredAt = session.endedAt ?? session.startedAt
            }
            return item
        }

        // Shadow lines — every corrected sentence, in conversation order.
        // Misheard-flagged turns are skipped: their "correction" fixes a
        // sentence the user never said.
        let sessionCards = drillCards.filter { $0.sourceSessionId == session.id }
        for turn in session.turns where turn.role == .user && !turn.excludedFromScoring {
            guard let s = turn.suggestion else { continue }
            var item = ScenarioCurriculum.Item(
                id: shadowLineId(for: turn.id),
                text: s.alternative,
                note: s.reason
            )
            item.masteredAt = shadowAttempts
                .filter { $0.turnId == item.id && $0.matchScore >= ScenarioCurriculum.shadowMasteryScore }
                .map(\.createdAt).max()
            // The book page studies corrections as drill CARDS, not shadowing
            // — a card graduated to the top box (Got it / produced live in a
            // talk) masters the line, or the cover's count asks for work no
            // chapter offers. Turn-id match first; text match catches cards
            // minted from the summary without a source turn (same fallback
            // the Drill chapter's openCard uses).
            if item.masteredAt == nil {
                let needle = CarryoverDetector.normalized(s.alternative)
                if let card = sessionCards.first(where: {
                    $0.box == DrillStore.maxBox
                        && ($0.sourceTurnId == turn.id
                            || CarryoverDetector.normalized($0.targetPhrase) == needle)
                }) {
                    item.masteredAt = card.lastReviewedAt ?? card.createdAt
                }
            }
            snap.shadowLines.append(item)
        }

        return snap
    }
}
