import Foundation

/// On-disk persistence for the user's saved-line archive
/// (`Documents/saved_lines.json`). Mirrors the other JSON stores.
final class SavedLineStore: LanguageScopedStore {
    static let shared = SavedLineStore()

    private var fileURL: URL
    private let filename: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "saved_lines.json") {
        self.filename = filename
        self.fileURL = LanguageScope.activeDirectory.appendingPathComponent(filename)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    func languageScopeDidChange() {
        fileURL = LanguageScope.activeDirectory.appendingPathComponent(filename)
    }

    /// Newest-saved-first.
    func load() -> [SavedLine] {
        guard let data = try? Data(contentsOf: fileURL),
              let lines = try? decoder.decode([SavedLine].self, from: data) else {
            return []
        }
        return lines.sorted { $0.savedAt > $1.savedAt }
    }

    func save(_ line: SavedLine) {
        var all = load()
        all.removeAll { $0.id == line.id }
        all.append(line)
        write(all)
    }

    func delete(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        write(all)
    }

    private func write(_ lines: [SavedLine]) {
        guard let data = try? encoder.encode(lines) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
