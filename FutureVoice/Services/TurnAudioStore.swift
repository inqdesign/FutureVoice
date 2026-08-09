import Foundation

/// On-disk cache for turn audio so the user can shadow past lines without
/// re-spending ElevenLabs credits. Files live under
/// `Documents/TurnAudio/{turnId}.{ext}`. Phase 2 will move this behind a
/// signed Supabase Storage URL.
///
/// **The extension is load-bearing.** Fluent-self TTS is MP3; the user's own
/// recorded turn is AAC/M4A. `AVAudioFile(forReading:)` — the reader behind
/// `AudioLoudness.aacADTS16kMono` / `wav16kMono`, i.e. the Gemini audio
/// attachment — opens through ExtAudioFile, which honors the URL's extension
/// as a type hint and FAILS outright on M4A bytes named `.mp3`. Storing the
/// user's turn under `.mp3` is what silently killed the audio attachment (and
/// with it Gemini's verbatim transcript) on most turns. `AVAudioPlayer` sniffs
/// content and never noticed, which is why listen-back always worked.
final class TurnAudioStore {
    static let shared = TurnAudioStore()

    /// Extensions a cached turn can live under, newest convention first.
    /// `url(for:)` probes them in order so turns saved by earlier builds
    /// (everything as `.mp3`) still resolve.
    private static let knownExtensions = ["mp3", "m4a"]

    private let dir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.dir = docs.appendingPathComponent("TurnAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Persist audio for a turn. Returns the file URL.
    /// - Parameter fileExtension: MUST match the actual container — `mp3` for
    ///   ElevenLabs TTS, `m4a` for the user's own AAC capture. See the type
    ///   note on the class.
    @discardableResult
    func save(_ data: Data, turnId: UUID, timings: [WordTiming] = [],
              fileExtension: String = "mp3") -> URL? {
        let url = dir.appendingPathComponent("\(turnId.uuidString).\(fileExtension)")
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

    /// File URL if audio for this turn has been cached, under any known
    /// extension.
    func url(for turnId: UUID) -> URL? {
        for ext in Self.knownExtensions {
            let url = dir.appendingPathComponent("\(turnId.uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Load cached audio bytes for a turn, if any.
    func data(for turnId: UUID) -> Data? {
        guard let url = url(for: turnId) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Remove cached audio + timings for a turn — session-deletion cleanup.
    func delete(turnId: UUID) {
        for ext in Self.knownExtensions {
            try? FileManager.default.removeItem(
                at: dir.appendingPathComponent("\(turnId.uuidString).\(ext)"))
        }
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
