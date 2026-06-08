import Foundation

/// Minimal ElevenLabs client for Phase 1.
///
/// Endpoints used:
///   POST /v1/voices/add                          — clone a voice from sample audio
///   POST /v1/text-to-speech/{voice_id}           — non-streaming TTS (returns MP3)
///
/// Phase 2 should switch TTS to the streaming endpoint for < 1.5s end-to-end latency.
final class ElevenLabsClient {
    static let shared = ElevenLabsClient()

    private let baseURL = URL(string: "https://api.elevenlabs.io")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var apiKey: String { Secrets.require(.elevenLabs) }

    // MARK: - Voice cloning

    /// Uploads sample audio and creates a new voice clone.
    /// - Parameters:
    ///   - name: display name for the voice (e.g. "Eunggyu — Future Self")
    ///   - sampleAudioURLs: one or more WAV/MP3 files. Total 30–60s recommended.
    ///   - description: optional human description
    /// - Returns: ElevenLabs `voice_id`.
    func cloneVoice(name: String, sampleAudioURLs: [URL], description: String? = nil) async throws -> String {
        let url = baseURL.appendingPathComponent("/v1/voices/add")
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
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
        let url = baseURL.appendingPathComponent("/v1/voices/\(voiceId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

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
        let url = baseURL.appendingPathComponent("/v1/text-to-speech/\(voiceId)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        struct VoiceSettings: Encodable {
            let stability: Double
            let similarity_boost: Double
            let style: Double
            let use_speaker_boost: Bool
        }
        struct Body: Encodable {
            let text: String
            let model_id: String
            let voice_settings: VoiceSettings
        }
        let body = Body(
            text: text,
            model_id: modelId,
            voice_settings: .init(
                stability: 0.55,       // slightly higher = cleaner, less wobble
                similarity_boost: 0.90, // push close to the cloned timbre
                style: 0.15,            // low style exaggeration — natural over theatrical
                use_speaker_boost: true
            )
        )
        request.httpBody = try JSONEncoder().encode(body)

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
        let url = baseURL.appendingPathComponent("/v1/text-to-speech/\(voiceId)/with-timestamps")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        struct VoiceSettings: Encodable {
            let stability: Double
            let similarity_boost: Double
            let style: Double
            let use_speaker_boost: Bool
        }
        struct Body: Encodable {
            let text: String
            let model_id: String
            let voice_settings: VoiceSettings
        }
        let body = Body(
            text: text,
            model_id: modelId,
            voice_settings: .init(
                stability: 0.55,       // slightly higher = cleaner, less wobble
                similarity_boost: 0.90, // push close to the cloned timbre
                style: 0.15,            // low style exaggeration — natural over theatrical
                use_speaker_boost: true
            )
        )
        request.httpBody = try JSONEncoder().encode(body)

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
            let snippet = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            throw ElevenLabsError.httpError(status: http.statusCode, body: snippet)
        }
    }
}

enum ElevenLabsError: Error, LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "ElevenLabs: invalid response"
        case .httpError(let status, let body): return "ElevenLabs HTTP \(status): \(body)"
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
