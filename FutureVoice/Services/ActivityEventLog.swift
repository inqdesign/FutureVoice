import Foundation

/// WHEN each practice rep happened — the timetable's "what actually
/// happened" for everything that isn't a talk (a talk has its own
/// `Session.startedAt`/`endedAt`). `PracticeLog` only counts reps per day,
/// which can say how much but not at what time.
///
/// Fed from the one door every rep already walks through
/// (`PracticeLog.record`), plus "say it again" runs, which are logged when a
/// run finishes. Device-local, pruned to `keepDays`; anything older is still
/// counted in `PracticeLog`, it just has no time of day.
final class ActivityEventLog: @unchecked Sendable {
    static let shared = ActivityEventLog()

    enum Kind: String, Codable {
        case drill, shadow, word, expression, scene, sayItAgain
    }

    struct Event: Codable, Equatable {
        var kind: Kind
        var at: Date
    }

    static let keepDays = 60

    private let lock = NSLock()
    private var events: [Event]
    private let url: URL

    init(filename: String = "activity_events.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: url),
           let decoded = try? Self.decoder.decode([Event].self, from: data) {
            events = decoded
        } else {
            events = []
        }
    }

    func record(_ kind: Kind, at date: Date = Date()) {
        lock.lock()
        events.append(Event(kind: kind, at: date))
        let cutoff = date.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        if let first = events.first, first.at < cutoff {
            events.removeAll { $0.at < cutoff }
        }
        let snapshot = events
        lock.unlock()
        if let data = try? Self.encoder.encode(snapshot) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    /// Events within `[start, end)`, oldest first.
    func events(from start: Date, to end: Date) -> [Event] {
        lock.lock(); defer { lock.unlock() }
        return events.filter { $0.at >= start && $0.at < end }.sorted { $0.at < $1.at }
    }

    #if DEBUG
    func replaceAll(_ new: [Event]) {
        lock.lock(); events = new; lock.unlock()
        if let data = try? Self.encoder.encode(new) { try? data.write(to: url, options: [.atomic]) }
    }
    #endif

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}

extension ActivityEventLog.Kind {
    init(_ kind: PracticeLog.Kind) {
        switch kind {
        case .drill: self = .drill
        case .shadow: self = .shadow
        case .word: self = .word
        case .expression: self = .expression
        case .scene: self = .scene
        }
    }
}
