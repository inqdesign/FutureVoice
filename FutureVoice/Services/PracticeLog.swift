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
        var total: Int { drillReps + shadowReps + wordReps + expressionReps }

        func done(_ kind: Kind) -> Int {
            switch kind {
            case .drill:      return drillDone
            case .shadow:     return shadowDone
            case .word:       return wordDone
            case .expression: return expressionDone
            }
        }
    }

    enum Kind {
        case drill
        case shadow
        case word
        case expression
    }

    private var days: [String: Day]
    private let fileURL: URL

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

    /// - Parameter finished: the item is done with (mastered / known /
    ///   actually said out loud), as opposed to merely handled. Only finished
    ///   work counts toward a daily goal.
    func record(_ kind: Kind, finished: Bool = false, on date: Date = Date()) {
        let key = Self.key(for: date)
        var day = days[key] ?? Day()
        switch kind {
        case .drill:      day.drillReps += 1
        case .shadow:     day.shadowReps += 1
        case .word:       day.wordReps += 1
        case .expression: day.expressionReps += 1
        }
        if finished {
            switch kind {
            case .drill:      day.drillDone += 1
            case .shadow:     day.shadowDone += 1
            case .word:       day.wordDone += 1
            case .expression: day.expressionDone += 1
            }
        }
        days[key] = day
        save()
    }

    func day(_ date: Date) -> Day? { days[Self.key(for: date)] }

    /// Total reps in the 7 days ending today (inclusive).
    func repsThisWeek(now: Date = Date(), calendar: Calendar = .current) -> Int {
        (0..<7).reduce(0) { acc, offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: now) else { return acc }
            return acc + (day(d)?.total ?? 0)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: fileURL, options: [.atomic])
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
    }
}
