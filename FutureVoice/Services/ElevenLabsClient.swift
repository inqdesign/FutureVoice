import CryptoKit
import Foundation
import Supabase

/// ElevenLabs client. As of TestFlight prep, this no longer talks to
/// ElevenLabs directly — every call goes through Supabase Edge Functions
/// (`elevenlabs-tts`, `elevenlabs-voice-clone`, `elevenlabs-voice-delete`).
/// The server-side proxy injects the real `xi-api-key`. The iOS bundle no
/// longer ships any ElevenLabs credentials.
///
/// Auth: each request carries the current Supabase user's access token in
/// the `Authorization` header. The Edge Function verifies it before
/// forwarding, so unauthenticated callers can't drain the account.
final class ElevenLabsClient {
    static let shared = ElevenLabsClient()

    private let session: URLSession
    /// Voice-clone sample uploads are megabytes, not kilobytes — they get a
    /// roomier resource timeout than the interactive calls.
    private let uploadSession: URLSession

    init(session: URLSession = .edgeFunctions,
         uploadSession: URLSession = .edgeFunctionUploads) {
        self.session = session
        self.uploadSession = uploadSession
    }

    /// Edge Function base URL = `<SUPABASE_URL>/functions/v1`. Built once
    /// from the same xcconfig values used by `SupabaseProvider`.
    private var functionsBaseURL: URL {
        guard
            let urlString = Secrets.string(for: .supabaseURL),
            let url = URL(string: urlString)
        else { fatalError("SUPABASE_URL missing") }
        return url.appendingPathComponent("/functions/v1")
    }

    /// Fetches the caller's current Supabase access token. Throws if there
    /// is no session — RootView gates the app behind sign-in so in practice
    /// this only happens if the user signs out mid-flight.
    private func accessToken() async throws -> String {
        let session = try await SupabaseProvider.shared.auth.session
        return session.accessToken
    }

    // MARK: - Voice cloning

    /// Uploads sample audio and creates a new voice clone.
    /// - Parameters:
    ///   - name: display name for the voice (e.g. "Eunggyu — Future Self")
    ///   - sampleAudioURLs: one or more WAV/MP3 files. Total 30–60s recommended.
    ///   - description: optional human description
    ///   - removeBackgroundNoise: run ElevenLabs' denoiser on the sample
    ///     before cloning. Only pass `true` for a genuinely noisy take — see
    ///     the call site in `AppState.regenerateVoiceClone`.
    /// - Returns: ElevenLabs `voice_id`.
    func cloneVoice(name: String, sampleAudioURLs: [URL], description: String? = nil,
                    removeBackgroundNoise: Bool) async throws -> String {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-voice-clone")
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendFormField(name: "name", value: name, boundary: boundary)
        if let description {
            body.appendFormField(name: "description", value: description, boundary: boundary)
        }
        // Denoise handles AC hum, distant traffic, keyboard taps — a clear win
        // on a noisy take. But it is NOT free on a clean one: the denoiser
        // also shaves breath, sibilance and high-end texture, i.e. the cues
        // that make a clone recognizable as a specific person. This used to be
        // hardcoded `true`, which meant the quiet-spot finder's whole job was
        // to produce a clean sample that we then degraded anyway. Now the
        // caller decides from the measured SNR.
        body.appendFormField(name: "remove_background_noise",
                             value: removeBackgroundNoise ? "true" : "false", boundary: boundary)
        for url in sampleAudioURLs {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            let mime = filename.lowercased().hasSuffix(".mp3") ? "audio/mpeg" : "audio/wav"
            body.appendFileField(name: "files", filename: filename, mime: mime, data: data, boundary: boundary)
        }
        body.appendString("--\(boundary)--\r\n")

        let (data, response) = try await uploadSession.uploadWithRetry(for: request, from: body)
        try Self.validate(response: response, data: data)

        struct AddVoiceResponse: Decodable { let voice_id: String }
        let decoded = try JSONDecoder().decode(AddVoiceResponse.self, from: data)
        return decoded.voice_id
    }

