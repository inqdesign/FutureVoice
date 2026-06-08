import Foundation

/// JSON-on-disk store for saved Watch-mode dialogues so the user can replay
/// past scenarios with each counterpart instead of regenerating every time.
/// Same pattern as `SessionStore` / `DrillStore` / `CounterpartStore`.
final class WatchDialogueStore {
    static let shared = WatchDialogueStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "watch-dialogues.json") {
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

    func load() -> [WatchDialogue] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? decoder.decode([WatchDialogue].self, from: data) else {
            return []
        }
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ dialogue: WatchDialogue) {
        var all = load()
        all.removeAll { $0.id == dialogue.id }
        all.append(dialogue)
        write(all)
    }

    func delete(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        write(all)
    }

    /// Wipe dialogues belonging to a deleted counterpart — keeps the store
    /// tidy when a person is removed.
    func deleteAll(forCounterpart counterpartId: UUID) {
        var all = load()
        all.removeAll { $0.counterpartId == counterpartId }
        write(all)
    }

    private func write(_ list: [WatchDialogue]) {
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
