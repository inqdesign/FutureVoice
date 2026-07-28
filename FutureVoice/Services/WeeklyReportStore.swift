import Foundation

/// JSON-on-disk store for generated weekly reports, mirroring SessionStore /
/// ShadowAttemptStore. Reports are never edited in place; the one exception
/// is `delete(id:)`, used to VOID an assessment whose evidence the user has
/// since repudiated (misheard-turn exclusion) so it can be re-run.
///
/// Phase 2 should migrate this to Supabase too so the trend chart survives
/// reinstall; for the first TestFlight we keep it local.
final class WeeklyReportStore {
    static let shared = WeeklyReportStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "weekly-reports.json") {
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

    func load() -> [WeeklyReport] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let list = try? decoder.decode([WeeklyReport].self, from: data)
        else { return [] }
        return list.sorted { $0.periodEnd > $1.periodEnd }
    }

    func latest() -> WeeklyReport? { load().first }

    func save(_ report: WeeklyReport) {
        var all = load()
        all.removeAll { $0.id == report.id }
        all.append(report)
        write(all)
    }

    /// Void one assessment — only for evidence-changed re-runs, never pruning.
    func delete(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        write(all)
    }

    private func write(_ list: [WeeklyReport]) {
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