    /// Deletes a custom voice from the ElevenLabs account. Used to clean up
    /// the previous clone after a successful re-record so the user doesn't
    /// hit their plan's voice slot ceiling.
    func deleteVoice(voiceId: String) async throws {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-voice-delete")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["voice_id": voiceId])

        let (data, response) = try await session.dataWithRetry(for: request)
        try Self.validate(response: response, data: data)
    }

    /// Renames an EXISTING clone upstream. The name is otherwise fixed at
    /// creation time, so without this a rename would only show up after the
    /// user's next re-record. Free — no credits are charged.
    func renameVoice(voiceId: String, name: String) async throws {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-voice-rename")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["voice_id": voiceId, "name": name])

        let (data, response) = try await session.dataWithRetry(for: request)
        try Self.validate(response: response, data: data)
    }

    // MARK: - Voice remixing (accent picker)

    /// One remix candidate: a voice that exists upstream only transiently
    /// until saved. `id` is the ElevenLabs `generated_voice_id`.
    struct RemixPreview: Identifiable {
        let id: String
        let audio: Data
    }

    /// Generates accent-remix previews of an existing clone. Same person,
    /// instructed accent — see `VoiceAccentCatalog` for the descriptions.
    /// `text` is what the previews speak (upstream wants 100–1000 chars).
    func remixVoicePreviews(voiceId: String, voiceDescription: String,
                            text: String) async throws -> [RemixPreview] {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-voice-remix")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "voice_id": voiceId,
            "voice_description": voiceDescription,
            "text": text,
        ])
        // Preview generation runs tens of seconds upstream and returns a few
        // MB of base64 audio — the roomier upload session, not the 60s one.
        let (data, response) = try await uploadSession.dataWithRetry(for: request)
        try Self.validate(response: response, data: data)

        struct Preview: Decodable {
            let generated_voice_id: String
            let audio_base_64: String
        }
        struct Resp: Decodable { let previews: [Preview] }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.previews.compactMap { p in
            guard let audio = Data(base64Encoded: p.audio_base_64) else { return nil }
            return RemixPreview(id: p.generated_voice_id, audio: audio)
        }
    }

    /// Promotes the picked preview into a permanent voice and returns its
    /// voice_id. The edge function mirrors the new id into `voice_clones`,
    /// so the swap-and-delete machinery treats it exactly like a re-record.
    func saveRemixedVoice(generatedVoiceId: String, name: String,
                          voiceDescription: String) async throws -> String {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-voice-remix")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "generated_voice_id": generatedVoiceId,
            "voice_name": name,
            "voice_description": voiceDescription,
        ])
        let (data, response) = try await session.dataWithRetry(for: request)
        try Self.validate(response: response, data: data)

        struct Resp: Decodable { let voice_id: String }
        return try JSONDecoder().decode(Resp.self, from: data).voice_id
    }

    // MARK: - Text-to-Speech

    /// Model for live conversation turns (Talk).
    ///
    /// This was Flash v2.5 for a while, on the reasoning that ~200ms lower
    /// time-to-first-audio is the right trade in a phone-call loop. Reverted,
    /// because that trade priced the wrong thing: Flash buys its latency by
    /// cutting speaker similarity below turbo, and Talk is where users hear
    /// their own cloned voice FAR more than anywhere else in the app — so the
    /// tab with the most exposure was running the least similar model, and
    /// users told us the clone didn't sound like them.
    ///
    /// Turbo costs the SAME per character as Flash, so this reverts for free:
    /// the only thing we give back is the ~200ms, against a turn whose STT +
    /// Gemini legs already dominate the wait. (Fidelity beyond turbo is a
    /// different trade — see `fidelityModelId`, which is NOT free.)
    ///
    /// DEBUG builds run turns on the fidelity model as a LOCAL A/B: feel the
    /// similarity gain against the extra time-to-first-audio on-device.
    /// Release/TestFlight stays on turbo — promoting multilingual to live
    /// turns is a standing pricing decision (2x upstream, absorbed; see
    /// `fidelityModelId`), not something this toggle decides.
    #if DEBUG
    static let conversationModelId = fidelityModelId
    #else
    static let conversationModelId = "eleven_turbo_v2_5"
    #endif

    /// Model for material the user LISTENS to as their own voice, where
    /// speaker similarity is the product (Watch scenes today).
    ///
    /// flash/turbo v2.5 are the latency tier — they trade speaker similarity
    /// for time-to-first-audio. multilingual_v2 is the fidelity tier, and it
    /// is also markedly better at cross-lingual transfer (a clone recorded in
    /// one language speaking another), which is exactly what this app does.
    ///
    /// COST: multilingual_v2 bills ~2x per character upstream vs flash/turbo
    /// v2.5, and `priceFor("tts")` in the edge function is character-based and
    /// model-BLIND — the user is charged identically either way, so every
    /// call on this model is margin we absorb. Only put a path on it when
    /// `PhraseAudioStore` caches the result, which makes that 2x a ONE-TIME
    /// cost per unique line rather than a per-play one. Never use it for live
    /// conversation turns: those are new text every time, so nothing caches
    /// and the 2x repeats forever (on top of being too slow for a call).
    static let fidelityModelId = "eleven_multilingual_v2"

    /// Deterministic fallback idempotency key for callers that don't pass
    /// one (drill / library / shadow / scene plays): the same (text, voice)
    /// from this install always sends the same key, so a double-fired play
    /// or retry race dedupes to ONE charge server-side. Salted per install
    /// so keys can never collide across users on shared preset voices; a
    /// reinstall (which also loses the audio cache) simply starts fresh.
    private static let installSalt: String = {
        let key = "futurevoice.ttsIdemSalt"
        if let s = UserDefaults.standard.string(forKey: key) { return s }
        let s = UUID().uuidString
        UserDefaults.standard.set(s, forKey: key)
        return s
    }()

    private static func deterministicKey(text: String, voiceId: String,
                                         timestamps: Bool) -> String {
        // Timestamps flag included: plain and karaoke syntheses are separate
        // billable actions and must not dedupe against each other.
        let digest = SHA256.hash(data: Data("\(voiceId)|\(timestamps)|\(text)".utf8))
        let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "tts:\(installSalt):\(hex)"
    }

    /// Synthesizes speech in the cloned voice and returns MP3 data.
    /// - Parameters:
    ///   - voiceId: ElevenLabs voice id from `cloneVoice`
    ///   - text: text to speak. Should already be in the target language.
    ///   - modelId: defaults to multilingual model that handles non-English well.
    ///   - previousText/nextText: the lines that surround this one in a longer
    ///     stretch of speech. NOT spoken — they only condition prosody, and
    ///     ElevenLabs does not bill their characters. Without them every line
    ///     is synthesized as a standalone utterance: full sentence-final fall
    ///     at the end, cold "starting to talk" energy at the start. Across a
    ///     scene that reads as a series of separate announcements rather than
    ///     a conversation. Pass them wherever consecutive lines play back to
    ///     back (Watch scenes), regardless of who speaks each one — the point
    ///     is that this line lands mid-conversation, not who said the last one.
    func synthesize(
        voiceId: String,
        text: String,
        modelId: String = "eleven_turbo_v2_5",
        idempotencyKey: String? = nil,
        purpose: String? = nil,
        previousText: String? = nil,
        nextText: String? = nil,
        sceneKey: String? = nil
    ) async throws -> Data {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-tts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        // Caller-supplied key = retries of the same logical synthesis are
        // charge-deduped by the edge function's usage ledger.
        request.setValue(idempotencyKey ?? Self.deterministicKey(text: text, voiceId: voiceId, timestamps: false),
                         forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        // Voice settings are now fixed inside the Edge Function — keeping
        // them server-side means we can tune stability/similarity without
        // shipping a new app version.
        var body: [String: Any] = [
            "voice_id": voiceId,
            "text": text,
            "model_id": modelId,
            "with_timestamps": false,
        ]
        // Feature tag for the usage ledger (spend attribution) — the edge
        // function records it in metadata, never forwards it upstream.
        if let purpose { body["purpose"] = purpose }
        // One Watch scene = one key across all its lines, so the plan's daily
        // scene COUNT is charged once and the scene's seconds stop coming out
        // of the talk allowance. An edge deploy that predates this ignores it
        // and the scene meters in seconds exactly as it used to.
        if let sceneKey { body["scene_key"] = sceneKey }
        // Prosody conditioning. An edge deploy that predates these simply
        // drops them and the line synthesizes exactly as it used to.
        if let previousText, !previousText.isEmpty { body["previous_text"] = previousText }
        if let nextText, !nextText.isEmpty { body["next_text"] = nextText }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.dataWithRetry(for: request)
        try Self.validate(response: response, data: data)
        return data
    }

    /// Result of a streaming synthesis. `.pcm` means the server streamed raw
    /// 16-bit LE mono PCM at `sampleRate` Hz and `onPCMChunk` already
    /// delivered it incrementally; the payload is the FULL accumulated PCM
    /// for caching. `.mp3` means the server doesn't support streaming yet
    /// (older edge deploy) — the payload is the fully-buffered MP3, exactly
    /// like `synthesize` returns, and `onPCMChunk` was never called.
    enum StreamedAudio {
        case pcm(Data, sampleRate: Double)
        case mp3(Data)
    }

    /// PCM formats we can play, best first. Sent to the edge function, which
    /// walks down until the ElevenLabs plan accepts one (pcm_44100 is
    /// Pro-tier) — so conversation audio rides the highest rate the account
    /// allows instead of being pinned to the 22.05 kHz floor.
    private static let streamFormats = ["pcm_44100", "pcm_24000", "pcm_22050"]

    /// Streaming TTS: playback can start on the first chunk instead of after
    /// the full file. Chunks are delivered in order via `onPCMChunk` (16-bit
    /// LE mono PCM at the callback's sample rate), sized ~8 KB.
    ///
    /// No word timings on this path — the shadow screen already re-synthesizes
    /// via `with-timestamps` when a line has no cached timings.
    func synthesizeStreaming(
        voiceId: String,
        text: String,
        modelId: String = "eleven_turbo_v2_5",
        idempotencyKey: String? = nil,
        purpose: String? = nil,
        sceneKey: String? = nil,
        onPCMChunk: @MainActor @escaping (Data, _ sampleRate: Double) -> Void
    ) async throws -> StreamedAudio {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-tts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey ?? Self.deterministicKey(text: text, voiceId: voiceId, timestamps: false),
                         forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "voice_id": voiceId,
            "text": text,
            "model_id": modelId,
            "with_timestamps": false,
            "stream": true,
            "stream_formats": Self.streamFormats,
        ]
        if let purpose { body["purpose"] = purpose }
        if let sceneKey { body["scene_key"] = sceneKey }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // One immediate re-dial on a transient connect failure: a cellular
        // radio blip at stream OPEN otherwise cascades straight into the
        // buffered fallback, which doubles perceived latency for the turn.
        // (Mid-stream breaks stay the caller's fallback to handle.)
        var opened: (URLSession.AsyncBytes, URLResponse)
        do {
            opened = try await session.bytes(for: request)
        } catch where error.isTransientNetworkError {
            opened = try await session.bytes(for: request)
        }
        let (bytes, response) = opened
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var errBody = Data()
            for try await b in bytes.prefix(512) { errBody.append(b) }
            let snippet = String(data: errBody, encoding: .utf8) ?? "<binary>"
            if http.statusCode == 402 {
                throw snippet.contains("scene_cap_reached")
                    ? ElevenLabsError.sceneCapReached : ElevenLabsError.insufficientCredits
            }
            throw ElevenLabsError.httpError(status: http.statusCode, body: snippet)
        }

        // The PCM header is the protocol handshake: without it we're talking
        // to an edge deploy that ignored `stream` and returned a whole MP3 —
        // buffer it and let the caller take the classic path. The header also
        // carries the rate the server actually got from ElevenLabs
        // ("pcm_44100" on Pro, lower otherwise).
        let format = http.value(forHTTPHeaderField: "X-Audio-Format") ?? ""
        guard format.hasPrefix("pcm_"),
              let sampleRate = Double(format.dropFirst("pcm_".count)) else {
            var all = Data()
            for try await b in bytes { all.append(b) }
            return .mp3(all)
        }

        var full = Data()
        var chunk = Data()
        // ~8 KB ≈ 0.09–0.18s of s16 mono depending on rate: small enough for
        // a fast start, big enough to keep scheduling overhead trivial.
        let flushSize = 8 * 1024
        for try await b in bytes {
            chunk.append(b)
            if chunk.count >= flushSize {
                // Keep sample alignment: never split an Int16 across flushes.
                let even = chunk.count - (chunk.count % 2)
                let out = chunk.prefix(even)
                chunk.removeFirst(even)
                full.append(contentsOf: out)
                let send = Data(out)
                await MainActor.run { onPCMChunk(send, sampleRate) }
            }
        }
        if !chunk.isEmpty {
            let even = chunk.count - (chunk.count % 2)
            if even > 0 {
                let out = Data(chunk.prefix(even))
                full.append(out)
                await MainActor.run { onPCMChunk(out, sampleRate) }
            }
        }
        return .pcm(full, sampleRate: sampleRate)
    }

    /// Same TTS as `synthesize`, but uses the `with-timestamps` endpoint so we
    /// also get character-level alignment. We group consecutive non-space
    /// characters into words and return their [start, end] ms windows for the
    /// karaoke highlight in shadow practice.
    ///
    /// If the with-timestamps endpoint fails for any reason (HTTP error,
    /// unexpected JSON shape) we transparently fall back to plain `synthesize`
    /// and return empty timings — keeps audio working even when karaoke is
    /// unavailable.
    func synthesizeWithTimestamps(
        voiceId: String,
        text: String,
        modelId: String = "eleven_turbo_v2_5",
        idempotencyKey: String? = nil,
        purpose: String? = nil
    ) async throws -> (Data, [WordTiming]) {
        do {
            return try await synthesizeWithTimestampsInner(
                voiceId: voiceId, text: text, modelId: modelId,
                idempotencyKey: idempotencyKey, purpose: purpose)
        } catch {
            // Fallback: at least play audio without karaoke. Reuses the same
            // idempotency key — one logical synthesis, one charge.
            let audio = try await synthesize(
                voiceId: voiceId, text: text, modelId: modelId,
                idempotencyKey: idempotencyKey, purpose: purpose)
            return (audio, [])
        }
    }

    private func synthesizeWithTimestampsInner(
        voiceId: String,
        text: String,
        modelId: String,
        idempotencyKey: String? = nil,
        purpose: String? = nil
    ) async throws -> (Data, [WordTiming]) {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-tts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey ?? Self.deterministicKey(text: text, voiceId: voiceId, timestamps: true),
                         forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var body: [String: Any] = [
            "voice_id": voiceId,
            "text": text,
            "model_id": modelId,
            "with_timestamps": true,
        ]
        if let purpose { body["purpose"] = purpose }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.dataWithRetry(for: request)
        try Self.validate(response: response, data: data)

        struct Alignment: Decodable {
            let characters: [String]
            let character_start_times_seconds: [Double]
            let character_end_times_seconds: [Double]
        }
        struct Resp: Decodable {
            let audio_base64: String
            let alignment: Alignment?
            let normalized_alignment: Alignment?
        }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        guard let audio = Data(base64Encoded: decoded.audio_base64) else {
            throw ElevenLabsError.invalidResponse
        }
        // ElevenLabs returns TWO alignments: `alignment` indexes the text we
        // SENT, while `normalized_alignment` indexes ElevenLabs' own normalized
        // form of it — which for non-Latin scripts is ROMANIZED ("그러면" →
        // "geureomyeon") and spells numbers out. Shadow practice renders these
        // timing words AS the target sentence, so preferring the normalized one
        // turned Korean shadowing into romaji. Raw alignment first, always.
        let align = decoded.alignment ?? decoded.normalized_alignment
        var timings: [WordTiming] = []
        if let align = align {
            let candidate = Self.wordTimings(from: align.characters,
                                             starts: align.character_start_times_seconds,
                                             ends: align.character_end_times_seconds)
            // Belt and braces: if what came back doesn't spell out the line we
            // asked for, it isn't safe to display. Empty timings make callers
            // fall back to the local estimate, which uses the real text.
            timings = Self.alignmentMatches(text: text, timings: candidate) ? candidate : []
        }
        return (audio, timings)
    }

    /// True when a timing set really spells out `text` — same characters,
    /// ignoring whitespace, case and punctuation. The one thing this must
    /// catch is a transliterated/normalized alignment being shown to the
    /// learner as their target sentence.
    static func alignmentMatches(text: String, timings: [WordTiming]) -> Bool {
        guard !timings.isEmpty else { return false }
        func squash(_ s: String) -> String {
            String(String.UnicodeScalarView(
                s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            ))
        }
        return squash(timings.map(\.word).joined()) == squash(text)
    }

    /// Group consecutive non-whitespace characters into words and collapse
    /// per-character timings into a single [start, end] window per word.
    private static func wordTimings(
        from chars: [String],
        starts: [Double],
        ends: [Double]
    ) -> [WordTiming] {
        guard chars.count == starts.count, chars.count == ends.count else { return [] }
        var out: [WordTiming] = []
        var current: String = ""
        var currentStart: Double = 0
        var currentEnd: Double = 0
        for i in 0..<chars.count {
            let c = chars[i]
            let isWS = c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isWS {
                if !current.isEmpty {
                    out.append(WordTiming(
                        word: current,
                        startMs: Int((currentStart * 1000).rounded()),
                        endMs: Int((currentEnd * 1000).rounded())
                    ))
                    current = ""
                }
            } else {
                if current.isEmpty { currentStart = starts[i] }
                current += c
                currentEnd = ends[i]
            }
        }
        if !current.isEmpty {
            out.append(WordTiming(
                word: current,
                startMs: Int((currentStart * 1000).rounded()),
                endMs: Int((currentEnd * 1000).rounded())
            ))
        }
        return out
    }

    // MARK: - Helpers

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            if http.statusCode == 402 {
                throw snippet.contains("scene_cap_reached")
                    ? ElevenLabsError.sceneCapReached : ElevenLabsError.insufficientCredits
            }
            throw ElevenLabsError.httpError(status: http.statusCode, body: snippet)
        }
    }
}

