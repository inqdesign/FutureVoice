import Foundation

/// The day's talk seconds as they were actually METERED — appended by
/// `TalkMeter` every time the server accepts a tick.
///
/// The home ring used to derive this from session records (`endedAt -
/// startedAt`), which is not the same thing at all: continuing an old talk
/// keeps the original `startedAt`, and backgrounding the app freezes the
/// ticks while the span keeps running. A learner saw "25 min" on the ring
/// and "13 min used today" on the receipt for the same afternoon.
///
/// So the ring reads what the meter counted, not what the clock could have
/// counted. Two consequences worth keeping: seconds that failed to meter
/// (offline) don't show up — but they weren't billed either, so the two
/// numbers still agree; and the count is keyed to the LOCAL day, because a
/// habit belongs to the day the learner is living in (the server pools per
/// UTC day for billing, and around midnight the two may briefly differ).
enum TalkTimeLog {
    private static let key = "futurevoice.talkSecondsByDay"
    /// Days kept before pruning — the ring needs today, the widget's history
    /// needs a couple of weeks of headroom, and this is a few hundred bytes.
    private static let keepDays = 30

    /// Record seconds the server accepted. Never call this for a tick that
    /// 402'd: those seconds were refused, and counting them would put the
    /// ring back ahead of the receipt.
    static func add(seconds: Int, now: Date = Date()) {
        guard seconds > 0 else { return }
        var map = load()
        map[dayKey(now), default: 0] += seconds
        save(prune(map, now: now))
    }

    static func secondsToday(now: Date = Date()) -> Int {
        load()[dayKey(now)] ?? 0
    }

    static func seconds(on day: Date) -> Int {
        load()[dayKey(day)] ?? 0
    }

    // MARK: - Disk

    private static func load() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    private static func save(_ map: [String: Int]) {
        UserDefaults.standard.set(map, forKey: key)
    }

    private static func prune(_ map: [String: Int], now: Date) -> [String: Int] {
        guard map.count > keepDays else { return map }
        let cutoff = dayKey(now.addingTimeInterval(-Double(keepDays) * 86_400))
        return map.filter { $0.key >= cutoff }
    }

    /// LOCAL day — see the type comment for why this differs from the
    /// server's UTC pooling.
    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
