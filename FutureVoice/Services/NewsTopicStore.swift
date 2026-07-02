import Foundation

/// Daily cache for news-grounded topics (`Documents/news_topics.json`).
/// Search-grounded Gemini calls cost more than plain ones, so we keep one
/// batch per day and invalidate when the user's interests change.
final class NewsTopicStore {
    static let shared = NewsTopicStore()

    struct Cached: Codable {
        var interestsKey: String
        var fetchedAt: Date
        var topics: [SuggestedTopic]
        /// Titles the user has already been SHOWN (refresh rotates them to
        /// the back). Optional so pre-existing cache files still decode.
        var seenTitles: [String]?
    }

    static let maxAge: TimeInterval = 24 * 60 * 60

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "news_topics.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent(filename)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Order- and case-insensitive fingerprint of the interest list.
    static func key(for interests: [String]) -> String {
        interests
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "|")
    }

    /// Cached topics, or nil when stale / interests changed / never fetched.
    func valid(for interests: [String], now: Date = Date()) -> [SuggestedTopic]? {
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? decoder.decode(Cached.self, from: data),
              cached.interestsKey == Self.key(for: interests),
              now.timeIntervalSince(cached.fetchedAt) < Self.maxAge,
              !cached.topics.isEmpty else {
            return nil
        }
        return cached.topics
    }

    func save(_ topics: [SuggestedTopic], interests: [String], now: Date = Date()) {
        // Keep seen-rotation state across saves of the same interest set —
        // a refresh save must not make everything look "unseen" again.
        let carriedSeen = load().flatMap {
            $0.interestsKey == Self.key(for: interests) ? $0.seenTitles : nil
        }
        let cached = Cached(interestsKey: Self.key(for: interests), fetchedAt: now,
                            topics: topics, seenTitles: carriedSeen)
        guard let data = try? encoder.encode(cached) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    /// Titles already shown to the user for this interest set.
    func seenTitles(for interests: [String]) -> [String] {
        guard let cached = load(), cached.interestsKey == Self.key(for: interests) else { return [] }
        return cached.seenTitles ?? []
    }

    /// Mark titles as shown (refresh pushes them behind unseen ones). Does
    /// NOT touch `fetchedAt` — seen-state is display rotation, not freshness.
    func markSeen(_ titles: [String], interests: [String]) {
        guard var cached = load(), cached.interestsKey == Self.key(for: interests) else { return }
        var seen = cached.seenTitles ?? []
        for t in titles where !seen.contains(t) { seen.append(t) }
        // Bounded — it only needs to cover one day's pool.
        if seen.count > 100 { seen.removeFirst(seen.count - 100) }
        cached.seenTitles = seen
        guard let data = try? encoder.encode(cached) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func load() -> Cached? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(Cached.self, from: data)
    }
}