enum ElevenLabsError: Error, LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)
    case insufficientCredits
    /// A SUBSCRIBER used up today's Watch scenes. Never a paywall — they
    /// already paid, so `isOutOfCredits` deliberately does not match this.
    case sceneCapReached

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "ElevenLabs: invalid response"
        case .httpError(let status, let body):
            // The voice-slot ceiling is OUR capacity problem, not something the
            // user did — don't hand them a wall of upstream JSON they can't act
            // on. Everything else keeps the raw body: it's the only diagnostic
            // a beta tester can screenshot.
            if Self.isVoiceLimitBody(body) {
                return "We've hit our voice-creation limit right now — nothing you did wrong. We've been alerted; please try again a bit later."
            }
            return "ElevenLabs HTTP \(status): \(body)"
        case .insufficientCredits: return "You're out of credits. Check your plan under Me → Account."
        case .sceneCapReached:
            return explain("You've watched today's scenes. New ones unlock at midnight — replaying the ones you have is always free.")
        }
    }

    /// True when the account's custom-voice slots are full. The upstream error
    /// arrives as a 400 with `voice_limit_reached` nested in the body.
    var isVoiceLimitReached: Bool {
        if case .httpError(_, let body) = self { return Self.isVoiceLimitBody(body) }
        return false
    }

    private static func isVoiceLimitBody(_ body: String) -> Bool {
        body.contains("voice_limit_reached")
    }
}

extension Error {
    /// Convenience for call sites that only hold an `Error`.
    var isVoiceLimitReached: Bool {
        (self as? ElevenLabsError)?.isVoiceLimitReached ?? false
    }

    /// Upstream HTTP status for telemetry, when this is an ElevenLabs failure.
    ///
    /// Worth a helper because the obvious thing to log — `(error as NSError)
    /// .code` — is NOT the case's source order: Swift numbers the cases WITH
    /// payloads first, so `httpError` is 0 and `invalidResponse` is 1. Every
    /// upstream failure therefore logged as a flat "ElevenLabsError:0" that
    /// reads like a decode bug and says nothing about WHICH status came back
    /// (a dead voice id and a rate limit were indistinguishable). Log the
    /// status beside the code, and never read the code as an ordinal.
    var elevenLabsStatus: String? {
        if case .httpError(let status, _)? = self as? ElevenLabsError {
            return String(status)
        }
        return nil
    }
}

// MARK: - Multipart helpers

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }

    mutating func appendFormField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendFileField(name: String, filename: String, mime: String, data: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mime)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }
}
