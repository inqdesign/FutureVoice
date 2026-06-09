import Foundation
import Supabase

/// Google Gemini client used for conversation turns + post-session summary.
///
/// As of TestFlight prep, all requests route through the `gemini` Supabase
/// Edge Function so the real Google API key stays server-side. The iOS
/// bundle no longer carries `GEMINI_API_KEY`. Each call carries the
/// caller's Supabase access token; the Edge Function verifies it before
/// forwarding to Google.
final class GeminiClient {
    static let shared = GeminiClient()

    private let session: URLSession
    init(session: URLSession = .shared) {
        self.session = session
    }

    private var functionsBaseURL: URL {
        guard
            let urlString = Secrets.string(for: .supabaseURL),
            let url = URL(string: urlString)
        else { fatalError("SUPABASE_URL missing") }
        return url.appendingPathComponent("/functions/v1")
    }

    private func accessToken() async throws -> String {
        let session = try await SupabaseProvider.shared.auth.session
        return session.accessToken
    }

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
        let url = functionsBaseURL.appendingPathComponent("gemini")

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
            let model: String
            let system_instruction: SystemInstruction
            let contents: [Content]
            let generationConfig: GenerationConfig
        }
        let body = Body(
            model: model.rawValue,
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
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
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
