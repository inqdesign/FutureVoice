import Foundation

/// JSON-on-disk store for saved shadow attempts. Lets the user revisit past
/// attempts, hear their old recordings, compare scores over time. Same
/// pattern as the other stores — Phase 2 will move to Supabase.
final class ShadowAttemptStore: LanguageScopedStore {
    static let shared = ShadowAttemptStore()

    private var fileURL: URL
    private let filename: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "shadow-attempts.json") {
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

    // Attempt records are language-scoped; the recordings they name stay in
    // the global Documents/Recordings/ (audio blobs are per-user assets,
    // like PhraseAudio/TurnAudio — the JSON provides the language split).
    func languageScopeDidChange() {
        fileURL = LanguageScope.activeDirectory.appendingPathComponent(filename)
    }

    func load() -> [ShadowAttempt] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? decoder.decode([ShadowAttempt].self, from: data) else {
            return []
        }
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ attempt: ShadowAttempt) {
        var all = load()
        all.removeAll { $0.id == attempt.id }
        all.append(attempt)
        write(all)
    }

    func delete(id: UUID) {
        var all = load()
        guard let toDelete = all.first(where: { $0.id == id }) else { return }
        // Best-effort cleanup of the audio file too.
        if let filename = toDelete.recordingFilename {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Recordings", isDirectory: true)
            let url = dir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }
        all.removeAll { $0.id == id }
        write(all)
    }

    private func write(_ list: [ShadowAttempt]) {
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
