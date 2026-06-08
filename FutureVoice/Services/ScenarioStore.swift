import Foundation

/// JSON-on-disk store for the user's Talk-mode scenarios. Replaces the old
/// `TopicStore` (auto-suggested topics) — those felt stale because they only
/// regenerated on explicit refresh. A user-curated library is fresher because
/// it reflects what they ACTUALLY practice with.
final class ScenarioStore {
    static let shared = ScenarioStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "scenarios.json") {
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

    func load() -> [Scenario] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? decoder.decode([Scenario].self, from: data) else {
            return []
        }
        // Order: most-recently-used at top, falling back to createdAt.
        return list.sorted {
            ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt)
        }
    }

    func save(_ scenario: Scenario) {
        var all = load()
        all.removeAll { $0.id == scenario.id }
        all.append(scenario)
        write(all)
    }

    func delete(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        write(all)
    }

    func markUsed(id: UUID, at date: Date = Date()) {
        var all = load()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return }
        all[idx].lastUsedAt = date
        write(all)
    }

    private func write(_ list: [Scenario]) {
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
