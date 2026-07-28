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

    // MARK: - Misheard-turn exclusion

    /// The user flagged a turn as misheard by speech-to-text: exclude it from
    /// every deterministic metric, drop the grammar slips quoted from it,
    /// rescale the stored grammar score to the remaining evidence, and delete
    /// the drill cards minted from the turn. Returns the updated session.
    @discardableResult
    func excludeTurnFromScoring(sessionId: UUID, turnId: UUID) -> Session? {
        guard var session = load().first(where: { $0.id == sessionId }),
              let idx = session.turns.firstIndex(where: { $0.id == turnId }),
              session.turns[idx].role == .user,
              !session.turns[idx].excludedFromScoring else { return nil }

        session.turns[idx].excludedFromScoring = true
        let transcriptKey = Self.normalizedForMatch(session.turns[idx].transcript)

        if var summary = session.summary {
            let before = summary.grammarIssues.count
            summary.grammarIssues.removeAll { issue in
                let needle = Self.normalizedForMatch(issue.quote)
                return !needle.isEmpty && transcriptKey.contains(needle)
            }
            let removed = before - summary.grammarIssues.count
            // Rescale the grammar score deterministically: the deduction from
            // 100 shrinks in proportion to the slips that survived. Removing
            // the only slip returns the score to 100.
            if removed > 0, before > 0, var card = summary.scorecard {
                let deduction = Double(100 - card.grammar.score)
                let remaining = Double(summary.grammarIssues.count) / Double(before)
                card.grammar.score = min(100, 100 - Int((deduction * remaining).rounded()))
                summary.scorecard = card
            }
            session.summary = summary
        }

        save(session)
        DrillStore.shared.deleteForTurn(turnId)
        return session
    }

    /// Resolve a grammar-review slip back to its source turn and exclude that
    /// turn (which also removes the slip and rescales the score). When the
    /// quote can't be traced to a turn, just the slip is dropped.
    @discardableResult
    func excludeMishearing(sessionId: UUID, issueId: UUID) -> Session? {
        guard let session = load().first(where: { $0.id == sessionId }),
              let issue = session.summary?.grammarIssues.first(where: { $0.id == issueId })
        else { return nil }

        let needle = Self.normalizedForMatch(issue.quote)
        if !needle.isEmpty,
           let turn = session.turns.first(where: {
               $0.role == .user && Self.normalizedForMatch($0.transcript).contains(needle)
           }) {
            return excludeTurnFromScoring(sessionId: sessionId, turnId: turn.id)
        }

        // No traceable turn — remove the slip alone, with the same rescale.
        var updated = session
        guard var summary = updated.summary else { return nil }
        let before = summary.grammarIssues.count
        summary.grammarIssues.removeAll { $0.id == issueId }
        if before > 0, var card = summary.scorecard {
            let deduction = Double(100 - card.grammar.score)
            let remaining = Double(summary.grammarIssues.count) / Double(before)
            card.grammar.score = min(100, 100 - Int((deduction * remaining).rounded()))
            summary.scorecard = card
        }
        updated.summary = summary
        save(updated)
        return updated
    }

    /// Same normalization the hallucination guard and drill ingestion use, so
    /// a slip quote reliably finds the turn it was lifted from.
    static func normalizedForMatch(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func rank(_ s: Session) -> Date { s.endedAt ?? s.startedAt }

    private func write(_ sessions: [Session]) {
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
