import CryptoKit
import Foundation

/// On-disk cache for TTS audio keyed by `(voiceId, text)` content hash, so
/// repeating the same SRS drill phrase doesn't re-bill synthesis each time.
/// Files live under `Documents/PhraseAudio/{sha256}.mp3`. Separate from
/// `TurnAudioStore` because the lookup key here is content-addressed rather
/// than tied to a specific `Turn.id`.
///
/// ## Re-recording your voice does NOT throw the old audio away
///
/// The key includes the voice id, so a re-clone used to miss on
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
    /// Delete every cached synthesis, and NOTHING else.
    ///
    /// Scoped hard to `Documents/PhraseAudio` on purpose. Learning records —
    /// sessions, drills, vocabulary, books, streak — are plain JSON in
    /// `Documents` with no server copy, so "reinstall the app to clear the
    /// audio cache" destroys everything the learner has ever done. This is the
    /// only safe way to force a re-synthesis, which is why it exists.
    ///
    /// Costs real money to undo: every line played after this re-bills once.
    func clearCachedAudio() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files { try? fm.removeItem(at: url) }
    }

    func clearOwnVoiceLineage() {
        ownVoiceLineage = []
        UserDefaults.standard.removeObject(forKey: lineageKey)
    }

    /// Keys to try, in order: the voice that actually speaks first, then the
    /// user's older clones (only when the asked-for voice IS the user's own).
    ///
    /// A preset SLOT resolves to the target language's own voice
    /// (`VoicePreset.speaking`, 2026-09-28), and new lines are saved under that
    /// voice. Lines made before then were saved under the slot id in the old
    /// English voice; they stay reachable as the fallback, for the same reason
    /// the lineage exists — a scene already watched replays as it was instead
    /// of re-billing. `allowLineage: false` turns this off too, for anything
    /// that must be heard in the voice speaking NOW (a preview, a call).
    private func candidateVoiceIds(_ voiceId: String, allowLineage: Bool) -> [String] {
        let speaking = VoicePreset.speaking(voiceId)
        guard allowLineage else { return [speaking] }
        if speaking != voiceId { return [speaking, voiceId] }
        guard ownVoiceLineage.contains(voiceId) else { return [voiceId] }
        return [voiceId] + ownVoiceLineage.filter { $0 != voiceId }
    }

    /// The key whose audio actually exists on disk — audio AND timings are both
    /// read from this one key, so karaoke can never end up aligned to a
    /// different take than the one playing.
    ///
    /// `anySpeed` also accepts a take made at another speech speed — for
    /// listening back to lines already made (a playlist), where the line as it
    /// was heard beats a gap. Never for anything that is about to synthesize:
    /// there a miss at the current speed is the right answer.
    private func resolvedKey(text: String, voiceId: String, allowLineage: Bool,
                             anySpeed: Bool = false) -> String? {
        let current = SpeechSpeed.current.cacheTag
        let tags = anySpeed
            ? [current] + SpeechSpeed.allCases.map(\.cacheTag).filter { $0 != current }
            : [current]
        for tag in tags {
            for candidate in candidateVoiceIds(voiceId, allowLineage: allowLineage) {
                let k = rawKey(text: text, voiceId: candidate, speedTag: tag)
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(k).mp3").path) {
                    return k
                }
            }
        }
        return nil
    }

    // MARK: - Read

    /// - Parameter allowLineage: pass `false` where a single stretch of speech
    ///   must sound like ONE take (the live call) — there, an older clone's
    ///   recording mid-conversation would read as the voice changing partway.
    ///   Review surfaces leave it on: reusing the old file beats re-billing.
    func url(text: String, voiceId: String, allowLineage: Bool = true,
             anySpeed: Bool = false) -> URL? {
        guard let k = resolvedKey(text: text, voiceId: voiceId, allowLineage: allowLineage,
                                  anySpeed: anySpeed) else {
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

    /// Drop ONE cached line — its audio and the word timings that describe it,
    /// which must never outlive the take they were measured on.
    ///
    /// The store's rule is that produced audio is kept (see the header), and
    /// this does not weaken it: the caller is `FreeTalkOpeners`, re-making the
    /// handful of lines that OPEN a call after the speaking speed moved. Those
    /// are the one place a stale take is audible against the live voice right
    /// after it. Anything that wants to clear more than a named line belongs in
    /// `clearCachedAudio`, behind the learner's own button.
    func removeAudio(text: String, voiceId: String) {
        let k = key(text: text, voiceId: voiceId)
        for name in ["\(k).mp3", "\(k).timings.json"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: - Scene lines, found by what was PLAYED (2026-10-19)
    //
    // A file's name is a hash of the voice that made it, so a lookup has to
    // re-derive that voice — and the voice behind a preset slot or a
    // Find-people person has changed twice (2026-09-28, 2026-10-12). The
    // listening playlist then lost every scene whose lines sat under the old
    // id, with the audio still on disk. So Watch writes down which file each
    // line actually played from, by speaker side and text, and the playlist
    // reads that before it re-derives anything. Local only, beside the files
    // it names (a cache clear takes both).

    private lazy var sceneLines: [String: String] = {
        guard let data = try? Data(contentsOf: sceneLinesURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }()
    private let sceneLinesLock = NSLock()
    private var sceneLinesURL: URL { dir.appendingPathComponent("scene-lines.json") }

    private func sceneLineId(text: String, isOther: Bool) -> String {
        (isOther ? "other\n" : "me\n") + text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Watch, once a line has played: remember the file it came from.
    func rememberSceneLine(text: String, voiceId: String, isOther: Bool) {
        guard let k = resolvedKey(text: text, voiceId: voiceId, allowLineage: true) else { return }
        let id = sceneLineId(text: text, isOther: isOther)
        sceneLinesLock.lock(); defer { sceneLinesLock.unlock() }
        guard sceneLines[id] != k else { return }
        sceneLines[id] = k
        if let data = try? JSONEncoder().encode(sceneLines) {
            try? data.write(to: sceneLinesURL, options: [.atomic])
        }
    }

    /// The file a scene line plays from, for listening back: the voice it is
    /// asked for (any speed), then the file Watch played it from, then any of
    /// `fallbackVoices` — the ids that voice went by before. Never synthesizes.
    func sceneLineKey(text: String, voiceId: String, isOther: Bool,
                      fallbackVoices: [String]) -> String? {
        if let k = resolvedKey(text: text, voiceId: voiceId, allowLineage: true, anySpeed: true) {
            return k
        }
        sceneLinesLock.lock()
        let played = sceneLines[sceneLineId(text: text, isOther: isOther)]
        sceneLinesLock.unlock()
        if let played, exists(played) { return played }
        for tag in SpeechSpeed.allCases.map(\.cacheTag) {
            for voice in fallbackVoices {
                let k = rawKey(text: text, voiceId: voice, speedTag: tag)
                if exists(k) { return k }
            }
        }
        return nil
    }

    func url(forKey key: String) -> URL { dir.appendingPathComponent("\(key).mp3") }

    func timings(forKey key: String) -> [WordTiming]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(key).timings.json")) else {
            return nil
        }
        return try? JSONDecoder().decode([WordTiming].self, from: data)
    }

    private func exists(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(key).mp3").path)
    }

    // MARK: - Word timings

    func timings(text: String, voiceId: String, allowLineage: Bool = true,
                 anySpeed: Bool = false) -> [WordTiming]? {
        guard let k = resolvedKey(text: text, voiceId: voiceId, allowLineage: allowLineage,
                                  anySpeed: anySpeed) else {
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

    /// The speech SPEED is part of the key (2026-09-23): a line at 0.8 is a
    /// different recording from the same line at Normal, and its word timings
    /// are different too — one key for both would play one speed's take under
    /// the other's karaoke. **Normal's tag is empty**, so every line cached
    /// before the setting existed — synthesized with no speed at all — is still
    /// found and still plays. That is this store's rule (see the header): audio
    /// already made is never orphaned and never re-billed. A learner who never
    /// touches the setting hears the old cache as it was and new lines at 0.9;
    /// a cache clear to "fix" that was built and reverted the same day
    /// (user decision: what is already produced stays).
    private func key(text: String, voiceId: String) -> String {
        rawKey(text: text, voiceId: VoicePreset.speaking(voiceId))
    }

    /// The key for exactly this voice id, with no preset resolution — only the
    /// lookup's fallback to a slot's pre-2026-09-28 files needs it.
    private func rawKey(text: String, voiceId: String,
                        speedTag: String = SpeechSpeed.current.cacheTag) -> String {
        let normalized = "\(voiceId)\n\(speedTag)\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
