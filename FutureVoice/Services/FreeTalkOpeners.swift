import Foundation

/// Rotating pool of Free-talk greeting lines (`Documents/freetalk_openers.json`).
///
/// A free talk opens with more or less the same kind of greeting every time,
/// so paying a Gemini call per session to write one (and an ElevenLabs call
/// to voice a line that's never repeated) is waste. Instead ONE Gemini call
/// writes a small pool of openers; sessions rotate through it, and because
/// the texts repeat verbatim, `PhraseAudioStore`'s content cache makes every
/// TTS after each line's first play free.
///
/// Topic/scenario/news openers stay dynamic — this pool is only for the
/// no-topic free talk. The pool is keyed to language + persona name and
/// regenerates when either changes.
final class FreeTalkOpeners {
    static let shared = FreeTalkOpeners()

    struct Pool: Codable {
        var key: String
        var lines: [String]
        var cursor: Int
        var generatedAt: Date
    }

    private struct Payload: Decodable {
        let openers: [String]
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "freetalk_openers.json") {
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

    private static func key(language: String, personaName: String?) -> String {
        "\(language)|\(personaName ?? "")"
    }

    /// The next greeting in rotation, or nil when no valid pool exists yet
    /// (caller falls back to a generated opener). Advances and persists the
    /// cursor so consecutive free talks don't repeat the same line.
    func next(language: String, personaName: String?) -> String? {
        guard var pool = load(),
              pool.key == Self.key(language: language, personaName: personaName),
              !pool.lines.isEmpty else { return nil }
        let line = pool.lines[pool.cursor % pool.lines.count]
        pool.cursor = (pool.cursor + 1) % pool.lines.count
        save(pool)
        return line
    }

    /// The line `next()` WOULD return, without consuming it. Read-only — the
    /// launcher uses this to synthesize the upcoming greeting ahead of the
    /// tap, so the call opens on cached audio instead of an ElevenLabs round
    /// trip. Must stay in sync with `next()`'s index arithmetic.
    func peek(language: String, personaName: String?) -> String? {
        guard let pool = load(),
              pool.key == Self.key(language: language, personaName: personaName),
              !pool.lines.isEmpty else { return nil }
        return pool.lines[pool.cursor % pool.lines.count]
    }

    /// Every line in the current pool (empty when none). Read-only — the
    /// launcher warms EACH line's TTS once, so any rotation position opens
    /// the call on cached audio.
    func lines(language: String, personaName: String?) -> [String] {
        guard let pool = load(),
              pool.key == Self.key(language: language, personaName: personaName),
              !pool.lines.isEmpty else { return [] }
        return pool.lines
    }

    /// Synthesize EVERY pool line's audio that isn't cached yet, so any
    /// rotation position opens a call on cached audio — no ElevenLabs round
    /// trip on the greeting. Bounded cost: one synthesis per unique line per
    /// voice, ever (the content cache makes later uses free). A failure
    /// aborts the sweep (the rest would fail the same way); the live call
    /// still falls back to on-demand TTS.
    func warmAudio(language: String, personaName: String?, voiceId: String?) async {
        guard let voiceId else { return }
        for line in lines(language: language, personaName: personaName) {
            guard !Task.isCancelled else { return }
            // `allowLineage: false` mirrors the live call's lookup — warming
            // a line the call would still consider a miss is pointless.
            guard PhraseAudioStore.shared.data(text: line, voiceId: voiceId,
                                               allowLineage: false) == nil else { continue }
            do {
                let audio = try await ElevenLabsClient.shared.synthesize(
                    voiceId: voiceId, text: line,
                    modelId: ElevenLabsClient.conversationModelId,
                    purpose: "turn")
                PhraseAudioStore.shared.save(audio, text: line, voiceId: voiceId)
            } catch {
                return
            }
        }
    }

    /// True when a valid pool exists for this language/persona. Read-only —
    /// unlike `next()` it never advances the rotation cursor.
    func hasPool(language: String, personaName: String?) -> Bool {
        guard let pool = load(),
              pool.key == Self.key(language: language, personaName: personaName),
              !pool.lines.isEmpty else { return false }
        return true
    }

    /// Fire-and-forget warm-up for the Talk launcher: generate the pool ahead
    /// of the first "Let's talk" so that call opens on a canned line instead
    /// of holding the greeting hostage to a live Gemini call (which, cold,
    /// used to be the multi-second blank screen on the first free talk).
    /// No-op when a valid pool already exists; failures stay silent — the
    /// in-call fallback path still generates on demand.
    func warmUp(language: String, personaName: String?, proficiency: CEFRLevel) async {
        guard !hasPool(language: language, personaName: personaName) else { return }
        _ = try? await generatePool(language: language, personaName: personaName,
                                    proficiency: proficiency)
    }

    /// Generate (or refresh) the pool with one Gemini call. Returns the first
    /// line in rotation so the generating session can use it directly.
    func generatePool(language: String,
                      personaName: String?,
                      proficiency: CEFRLevel) async throws -> String {
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: Self.systemPrompt(language: language, personaName: personaName,
                                      proficiency: proficiency),
            messages: [GeminiClient.Message(role: .user, content: "Write the greetings.")],
            model: .flashLite31,
            maxTokens: 1200,
            purpose: "freetalk-openers",
            idempotencyKey: "freetalk-openers:\(Self.key(language: language, personaName: personaName))"
        )
        let lines = payload.openers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else {
            throw GeminiError.jsonNotFound(raw: "empty opener pool")
        }
        save(Pool(key: Self.key(language: language, personaName: personaName),
                  lines: lines, cursor: 1, generatedAt: Date()))
        return first
    }

    private static func systemPrompt(language: String, personaName: String?,
                                     proficiency: CEFRLevel) -> String {
        let name = (personaName?.isEmpty == false) ? personaName! : "the learner"
        let languageName = LanguageCatalog.englishName(language)
        return """
        You are the learner's fluent future self opening a casual, free-form
        voice chat in \(languageName). Write 6 SHORT greeting openers (6–14 words
        each) that could start such a call on any day, at any time of day.

        Rules:
        - Warm, natural spoken \(languageName) a CEFR \(proficiency.rawValue.uppercased()) learner easily follows.
        - Each opener distinct in flavor; every one must invite a reply.
        - Address \(name) by name in AT MOST two of them.
        - No references to specific shared events, dates, news, or time of day.
        - Speakable as-is: no placeholders, brackets, or stage directions.

        Return STRICT JSON only — no prose, no code fences:
        { "openers": ["...", "..."] }
        """
    }

    // MARK: - Disk

    private func load() -> Pool? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(Pool.self, from: data)
    }

    private func save(_ pool: Pool) {
        guard let data = try? encoder.encode(pool) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
