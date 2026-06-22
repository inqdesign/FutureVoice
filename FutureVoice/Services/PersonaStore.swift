import Foundation

/// On-disk persistence for the user's avatar persona (`Documents/persona.json`).
/// Mirrors `SessionStore` / `DrillStore` pattern — Phase 2 moves to Supabase.
///
/// `load()` returns nil iff the user has never completed persona onboarding
/// (so RootView can route there); after the first save, even an empty persona
/// counts as "onboarded".
final class PersonaStore {
    static let shared = PersonaStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "persona.json") {
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

    func load() -> UserPersona? {
        guard let data = try? Data(contentsOf: fileURL),
              let persona = try? decoder.decode(UserPersona.self, from: data) else {
            return nil
        }
        return persona
    }

    func save(_ persona: UserPersona) {
        var p = persona
        p.updatedAt = Date()
        guard let data = try? encoder.encode(p) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func exists() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Delete the persona file so `load()` returns nil again. Used by the
    /// debug "replay onboarding" reset.
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
