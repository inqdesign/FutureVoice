import Foundation

/// Day-bucketed practice effort log (`Documents/practice-log.json`).
///
/// The stores only keep LATEST state (a card's last review date, a line's
/// attempts) — fine for scheduling, useless for showing effort over time.
/// This log records every rep as it happens so the Practice tab can show an
/// honest "you showed up" strip and weekly totals. Counts only; no content.
final class PracticeLog {
    static let shared = PracticeLog()

    struct Day: Codable {
        var drillReps: Int = 0
        var shadowReps: Int = 0
        var wordReps: Int = 0
        var expressionReps: Int = 0
        var total: Int { drillReps + shadowReps + wordReps + expressionReps }
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

    func record(_ kind: Kind, on date: Date = Date()) {
        let key = Self.key(for: date)
        var day = days[key] ?? Day()
        switch kind {
        case .drill:      day.drillReps += 1
        case .shadow:     day.shadowReps += 1
        case .word:       day.wordReps += 1
        case .expression: day.expressionReps += 1
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
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        drillReps      = try c.decodeIfPresent(Int.self, forKey: .drillReps) ?? 0
        shadowReps     = try c.decodeIfPresent(Int.self, forKey: .shadowReps) ?? 0
        wordReps       = try c.decodeIfPresent(Int.self, forKey: .wordReps) ?? 0
        expressionReps = try c.decodeIfPresent(Int.self, forKey: .expressionReps) ?? 0
    }
}
