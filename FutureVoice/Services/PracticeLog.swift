import Foundation

/// Day-bucketed practice effort log (`Documents/practice-log.json`).
///
/// The stores only keep LATEST state (a card's last review date, a line's
/// attempts) — fine for scheduling, useless for showing effort over time.
/// This log records every rep as it happens so the Practice tab can show an
/// honest "you showed up" strip and weekly totals. Counts only; no content.
final class PracticeLog {
    static let shared = PracticeLog()

    /// Two numbers per kind, because they answer two different questions.
    ///
    /// `*Reps` = EFFORT: every time the learner handled the item at all —
    /// bookmarking a word, pushing a card to tomorrow. That's what the
    /// activity chart on Progress is about ("you showed up").
    ///
    /// `*Done` = FINISHED: the item was actually retired — "Got it" on a card,
    /// "I know" on a word or phrase, a recorded shadow take. That's what a
    /// daily goal is about. The two were one number, so a day could be ticked
    /// complete by postponing ten cards.
    struct Day: Codable {
        var drillReps: Int = 0
        var shadowReps: Int = 0
        var wordReps: Int = 0
        var expressionReps: Int = 0
        var drillDone: Int = 0
        var shadowDone: Int = 0
        var wordDone: Int = 0
        var expressionDone: Int = 0
        /// Watch scenes heard that day. Kept OUT of `total`: the rep bars on
        /// Progress and Activity count handling review material, and a scene
        /// is watching, not a rep. It exists for `showedUp` — the streak.
        var sceneReps: Int = 0
        var total: Int { drillReps + shadowReps + wordReps + expressionReps }
        /// Anything at all was studied or used this day — the streak's
        /// question (`PracticeStats.studied(on:)`), not the goal's.
        var showedUp: Bool { total > 0 || sceneReps > 0 }

        func done(_ kind: Kind) -> Int {
            switch kind {
            case .drill:      return drillDone
            case .shadow:     return shadowDone
            case .word:       return wordDone
            case .expression: return expressionDone
            case .scene:      return sceneReps
            }
        }
    }

    enum Kind {
        case drill
        case shadow
        case word
        case expression
        case scene
    }

    private var days: [String: Day]
    private let fileURL: URL
    /// Guards `days`. Writes come from the main actor, but the streak
    /// (`PracticeStats.activeDays`) is also read from `ProgressTab`'s
    /// detached reload, and an unguarded Dictionary read racing a write is a
    /// crash, not a stale number.
    private let lock = NSLock()

    init(filename: String = "practice-log.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Day].self, from: data) {
            self.days = decoded
        } else {
            self.days = [:]
        }
    }

    /// Drops the in-memory day map and re-reads the file. Only `BackupService`
    /// needs this: the log is read once at init and held for the process's
    /// life, so a restore that replaced the file on disk would be erased by
    /// the very next `record()` writing the stale map back out.
    func reloadFromDisk() {
        let fresh = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: Day].self, from: $0) } ?? [:]
        lock.lock(); days = fresh; lock.unlock()
    }

    /// - Parameter finished: the item is done with (mastered / known /
    ///   actually said out loud), as opposed to merely handled. Only finished
    ///   work counts toward a daily goal.
    func record(_ kind: Kind, finished: Bool = false, on date: Date = Date()) {
        let key = Self.key(for: date)
        lock.lock()
        var day = days[key] ?? Day()
        switch kind {
        case .drill:      day.drillReps += 1
        case .shadow:     day.shadowReps += 1
        case .word:       day.wordReps += 1
        case .expression: day.expressionReps += 1
        case .scene:      day.sceneReps += 1
        }
        if finished {
            switch kind {
            case .drill:      day.drillDone += 1
            case .shadow:     day.shadowDone += 1
            case .word:       day.wordDone += 1
            case .expression: day.expressionDone += 1
            case .scene:      break
            }
        }
        days[key] = day
        let snapshot = days
        lock.unlock()
        save(snapshot)
    }

    func day(_ date: Date) -> Day? {
        let key = Self.key(for: date)
        lock.lock(); defer { lock.unlock() }
        return days[key]
    }

    /// Every day that `showedUp`, as local start-of-day dates. The log is
    /// never pruned, so this reaches back to the first rep ever recorded.
    func activeDays(calendar: Calendar = .current) -> Set<Date> {
        lock.lock(); let all = days; lock.unlock()
        return Set(all.compactMap { key, day -> Date? in
            guard day.showedUp, let date = Self.keyFormatter.date(from: key) else { return nil }
            return calendar.startOfDay(for: date)
        })
    }

    /// Total reps in the 7 days ending today (inclusive).
    func repsThisWeek(now: Date = Date(), calendar: Calendar = .current) -> Int {
        (0..<7).reduce(0) { acc, offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: now) else { return acc }
            return acc + (day(d)?.total ?? 0)
        }
    }

    private func save(_ days: [String: Day]) {
        guard let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        SyncEngine.noteChanged(.practiceDay)
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func key(for date: Date) -> String {
        keyFormatter.string(from: date)
    }
}

extension PracticeLog.Day {
    // Lenient decoding: logs written before the word/expression counters
    // existed lack those keys, and the loader treats a decode failure as an
    // empty log — which would erase the whole history on first launch.
    private enum CodingKeys: String, CodingKey {
        case drillReps, shadowReps, wordReps, expressionReps
        case drillDone, shadowDone, wordDone, expressionDone
        case sceneReps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        drillReps      = try c.decodeIfPresent(Int.self, forKey: .drillReps) ?? 0
        shadowReps     = try c.decodeIfPresent(Int.self, forKey: .shadowReps) ?? 0
        wordReps       = try c.decodeIfPresent(Int.self, forKey: .wordReps) ?? 0
        expressionReps = try c.decodeIfPresent(Int.self, forKey: .expressionReps) ?? 0
        // Days logged before the split have no done counts. A shadow rep IS a
        // recorded take, so that one can be recovered exactly; the others
        // can't tell postponed from finished and stay at 0 rather than
        // inventing credit for work that may not have happened.
        drillDone      = try c.decodeIfPresent(Int.self, forKey: .drillDone) ?? 0
        shadowDone     = try c.decodeIfPresent(Int.self, forKey: .shadowDone) ?? shadowReps
        wordDone       = try c.decodeIfPresent(Int.self, forKey: .wordDone) ?? 0
        expressionDone = try c.decodeIfPresent(Int.self, forKey: .expressionDone) ?? 0
        sceneReps      = try c.decodeIfPresent(Int.self, forKey: .sceneReps) ?? 0
    }

    /// `sceneReps` is written only when non-zero. Sync fingerprints each day
    /// from its encoding (`SyncCanonical`), so a `"sceneReps":0` on every
    /// existing day would re-upload the whole log once for nothing.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(drillReps, forKey: .drillReps)
        try c.encode(shadowReps, forKey: .shadowReps)
        try c.encode(wordReps, forKey: .wordReps)
        try c.encode(expressionReps, forKey: .expressionReps)
        try c.encode(drillDone, forKey: .drillDone)
        try c.encode(shadowDone, forKey: .shadowDone)
        try c.encode(wordDone, forKey: .wordDone)
        try c.encode(expressionDone, forKey: .expressionDone)
        if sceneReps > 0 { try c.encode(sceneReps, forKey: .sceneReps) }
    }
}
