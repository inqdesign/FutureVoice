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

    // MARK: - Carryover (studied → said in a real conversation)

    /// The proof-of-transfer number, and the one almost no language app can
    /// show: material the learner had been given that they later produced
    /// unprompted, live.
    ///
    /// Deduped by item text across sessions — saying the same phrase in five
    /// talks is one thing learned, not five — and dated by FIRST use, so the
    /// weekly figure means "newly crossed over", not "said again".
    struct CarryoverSummary {
        var total = 0
        var thisWeek = 0
        var bySource: [Carryover.Source: Int] = [:]
        /// Newest first — the evidence list under the number.
        var recent: [Carryover] = []
    }

    static func carryoverSummary(
        sessions: [Session],
        now: Date = Date(),
        recentLimit: Int = 3
    ) -> CarryoverSummary {
        var firstByItem: [String: Carryover] = [:]
        for session in sessions {
            for c in session.summary?.carryovers ?? [] {
                let key = CarryoverDetector.normalized(c.item)
                guard !key.isEmpty else { continue }
                if let existing = firstByItem[key], existing.detectedAt <= c.detectedAt { continue }
                firstByItem[key] = c
            }
        }
        let all = Array(firstByItem.values)
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        var bySource: [Carryover.Source: Int] = [:]
        for c in all { bySource[c.source, default: 0] += 1 }
        return CarryoverSummary(
            total: all.count,
            thisWeek: all.filter { $0.detectedAt > weekAgo }.count,
            bySource: bySource,
            recent: Array(all.sorted { $0.detectedAt > $1.detectedAt }.prefix(recentLimit)))
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

    /// Word-count band per CEFR level. A beginner shadowing a 20-word
    /// sentence drowns; a C1 learner repeating 4-word lines learns nothing.
    /// Length is a crude but deterministic difficulty proxy — the lines all
    /// come from level-calibrated conversations anyway, so length is the
    /// main residual variance.
    static func wordBand(for level: CEFRLevel) -> ClosedRange<Int> {
        switch level {
        case .a1: return 4...8
        case .a2: return 4...10
        case .b1: return 5...14
        case .b2: return 6...18
        case .c1, .c2: return 8...40
        }
    }

    /// How much a line teaches at the learner's level: the count of words
    /// graded AT or ABOVE their CEFR level in the core word list. Greetings
    /// and small talk ("Good to catch up! How was your day?") score ~0 and
    /// sink; lines carrying real vocabulary rise. Deterministic — pure
    /// word-list lookup, no LLM.
    static func lexicalValue(of text: String, level: CEFRLevel) -> Int {
        let learnerRank = CoreVocabulary.levelRank(level)
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty }
            .reduce(0) { acc, word in
                guard let lv = CoreVocabulary.level(of: word) else { return acc }
                return acc + (CoreVocabulary.levelRank(lv) >= learnerRank ? 1 : 0)
            }
    }

    /// Curate up to `limit` lines: fresh lines from the newest sessions the
    /// user hasn't shadowed yet (sized to the learner's level), then
    /// low-score retries (latest attempt per line < `retryThreshold`).
    /// Fresh-first keeps picks tied to whatever the user just talked about.
    ///
    /// Two guards against "why is it suggesting the greeting?":
    ///   • each session's OPENER (its first fluent-self line) is excluded —
    ///     it's the scripted ice-breaker, not conversation substance — unless
    ///     literally nothing else qualifies;
    ///   • within a session, candidates rank by `lexicalValue` so the lines
    ///     that teach the most vocabulary come first, not the earliest ones.
    static func shadowPicks(
        sessions: [Session],
        attempts: [ShadowAttempt],
        level: CEFRLevel,
        limit: Int = 3
    ) -> [ShadowPick] {
        // Latest attempt per target line.
        var latestByTurn: [UUID: ShadowAttempt] = [:]
        for a in attempts {
            if let existing = latestByTurn[a.turnId], existing.createdAt >= a.createdAt { continue }
            latestByTurn[a.turnId] = a
        }

        // Fresh: never-attempted fluent-self lines, newest session first.
        // Preferred = fits the learner's level band; if nothing does (e.g.
        // an A1 learner whose avatar spoke long lines), fall back to any
        // substantive line; openers are the tier of last resort.
        struct Candidate {
            let pick: ShadowPick
            let sessionIndex: Int
            let value: Int
        }
        let band = wordBand(for: level)
        var banded: [Candidate] = []
        var fallback: [Candidate] = []
        var openers: [Candidate] = []
        var seenTexts = Set<String>()
        let newestFirst = sessions.sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        for (sessionIndex, session) in newestFirst.enumerated() {
            let openerId = session.turns.first { $0.role == .fluentSelf }?.id
            for turn in session.turns where turn.role == .fluentSelf {
                let text = turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = text.lowercased()
                let wordCount = text.split(separator: " ").count
                guard !text.isEmpty,
                      wordCount >= minPickWords,
                      latestByTurn[turn.id] == nil,
                      !seenTexts.contains(key) else { continue }
                seenTexts.insert(key)
                let candidate = Candidate(
                    pick: ShadowPick(
                        turn: turn,
                        reason: "From: \(session.topic?.isEmpty == false ? session.topic! : "recent conversation")"
                    ),
                    sessionIndex: sessionIndex,
                    value: lexicalValue(of: text, level: level)
                )
                if turn.id == openerId {
                    openers.append(candidate)
                } else if band.contains(wordCount) {
                    banded.append(candidate)
                } else {
                    fallback.append(candidate)
                }
            }
        }
        // Newest session first, then the most teachable line within it.
        func ranked(_ list: [Candidate]) -> [ShadowPick] {
            list.sorted {
                $0.sessionIndex != $1.sessionIndex
                    ? $0.sessionIndex < $1.sessionIndex
                    : $0.value > $1.value
            }.map(\.pick)
        }
        let fresh = !banded.isEmpty ? ranked(banded)
            : !fallback.isEmpty ? ranked(fallback)
            : ranked(openers)

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
