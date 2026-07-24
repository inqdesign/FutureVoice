import Foundation

/// Local persistence for ended sessions. JSON-on-disk in the app's Documents
/// directory — deliberately lightweight for Phase 1. Phase 2 will move sessions
/// to Supabase with a SwiftData cache.
///
/// `load()` is called from every tab's onAppear (dashboards, stats, vocab
/// backfill — often several times per appear), and decoding the full archive
/// with all turns on the main thread visibly delayed tab switches as history
/// grew. The decoded array is therefore cached in memory: the file is read
/// once per launch and after each write the cache is updated in place. The
/// lock keeps the cache safe for the background stat readers
/// (`PracticeStats.snapshot` now runs off-main).
final class SessionStore {
    static let shared = SessionStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()
    private var cache: [Session]?

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

    /// All sessions, newest-ended-first. Sessions are value types, so callers
    /// can't mutate the cache through the returned array.
    func load() -> [Session] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let sessions = loadFromDisk()
        cache = sessions
        return sessions
    }

    /// Inserts or overwrites by `session.id`.
    func save(_ session: Session) {
        lock.lock(); defer { lock.unlock() }
        var all = cache ?? loadFromDisk()
        all.removeAll { $0.id == session.id }
        all.append(session)
        all.sort { rank($0) > rank($1) }
        cache = all
        write(all)
    }

    func delete(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var all = cache ?? loadFromDisk()
        all.removeAll { $0.id == id }
        cache = all
        write(all)
    }

    private func loadFromDisk() -> [Session] {
        guard let data = try? Data(contentsOf: fileURL),
              let sessions = try? decoder.decode([Session].self, from: data) else {
            return []
        }
        return sessions.sorted { rank($0) > rank($1) }
    }

    private func rank(_ s: Session) -> Date { s.endedAt ?? s.startedAt }

    private func write(_ sessions: [Session]) {
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
