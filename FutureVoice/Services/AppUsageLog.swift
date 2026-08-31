import Foundation

/// Seconds the app spent in the FOREGROUND, per local day — "how long did I
/// study today", for the day card. Written at the edges of a foreground stint
/// (`FutureVoiceApp` on `scenePhase`), never polled.
///
/// Deliberately naive: a call that keeps running in a pocket is metered by
/// `TalkMeter` but not counted here, so the card takes `max(usage, talk)`. It
/// is a study-time figure, not a billing one — the day's talk seconds stay
/// with `TalkTimeLog`, which reads the meter.
@MainActor
enum AppUsageLog {
    private static let key = "futurevoice.foregroundSecondsByDay"
    private static let keepDays = 45
    private static var activeSince: Date?

    static func becameActive(now: Date = Date()) {
        activeSince = now
    }

    static func resigned(now: Date = Date()) {
        guard let since = activeSince else { return }
        activeSince = nil
        add(seconds: Int(now.timeIntervalSince(since)), now: now)
    }

    /// Stored seconds for a day — plus the open stint when the day is today,
    /// so a card made mid-session counts the minutes it is being made in.
    static func seconds(on day: Date, now: Date = Date()) -> Int {
        let stored = load()[dayKey(day)] ?? 0
        guard dayKey(day) == dayKey(now) else { return stored }
        let open = activeSince.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        return stored + open
    }

    private static func add(seconds: Int, now: Date) {
        guard seconds > 0 else { return }
        var map = load()
        map[dayKey(now), default: 0] += seconds
        if map.count > keepDays {
            let cutoff = dayKey(now.addingTimeInterval(-Double(keepDays) * 86_400))
            map = map.filter { $0.key >= cutoff }
        }
        UserDefaults.standard.set(map, forKey: key)
    }

    private static func load() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    /// LOCAL day, same shape as `TalkTimeLog`'s keys.
    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
