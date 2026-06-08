import Foundation

/// Aggregates across past sessions for the home dashboard. Cheap to recompute
/// — `SessionStore.load()` is small JSON, and the dashboard recomputes only
/// when the home view appears, not on every conversation turn.
enum PracticeStats {

    struct Snapshot {
        var streakDays: Int                 // consecutive days ending today with ≥1 ended session
        var totalSessions: Int
        var lastScorecard: SessionScorecard?
        var lastSessionEndedAt: Date?
        var lastSevenDayScores: [Double]    // newest-last, missing days = 0
        var shadowableLineCount: Int        // fluent-self turns across all sessions
    }

    static func snapshot(now: Date = Date(), calendar: Calendar = .current) -> Snapshot {
        let sessions = SessionStore.shared.load()
        let endedSessions = sessions.filter { $0.endedAt != nil }

        let streak = computeStreak(sessions: endedSessions, now: now, calendar: calendar)
        let last = endedSessions.first   // SessionStore.load is sorted newest-first
        let weekly = computeWeeklyAverages(sessions: endedSessions, now: now, calendar: calendar)
        let shadowable = sessions.flatMap { $0.turns }.filter { $0.role == .fluentSelf }.count

        return Snapshot(
            streakDays: streak,
            totalSessions: endedSessions.count,
            lastScorecard: last?.summary?.scorecard,
            lastSessionEndedAt: last?.endedAt,
            lastSevenDayScores: weekly,
            shadowableLineCount: shadowable
        )
    }

    // MARK: - Helpers

    private static func computeStreak(sessions: [Session], now: Date, calendar: Calendar) -> Int {
        // Bucket session days, then walk back from today until we find a gap.
        var days: Set<Date> = []
        for s in sessions {
            guard let ended = s.endedAt else { continue }
            days.insert(calendar.startOfDay(for: ended))
        }
        guard !days.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: now)
        while days.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        // If user hasn't practiced today yet, allow yesterday as the streak tail
        // so the count doesn't reset at midnight before they've had a chance.
        if streak == 0,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           days.contains(yesterday) {
            cursor = yesterday
            while days.contains(cursor) {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            }
        }
        return streak
    }

    /// Per-day average overall score (mean of 4 axes) for the last 7 days,
    /// newest-last. Days with no sessions become 0. Pronunciation is excluded
    /// because it's not yet tracked in the scorecard.
    private static func computeWeeklyAverages(
        sessions: [Session],
        now: Date,
        calendar: Calendar
    ) -> [Double] {
        var bucket: [Date: [Double]] = [:]
        for s in sessions {
            guard let ended = s.endedAt, let card = s.summary?.scorecard else { continue }
            let day = calendar.startOfDay(for: ended)
            let avg = Double(card.vocabulary.score + card.grammar.score + card.expressiveness.score + card.fluency.score) / 4.0
            bucket[day, default: []].append(avg)
        }
        var out: [Double] = []
        let today = calendar.startOfDay(for: now)
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let scores = bucket[day] ?? []
            let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
            out.append(avg)
        }
        return out
    }
}
