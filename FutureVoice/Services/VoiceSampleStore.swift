import Foundation

/// Persists the RAW voice-clone sample recording (Documents/voice_sample.wav)
/// so the user can regenerate their clone later without recording again — e.g.
/// after switching target language, or if a clone got deleted. We keep the
/// un-normalized take; loudness normalization happens at upload time so a
/// future re-clone always starts from the original capture.
final class VoiceSampleStore {
    static let shared = VoiceSampleStore()

    private let fileURL: URL

    init(filename: String = "voice_sample.wav") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent(filename)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
    var url: URL? { exists ? fileURL : nil }

    /// Copy a freshly recorded sample into the stable location, replacing any
    /// previous one. Returns the stored URL, or nil on failure.
    @discardableResult
    func save(from sourceURL: URL) -> URL? {
        try? FileManager.default.removeItem(at: fileURL)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
