import Foundation

/// Minimal Anthropic Messages API client.
///
/// Phase 1 spike: in-app key, single request style.
/// Phase 2: move behind a Supabase Edge Function so the iOS app never holds the raw key.
///
/// Model defaults to Sonnet 4.6 — cheaper than Opus, fast enough for live conversation.
/// Switch to `claude-opus-4-7` for higher-stakes turns (e.g. session summary) if needed.
final class ClaudeClient {
    static let shared = ClaudeClient()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var apiKey: String { Secrets.require(.anthropic) }

    // MARK: - Public

    enum Model: String {
        case sonnet46 = "claude-sonnet-4-6"
        case opus47   = "claude-opus-4-7"
        case haiku45  = "claude-haiku-4-5-20251001"
    }

    struct Message: Codable {
        enum Role: String, Codable { case user, assistant }
        let role: Role
        let content: String
    }

    /// One-shot request. Returns the assistant's plain-text reply.
    func send(
        system: String,
        messages: [Message],
        model: Model = .sonnet46,
        maxTokens: Int = 512,
        temperature: Double = 0.7
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Encodable {
            let model: String
            let max_tokens: Int
            let temperature: Double
            let system: String
            let messages: [Message]
        }
        let body = Body(
            model: model.rawValue,
            max_tokens: maxTokens,
            temperature: temperature,
            system: system,
            messages: messages
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        struct APIResponse: Decodable {
            struct ContentBlock: Decodable { let type: String; let text: String? }
            let content: [ContentBlock]
        }
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return decoded.content.compactMap { $0.text }.joined(separator: "\n")
    }

    /// Convenience: decode a JSON object from the assistant reply. Used for session summaries.
    func sendJSON<T: Decodable>(
        system: String,
        messages: [Message],
        model: Model = .sonnet46,
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
            throw ClaudeError.jsonNotFound(raw: raw)
        }
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    // MARK: - Helpers

    /// Pulls the first top-level JSON object out of a possibly-chatty response.
    private static func extractJSON(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else { return nil }
        let slice = text[start...end]
        return slice.data(using: .utf8)
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            throw ClaudeError.httpError(status: http.statusCode, body: snippet)
        }
    }
}

enum ClaudeError: Error, LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)
    case jsonNotFound(raw: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Claude: invalid response"
        case .httpError(let status, let body): return "Claude HTTP \(status): \(body)"
        case .jsonNotFound(let raw): return "Claude: no JSON object found in reply: \(raw.prefix(200))"
        }
    }
}
