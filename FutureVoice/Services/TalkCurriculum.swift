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

    /// The fluent-self SENTENCES worth shadowing, in conversation order.
    ///
    /// The unit is a sentence, not a turn, and that is the whole point.
    /// Measured over 66 real talks (2026-09-01): the fluent self speaks a
    /// median of 26 words per turn, so **40% of turns overflow the 4–28 word
    /// window and were dropped whole** — the substantive middle of the call,
    /// exactly the part worth repeating. What survived was the short ritual
    /// lines. 70% of talks had fewer than the four candidates this is asked
    /// for and 15% had NONE, falling through to "the last thing said", which
    /// is how a farewell became the study material. Split into sentences the
    /// same talks offer a median of 10 candidates, only 11% fall short, and
    /// the median candidate is 9 words — a length a learner can actually say
    /// back in one breath.
    ///
    /// "Worth" means the learner could SAY IT AGAIN somewhere else. Two
    /// things decide that, in order:
    ///
    ///   • a line carrying one of the summary's `expressions_offered` —
    ///     reusable phrases the fluent self used and the learner didn't,
    ///     already LLM-picked and verbatim-verified — outranks everything;
    ///   • then core-list lemmas AT or ABOVE the learner's level. Below-level
    ///     lemmas used to score a point each, which is exactly how "So nice
    ///     to talk to you today!" (all A1 words) kept beating the middle of
    ///     the call.
    ///
    /// The call's opener and farewell are excluded by POSITION (first/last
    /// fluent-self turn) — they're ritual, not material, and no word list
    /// can see that — unless nothing else scores. A talk with nothing
    /// scoreable at all falls back to its last substantive lines so the
    /// chapter never goes empty.
    nonisolated static func shadowPicks(session: Session,
                                        proficiency: CEFRLevel) -> [Turn] {
        let fluent = session.turns.filter { $0.role == .fluentSelf }
        let edgeIds = Set([fluent.first?.id, fluent.last?.id].compactMap { $0 })
        let offered = (session.summary?.expressionsOffered ?? [])
            .map { CarryoverDetector.normalized($0) }
            .filter { !$0.isEmpty }
        let minRank = CoreVocabulary.levelRank(proficiency)
        func teachScore(_ text: String) -> Int {
            var total = 0
            let line = " " + CarryoverDetector.normalized(text) + " "
            for phrase in offered where line.contains(" " + phrase + " ") {
                total += 3
            }
            for lemma in VocabStore.lemmas(in: [text]) {
                guard let level = CoreVocabulary.level(of: lemma) else { continue }
                if CoreVocabulary.levelRank(level) >= minRank { total += 1 }
            }
            return total
        }

        // Candidates are SENTENCES, in conversation order.
        //
        // De-duplicated: the fluent self repeats itself across a call ("Oh,
        // that's really interesting." twice in one talk, seen in real data),
        // and a chapter that asks the learner to shadow the same line twice
        // is asking for one line and wasting a slot.
        var candidates: [(index: Int, turn: Turn, isEdge: Bool)] = []
        var seen = Set<String>()
        for turn in fluent {
            let parts = sentences(in: turn.transcript)
            for (offset, sentence) in parts.enumerated() {
                guard (4...28).contains(sentence.split(separator: " ").count) else { continue }
                guard seen.insert(CarryoverDetector.normalized(sentence)).inserted else { continue }
                // A turn that IS one sentence keeps its own identity: its
                // recorded audio still matches the text, and any shadow
                // attempt already made against it still counts.
                let piece = parts.count == 1
                    ? turn
                    : Turn(id: sentenceLineId(for: turn.id, index: offset),
                           role: .fluentSelf, audioURL: nil, transcript: sentence,
                           durationMs: 0, timestamp: turn.timestamp, suggestion: nil)
                candidates.append((candidates.count, piece, edgeIds.contains(turn.id)))
            }
        }

        var scored = candidates.filter { !$0.isEdge }
            .map { (index: $0.index, turn: $0.turn, score: teachScore($0.turn.transcript)) }
            .filter { $0.score > 0 }
        if scored.isEmpty {
            scored = candidates.filter(\.isEdge)
                .map { (index: $0.index, turn: $0.turn, score: teachScore($0.turn.transcript)) }
                .filter { $0.score > 0 }
        }
        guard !scored.isEmpty else {
            let middle = candidates.filter { !$0.isEdge }.map(\.turn)
            let pool = middle.isEmpty ? candidates.map(\.turn) : middle
            return Array(pool.suffix(maxShadowLines))
        }
        scored.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        return scored.prefix(maxShadowLines).sorted { $0.index < $1.index }.map(\.turn)
    }

    /// Split a spoken turn into the sentences it is made of.
    ///
    /// Deliberately naive — terminal punctuation only. The text is
    /// model-written speech, not prose with abbreviations and decimals, and a
    /// bad split produces a fragment the 4-word floor above throws away.
    nonisolated static func sentences(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            guard ".!?".contains(character) else { continue }
            let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { out.append(piece) }
            current = ""
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    /// Stable id for one sentence of a turn, so a shadow attempt made today is
    /// still recognised tomorrow. Derived from the source turn like
    /// `shadowLineId`, but off a different byte so the two can never collide.
    nonisolated static func sentenceLineId(for turnId: UUID, index: Int) -> UUID {
        var bytes = turnId.uuid
        bytes.15 ^= 0xA0 &+ UInt8(index & 0x0F)
        return UUID(uuid: bytes)
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
