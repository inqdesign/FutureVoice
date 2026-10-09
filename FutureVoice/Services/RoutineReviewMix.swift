import Foundation

/// How the routine's Review block splits its count between the four kinds
/// of review (2026-10-09). Pure, so the shares can be tested and retuned in
/// one place.
///
/// Shares: words 30% · sentence cards 30% · expressions 25% · shadow 15%.
/// Shadow is the smallest because a line is said out loud and graded — one
/// line is several cards' worth of time — and it is capped at
/// `maxShadow` whatever the count. A kind with less on hand than its share
/// passes the rest on to the CARD kinds (shadow never absorbs extra: a
/// 20-item block turning into 10 lines to record would be a different
/// sitting from the one planned).
enum RoutineReviewMix {
    struct Counts: Equatable {
        var words = 0, expressions = 0, sentences = 0, shadow = 0
        var total: Int { words + expressions + sentences + shadow }
    }

    static let maxShadow = 3

    static func quotas(goal: Int, available: Counts) -> Counts {
        guard goal > 0 else { return Counts() }
        var q = Counts()
        // At least one line once the block is big enough to hold a mix.
        let shadowShare = goal >= 5 ? max(1, Int((Double(goal) * 0.15).rounded())) : 0
        q.shadow = min(available.shadow, maxShadow, shadowShare)
        let cards = goal - q.shadow
        q.words = min(available.words, Int((Double(cards) * 0.35).rounded()))
        q.sentences = min(available.sentences, Int((Double(cards) * 0.35).rounded()))
        q.expressions = min(available.expressions, max(0, cards - q.words - q.sentences))

        // Spill what's left, one at a time, to whichever card kind still has
        // something — round-robin so no single kind swallows the remainder.
        var left = goal - q.total
        while left > 0 {
            var moved = false
            if left > 0, q.words < available.words { q.words += 1; left -= 1; moved = true }
            if left > 0, q.sentences < available.sentences { q.sentences += 1; left -= 1; moved = true }
            if left > 0, q.expressions < available.expressions { q.expressions += 1; left -= 1; moved = true }
            if !moved { break }
        }
        return q
    }
}
