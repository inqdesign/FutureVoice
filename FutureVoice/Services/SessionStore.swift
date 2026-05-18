import Foundation

/// Local persistence for ended sessions. JSON-on-disk in the app's Documents
/// directory — deliberately lightweight for Phase 1. Phase 2 will move sessions
/// to Supabase with a SwiftData cache.
final class SessionStore {
    static let shared = SessionStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "sessions.json") {
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

    /// All sessions, newest-ended-first.
    func load() -> [Session] {
        guard let data = try? Data(contentsOf: fileURL),
              let sessions = try? decoder.decode([Session].self, from: data) else {
            return []
        }
        return sessions.sorted { rank($0) > rank($1) }
    }

    /// Inserts or overwrites by `session.id`.
    func save(_ session: Session) {
        var all = load()
        all.removeAll { $0.id == session.id }
        all.append(session)
        write(all)
    }

    func delete(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        write(all)
    }

    private func rank(_ s: Session) -> Date { s.endedAt ?? s.startedAt }

    private func write(_ sessions: [Session]) {
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
