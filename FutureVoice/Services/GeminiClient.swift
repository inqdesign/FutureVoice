import Foundation

/// Google Gemini client used for conversation turns + post-session summary.
///
/// Mirrors `ClaudeClient`'s surface (`send`, `sendJSON`) so callers can swap.
/// Defaults to `gemini-2.5-flash` with thinking disabled — matches the
/// DearRoRo production pattern (see CLAUDE.md). Key comes from
/// `Secrets.require(.gemini)`.
final class GeminiClient {
    static let shared = GeminiClient()

    private let session: URLSession
    init(session: URLSession = .shared) {
        self.session = session
    }

    private var apiKey: String { Secrets.require(.gemini) }

    enum Model: String {
        case flash25 = "gemini-2.5-flash"
        case flashLite = "gemini-2.0-flash-lite"
    }

    struct Message {
        enum Role: String { case user, model }
        let role: Role
        let content: String
    }

    // MARK: - Public

    func send(
        system: String,
        messages: [Message],
        model: Model = .flash25,
        maxTokens: Int = 512,
        temperature: Double = 0.7
    ) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateContent?key=\(apiKey)")!

        struct Part: Encodable { let text: String }
        struct Content: Encodable { let role: String; let parts: [Part] }
        struct SystemInstruction: Encodable { let parts: [Part] }
        struct ThinkingConfig: Encodable { let thinkingBudget: Int }
        struct GenerationConfig: Encodable {
            let temperature: Double
            let maxOutputTokens: Int
            let thinkingConfig: ThinkingConfig
        }
        struct Body: Encodable {
            let system_instruction: SystemInstruction
            let contents: [Content]
            let generationConfig: GenerationConfig
        }
        let body = Body(
            system_instruction: .init(parts: [.init(text: system)]),
            contents: messages.map { Content(role: $0.role.rawValue, parts: [.init(text: $0.content)]) },
            generationConfig: .init(
                temperature: temperature,
                maxOutputTokens: maxTokens,
                thinkingConfig: .init(thinkingBudget: 0)
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        struct APIResponse: Decodable {
            struct Candidate: Decodable {
                struct ContentR: Decodable {
                    struct PartR: Decodable { let text: String? }
                    let parts: [PartR]?
                }
                let content: ContentR?
            }
            let candidates: [Candidate]?
        }
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        let text = decoded.candidates?.first?.content?.parts?.compactMap { $0.text }.joined() ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One-shot JSON request. Caller specifies the expected `Decodable` shape.
    func sendJSON<T: Decodable>(
        system: String,
        messages: [Message],
        model: Model = .flash25,
        maxTokens: Int = 1024
    ) async throws -> T {
        let raw = try await send(
            system: system,
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: 0.4
        )
        guard let jsonData = Self.extractJSON(from: raw) else {
            throw GeminiError.jsonNotFound(raw: raw)
        }
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    // MARK: - Helpers

    private static func extractJSON(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            throw GeminiError.httpError(status: http.statusCode, body: snippet)
        }
    }
}

enum GeminiError: Error, LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)
    case jsonNotFound(raw: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:               return "Gemini: invalid response"
        case .httpError(let status, let body): return "Gemini HTTP \(status): \(body)"
        case .jsonNotFound(let raw):         return "Gemini: no JSON found in reply: \(raw.prefix(200))"
        }
    }
}
