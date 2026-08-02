import Foundation

/// On-disk cache for the scenario composer's drill-down chips.
///
/// The composer used to keep its ideas in a static in-memory dict, so every
/// app launch paid the full Gemini round-trip again for the SAME
/// "Travel › at the hotel" path — several seconds of empty chips, and a bill.
/// This survives launches: a path asked once is instant forever after (until
/// the TTL expires), and only the explicit "More" button forces a new call.
///
/// Entries are keyed by person + path, so ideas scoped to a counterpart never
/// leak into the blank composer.
final class ScenarioIdeaCache {
    static let shared = ScenarioIdeaCache()

    /// Ideas go stale slowly — a hotel is a hotel. Long enough that repeat
    /// visits are free, short enough that a persona change eventually shows.
    private static let ttl: TimeInterval = 30 * 24 * 3600
    /// Keep the file small; oldest entries drop out first.
    private static let maxEntries = 150

    private struct Entry: Codable {
        let topics: [SuggestedTopic]
        let savedAt: Date
    }

    private let fileURL: URL
    private let lock = NSLock()
    private var entries: [String: Entry]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "scenario-ideas.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent(filename)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? dec.decode([String: Entry].self, from: data) {
            let cutoff = Date().addingTimeInterval(-Self.ttl)
            self.entries = loaded.filter { $0.value.savedAt > cutoff }
        } else {
            self.entries = [:]
        }
    }

    func topics(for key: String) -> [SuggestedTopic]? {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries[key], e.savedAt > Date().addingTimeInterval(-Self.ttl) else {
            return nil
        }
        return e.topics
    }

    func store(_ topics: [SuggestedTopic], for key: String) {
        guard !topics.isEmpty else { return }
        lock.lock()
        entries[key] = Entry(topics: topics, savedAt: Date())
        if entries.count > Self.maxEntries {
            let keep = entries.sorted { $0.value.savedAt > $1.value.savedAt }
                .prefix(Self.maxEntries)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        let snapshot = entries
        lock.unlock()

        let url = fileURL, enc = encoder
        Task.detached(priority: .utility) {
            guard let data = try? enc.encode(snapshot) else { return }
            try? data.write(to: url, options: [.atomic])
        }
    }

    func clear() {
        lock.lock(); entries = [:]; lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
