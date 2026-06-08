import Foundation

/// JSON-on-disk store for the user's saved counterparts (people from real
/// life used in Watch mode dialogues). Same pattern as `SessionStore` /
/// `DrillStore` — Phase 2 moves to Supabase.
final class CounterpartStore {
    static let shared = CounterpartStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "counterparts.json") {
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

    func load() -> [Counterpart] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? decoder.decode([Counterpart].self, from: data) else {
            return []
        }
        return list.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ counterpart: Counterpart) {
        var all = load()
        all.removeAll { $0.id == counterpart.id }
        var c = counterpart
        c.updatedAt = Date()
        all.append(c)
        write(all)
    }

    func delete(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        write(all)
    }

    private func write(_ list: [Counterpart]) {
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
