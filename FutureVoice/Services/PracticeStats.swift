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

    // MARK: - Shadow / pronunciation trend

    /// Deterministic pronunciation signal from saved shadow attempts —
    /// average match score this week vs. the week before. No LLM involved;
    /// `ShadowEngine` scores are token-Levenshtein, so the trend is honest.
    struct ShadowTrend {
        var attemptsThisWeek: Int
        var avgThisWeek: Int        // 0 when no attempts
        var avgPrevWeek: Int        // 0 when no attempts
        /// Delta vs. previous week; nil when either window is empty.
        var delta: Int? {
            (attemptsThisWeek > 0 && avgPrevWeek > 0) ? avgThisWeek - avgPrevWeek : nil
        }
    }

    static func shadowTrend(
        attempts: [ShadowAttempt],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ShadowTrend {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now

        let thisWeek = attempts.filter { $0.createdAt > weekAgo }
        let prevWeek = attempts.filter { $0.createdAt > twoWeeksAgo && $0.createdAt <= weekAgo }

        func avg(_ list: [ShadowAttempt]) -> Int {
            guard !list.isEmpty else { return 0 }
            return Int((Double(list.reduce(0) { $0 + $1.matchScore }) / Double(list.count)).rounded())
        }

        return ShadowTrend(
            attemptsThisWeek: thisWeek.count,
            avgThisWeek: avg(thisWeek),
            avgPrevWeek: avg(prevWeek)
        )
    }

    // MARK: - Shadow picks (curated "what to shadow today")

    /// One suggested shadow line with a human reason. The Practice home shows
    /// a handful of these instead of dumping the full line archive.
    struct ShadowPick: Identifiable {
        let turn: Turn
        let reason: String
        var id: UUID { turn.id }
    }

    /// Minimum substance for a fresh pick — one-word reactions ("Really?")
    /// aren't worth a prosody rep.
    private static let minPickWords = 4

    /// Score under which a past attempt earns a retry suggestion.
    static let retryThreshold = 75

    /// Curate up to `limit` lines: fresh lines from the newest sessions the
    /// user hasn't shadowed yet, then low-score retries (latest attempt per
    /// line < `retryThreshold`). Fresh-first keeps picks tied to whatever
    /// the user just talked about.
    static func shadowPicks(
        sessions: [Session],
        attempts: [ShadowAttempt],
        limit: Int = 3
    ) -> [ShadowPick] {
        // Latest attempt per target line.
        var latestByTurn: [UUID: ShadowAttempt] = [:]
        for a in attempts {
            if let existing = latestByTurn[a.turnId], existing.createdAt >= a.createdAt { continue }
            latestByTurn[a.turnId] = a
        }

        // Fresh: never-attempted fluent-self lines, newest session first.
        var fresh: [ShadowPick] = []
        var seenTexts = Set<String>()
        let newestFirst = sessions.sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        for session in newestFirst {
            for turn in session.turns where turn.role == .fluentSelf {
                let text = turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = text.lowercased()
                guard !text.isEmpty,
                      text.split(separator: " ").count >= minPickWords,
                      latestByTurn[turn.id] == nil,
                      !seenTexts.contains(key) else { continue }
                seenTexts.insert(key)
                fresh.append(ShadowPick(
                    turn: turn,
                    reason: "From: \(session.topic?.isEmpty == false ? session.topic! : "recent conversation")"
                ))
            }
        }

        // Retries: latest attempt scored low. Reuse the original turn when it
        // still exists so past attempts stay attached; otherwise rebuild from
        // the attempt's captured target text.
        let turnById: [UUID: Turn] = sessions
            .flatMap { $0.turns }
            .reduce(into: [:]) { $0[$1.id] = $1 }
        let retries: [ShadowPick] = latestByTurn.values
            .filter { $0.matchScore < retryThreshold }
            .sorted { $0.createdAt > $1.createdAt }
            .map { a in
                let turn = turnById[a.turnId] ?? Turn(
                    id: a.turnId, role: .fluentSelf, audioURL: nil,
                    transcript: a.targetText, durationMs: 0,
                    timestamp: a.createdAt, suggestion: nil
                )
                return ShadowPick(turn: turn, reason: "Retry — last score \(a.matchScore)")
            }

        var out = Array(fresh.prefix(max(0, limit - min(1, retries.count))))
        for r in retries where out.count < limit { out.append(r) }
        for f in fresh.dropFirst(out.filter { !$0.reason.hasPrefix("Retry") }.count) where out.count < limit {
            out.append(f)
        }
        return out
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
