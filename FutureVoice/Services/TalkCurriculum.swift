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
///                    scoring ≥ `ScenarioCurriculum.shadowMasteryScore`
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
                      shadowAttempts: [ShadowAttempt]) -> Snapshot {
        var snap = Snapshot()

        let spoken = session.turns.filter { $0.role == .user }
            .map(\.transcript).joined(separator: " ").lowercased()
        func saidByUser(_ word: String) -> Bool {
            let needle = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty else { return false }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b"
            return spoken.range(of: pattern, options: .regularExpression) != nil
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
            snap.shadowLines.append(item)
        }

        return snap
    }
}
