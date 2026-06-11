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
        let cached = Cached(interestsKey: Self.key(for: interests), fetchedAt: now, topics: topics)
        guard let data = try? encoder.encode(cached) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
