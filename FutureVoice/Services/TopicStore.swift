import Foundation

/// On-disk cache for the persona-grounded topic suggestions. The picker reads
/// from here on every open — only the explicit Refresh button (or a persona
/// change) triggers a fresh Gemini call. Avoids burning a generation per tap.
final class TopicStore {
    static let shared = TopicStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "topics.json") {
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

    func load() -> [SuggestedTopic] {
        guard let data = try? Data(contentsOf: fileURL),
              let topics = try? decoder.decode([SuggestedTopic].self, from: data) else {
            return []
        }
        return topics
    }

    func save(_ topics: [SuggestedTopic]) {
        guard let data = try? encoder.encode(topics) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
