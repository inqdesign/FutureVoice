import CryptoKit
import Foundation

/// On-disk cache for TTS audio keyed by `(voiceId, text)` content hash, so
/// repeating the same SRS drill phrase doesn't re-bill ElevenLabs each time.
/// Files live under `Documents/PhraseAudio/{sha256}.mp3`. Separate from
/// `TurnAudioStore` because the lookup key here is content-addressed rather
/// than tied to a specific `Turn.id`.
final class PhraseAudioStore {
    static let shared = PhraseAudioStore()

    private let dir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.dir = docs.appendingPathComponent("PhraseAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func url(text: String, voiceId: String) -> URL? {
        let url = dir.appendingPathComponent("\(key(text: text, voiceId: voiceId)).mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func data(text: String, voiceId: String) -> Data? {
        guard let url = url(text: text, voiceId: voiceId) else { return nil }
        return try? Data(contentsOf: url)
    }

    @discardableResult
    func save(_ data: Data, text: String, voiceId: String, timings: [WordTiming] = []) -> URL? {
        let k = key(text: text, voiceId: voiceId)
        let url = dir.appendingPathComponent("\(k).mp3")
        do {
            try data.write(to: url, options: [.atomic])
            if !timings.isEmpty {
                saveTimings(timings, key: k)
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Word timings

    func timings(text: String, voiceId: String) -> [WordTiming]? {
        let k = key(text: text, voiceId: voiceId)
        let url = dir.appendingPathComponent("\(k).timings.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([WordTiming].self, from: data)
    }

    private func saveTimings(_ timings: [WordTiming], key: String) {
        let url = dir.appendingPathComponent("\(key).timings.json")
        guard let data = try? JSONEncoder().encode(timings) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func key(text: String, voiceId: String) -> String {
        let normalized = "\(voiceId)\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
