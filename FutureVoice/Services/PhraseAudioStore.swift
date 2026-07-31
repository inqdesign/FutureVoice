import CryptoKit
import Foundation

/// On-disk cache for TTS audio keyed by `(voiceId, text)` content hash, so
/// repeating the same SRS drill phrase doesn't re-bill ElevenLabs each time.
/// Files live under `Documents/PhraseAudio/{sha256}.mp3`. Separate from
/// `TurnAudioStore` because the lookup key here is content-addressed rather
/// than tied to a specific `Turn.id`.
///
/// ## Re-recording your voice does NOT throw the old audio away
///
/// The key includes the ElevenLabs voice id, so a re-clone used to miss on
/// EVERY cached line — the whole library (scenes, drills, vocabulary,
/// expressions, shadow lines) silently re-synthesized itself one tap at a
/// time, re-billing audio the user already owned. The old files were still
/// sitting on disk, just unreachable, and the old clone had been deleted
/// server-side so they could never be produced again.
///
/// So the store remembers the user's OWN clone ids (`ownVoiceLineage`,
/// newest first). A lookup for the current clone falls back to earlier ones
/// in that lineage before declaring a miss: already-synthesized lines keep
/// playing exactly as they were, and only genuinely NEW text costs anything.
/// Counterpart preset voices are never in the lineage, so they can't be
/// substituted for each other.
final class PhraseAudioStore {
    static let shared = PhraseAudioStore()

    private let dir: URL
    private let lineageKey = "futurevoice.ownVoiceLineage"
    /// How many past clones stay reachable. A user who re-records repeatedly
    /// still keeps their oldest material playable, without an unbounded list.
    private static let maxLineage = 6

    /// The user's own clone ids, newest first. `[0]` is the live one.
    private(set) var ownVoiceLineage: [String]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.dir = docs.appendingPathComponent("PhraseAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.ownVoiceLineage = UserDefaults.standard.stringArray(forKey: lineageKey) ?? []
    }

    // MARK: - Own-voice lineage

    /// Record the user's current clone id. Called whenever `voiceCloneId`
    /// changes — the previous id stays in the list so its audio keeps
    /// resolving.
    func registerOwnVoice(_ voiceId: String?) {
        guard let voiceId, !voiceId.isEmpty else { return }
        guard ownVoiceLineage.first != voiceId else { return }
        var updated = ownVoiceLineage.filter { $0 != voiceId }
        updated.insert(voiceId, at: 0)
        if updated.count > Self.maxLineage { updated.removeLast(updated.count - Self.maxLineage) }
        ownVoiceLineage = updated
        UserDefaults.standard.set(updated, forKey: lineageKey)
    }

    /// Account deletion / local wipe — the next user inherits no lineage.
    func clearOwnVoiceLineage() {
        ownVoiceLineage = []
        UserDefaults.standard.removeObject(forKey: lineageKey)
    }

    /// Keys to try, in order: the asked-for voice first, then the user's older
    /// clones (only when the asked-for voice IS the user's own).
    private func candidateVoiceIds(_ voiceId: String, allowLineage: Bool) -> [String] {
        guard allowLineage, ownVoiceLineage.contains(voiceId) else { return [voiceId] }
        return [voiceId] + ownVoiceLineage.filter { $0 != voiceId }
    }

    /// The key whose audio actually exists on disk — audio AND timings are both
    /// read from this one key, so karaoke can never end up aligned to a
    /// different take than the one playing.
    private func resolvedKey(text: String, voiceId: String, allowLineage: Bool) -> String? {
        for candidate in candidateVoiceIds(voiceId, allowLineage: allowLineage) {
            let k = key(text: text, voiceId: candidate)
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(k).mp3").path) {
                return k
            }
        }
        return nil
    }

    // MARK: - Read

    /// - Parameter allowLineage: pass `false` where a single stretch of speech
    ///   must sound like ONE take (the live call) — there, an older clone's
    ///   recording mid-conversation would read as the voice changing partway.
    ///   Review surfaces leave it on: reusing the old file beats re-billing.
    func url(text: String, voiceId: String, allowLineage: Bool = true) -> URL? {
        guard let k = resolvedKey(text: text, voiceId: voiceId, allowLineage: allowLineage) else {
            return nil
        }
        return dir.appendingPathComponent("\(k).mp3")
    }

    func data(text: String, voiceId: String, allowLineage: Bool = true) -> Data? {
        guard let url = url(text: text, voiceId: voiceId, allowLineage: allowLineage) else {
            return nil
        }
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

    func timings(text: String, voiceId: String, allowLineage: Bool = true) -> [WordTiming]? {
        guard let k = resolvedKey(text: text, voiceId: voiceId, allowLineage: allowLineage) else {
            return nil
        }
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
