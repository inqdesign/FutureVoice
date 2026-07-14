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
    /// - Returns: ElevenLabs `voice_id`.
    func cloneVoice(name: String, sampleAudioURLs: [URL], description: String? = nil) async throws -> String {
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
        // Ask ElevenLabs to denoise the sample before clone — handles AC hum,
        // distant traffic, keyboard taps, etc. Improves IVC quality noticeably
        // even when the user thinks the room is "quiet enough".
        body.appendFormField(name: "remove_background_noise", value: "true", boundary: boundary)
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

    // MARK: - Text-to-Speech

    /// Synthesizes speech in the cloned voice and returns MP3 data.
    /// - Parameters:
    ///   - voiceId: ElevenLabs voice id from `cloneVoice`
    ///   - text: text to speak. Should already be in the target language.
    ///   - modelId: defaults to multilingual model that handles non-English well.
    func synthesize(
        voiceId: String,
        text: String,
        modelId: String = "eleven_turbo_v2_5",
        idempotencyKey: String? = nil
    ) async throws -> Data {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-tts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        // Caller-supplied key = retries of the same logical synthesis are
        // charge-deduped by the edge function's usage ledger.
        request.setValue(idempotencyKey ?? UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        // Voice settings are now fixed inside the Edge Function — keeping
        // them server-side means we can tune stability/similarity without
        // shipping a new app version.
        let body: [String: Any] = [
            "voice_id": voiceId,
            "text": text,
            "model_id": modelId,
            "with_timestamps": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.dataWithRetry(for: request)
        try Self.validate(response: response, data: data)
        return data
    }

    /// Result of a streaming synthesis. `.pcm22050` means the server streamed
    /// raw 16-bit LE mono PCM at 22.05 kHz and `onPCMChunk` already delivered
    /// it incrementally; the payload is the FULL accumulated PCM for caching.
    /// `.mp3` means the server doesn't support streaming yet (older edge
    /// deploy) — the payload is the fully-buffered MP3, exactly like
    /// `synthesize` returns, and `onPCMChunk` was never called.
    enum StreamedAudio {
        case pcm22050(Data)
        case mp3(Data)
    }

    static let streamSampleRate: Double = 22_050

    /// Streaming TTS: playback can start on the first chunk instead of after
    /// the full file. Chunks are delivered in order via `onPCMChunk` (16-bit
    /// LE mono PCM, 22.05 kHz), sized ~8 KB (~0.18s of audio).
    ///
    /// No word timings on this path — the shadow screen already re-synthesizes
    /// via `with-timestamps` when a line has no cached timings.
    func synthesizeStreaming(
        voiceId: String,
        text: String,
        modelId: String = "eleven_turbo_v2_5",
        idempotencyKey: String? = nil,
        onPCMChunk: @MainActor @escaping (Data) -> Void
    ) async throws -> StreamedAudio {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-tts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey ?? UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "voice_id": voiceId,
            "text": text,
            "model_id": modelId,
            "with_timestamps": false,
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var errBody = Data()
            for try await b in bytes.prefix(512) { errBody.append(b) }
            if http.statusCode == 402 { throw ElevenLabsError.insufficientCredits }
            let snippet = String(data: errBody, encoding: .utf8) ?? "<binary>"
            throw ElevenLabsError.httpError(status: http.statusCode, body: snippet)
        }

        // The PCM header is the protocol handshake: without it we're talking
        // to an edge deploy that ignored `stream` and returned a whole MP3 —
        // buffer it and let the caller take the classic path.
        let isPCM = http.value(forHTTPHeaderField: "X-Audio-Format") == "pcm_22050"

        if !isPCM {
            var all = Data()
            for try await b in bytes { all.append(b) }
            return .mp3(all)
        }

        var full = Data()
        var chunk = Data()
        // ~8 KB = ~0.18s at 22.05 kHz s16 mono: small enough for a fast
        // start, big enough to keep scheduling overhead trivial.
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
                await MainActor.run { onPCMChunk(send) }
            }
        }
        if !chunk.isEmpty {
            let even = chunk.count - (chunk.count % 2)
            if even > 0 {
                let out = Data(chunk.prefix(even))
                full.append(out)
                await MainActor.run { onPCMChunk(out) }
            }
        }
        return .pcm22050(full)
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
        idempotencyKey: String? = nil
    ) async throws -> (Data, [WordTiming]) {
        do {
            return try await synthesizeWithTimestampsInner(
                voiceId: voiceId, text: text, modelId: modelId, idempotencyKey: idempotencyKey)
        } catch {
            // Fallback: at least play audio without karaoke. Reuses the same
            // idempotency key — one logical synthesis, one charge.
            let audio = try await synthesize(
                voiceId: voiceId, text: text, modelId: modelId, idempotencyKey: idempotencyKey)
            return (audio, [])
        }
    }

    private func synthesizeWithTimestampsInner(
        voiceId: String,
        text: String,
        modelId: String,
        idempotencyKey: String? = nil
    ) async throws -> (Data, [WordTiming]) {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-tts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey ?? UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "voice_id": voiceId,
            "text": text,
            "model_id": modelId,
            "with_timestamps": true,
        ]
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
        let align = decoded.normalized_alignment ?? decoded.alignment
        let timings: [WordTiming]
        if let align = align {
            timings = Self.wordTimings(from: align.characters,
                                       starts: align.character_start_times_seconds,
                                       ends: align.character_end_times_seconds)
        } else {
            timings = []
        }
        return (audio, timings)
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
            if http.statusCode == 402 { throw ElevenLabsError.insufficientCredits }
            let snippet = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            throw ElevenLabsError.httpError(status: http.statusCode, body: snippet)
        }
    }
}

enum ElevenLabsError: Error, LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)
    case insufficientCredits

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "ElevenLabs: invalid response"
        case .httpError(let status, let body): return "ElevenLabs HTTP \(status): \(body)"
        case .insufficientCredits: return "You're out of credits. Check your plan under Me → Account."
        }
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
