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

    init(session: URLSession = .shared) {
        self.session = session
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

        let (data, response) = try await session.upload(for: request, from: body)
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

        let (data, response) = try await session.data(for: request)
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
        modelId: String = "eleven_turbo_v2_5"
    ) async throws -> Data {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-tts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
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

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return data
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
        modelId: String = "eleven_turbo_v2_5"
    ) async throws -> (Data, [WordTiming]) {
        do {
            return try await synthesizeWithTimestampsInner(voiceId: voiceId, text: text, modelId: modelId)
        } catch {
            // Fallback: at least play audio without karaoke.
            let audio = try await synthesize(voiceId: voiceId, text: text, modelId: modelId)
            return (audio, [])
        }
    }

    private func synthesizeWithTimestampsInner(
        voiceId: String,
        text: String,
        modelId: String
    ) async throws -> (Data, [WordTiming]) {
        let url = functionsBaseURL.appendingPathComponent("elevenlabs-tts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "voice_id": voiceId,
            "text": text,
            "model_id": modelId,
            "with_timestamps": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
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
