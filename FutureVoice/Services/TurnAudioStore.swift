import Foundation

/// On-disk cache for fluent-self TTS audio so the user can shadow past lines
/// without re-spending ElevenLabs credits. Files live under
/// `Documents/TurnAudio/{turnId}.mp3`. Phase 2 will move this behind a
/// signed Supabase Storage URL.
final class TurnAudioStore {
    static let shared = TurnAudioStore()

    private let dir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.dir = docs.appendingPathComponent("TurnAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Persist MP3 data for a fluent-self turn. Returns the file URL.
    @discardableResult
    func save(_ data: Data, turnId: UUID, timings: [WordTiming] = []) -> URL? {
        let url = dir.appendingPathComponent("\(turnId.uuidString).mp3")
        do {
            try data.write(to: url, options: [.atomic])
            if !timings.isEmpty {
                saveTimings(timings, for: turnId)
            }
            return url
        } catch {
            return nil
        }
    }

    /// File URL if audio for this turn has been cached.
    func url(for turnId: UUID) -> URL? {
        let url = dir.appendingPathComponent("\(turnId.uuidString).mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Load cached audio bytes for a turn, if any.
    func data(for turnId: UUID) -> Data? {
        guard let url = url(for: turnId) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Remove cached audio + timings for a turn — session-deletion cleanup.
    func delete(turnId: UUID) {
        try? FileManager.default.removeItem(
            at: dir.appendingPathComponent("\(turnId.uuidString).mp3"))
        try? FileManager.default.removeItem(at: timingsURL(for: turnId))
    }

    // MARK: - Word timings

    func timings(for turnId: UUID) -> [WordTiming]? {
        let url = timingsURL(for: turnId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([WordTiming].self, from: data)
    }

    func saveTimings(_ timings: [WordTiming], for turnId: UUID) {
        let url = timingsURL(for: turnId)
        guard let data = try? JSONEncoder().encode(timings) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func timingsURL(for turnId: UUID) -> URL {
        dir.appendingPathComponent("\(turnId.uuidString).timings.json")
    }
}
