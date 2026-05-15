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

    // MARK: - Text-to-Speech

    /// Synthesizes speech in the cloned voice and returns MP3 data.
    /// - Parameters:
    ///   - voiceId: ElevenLabs voice id from `cloneVoice`
    ///   - text: text to speak. Should already be in the target language.
    ///   - modelId: defaults to multilingual model that handles non-English well.
    func synthesize(
        voiceId: String,
        text: String,
        modelId: String = "eleven_multilingual_v2"
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
                stability: 0.45,
                similarity_boost: 0.85,
                style: 0.30,
                use_speaker_boost: true
            )
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return data
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
