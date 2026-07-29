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
    init(session: URLSession = .edgeFunctions) {
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
        /// Default brain (GA 2026-07-21) — conversation turns, analysis,
        /// generation. Successor to 2.5 Flash, which retires 2026-10-16.
        case flash36 = "gemini-3.6-flash"
        /// Cheap fast tier for utility calls (translation, parsing, canned
        /// openers) where top quality isn't load-bearing.
        case flashLite31 = "gemini-3.1-flash-lite"
        /// Legacy default — rollback escape hatch until the Oct 2026
        /// retirement; don't wire new features to it.
        case flash25 = "gemini-2.5-flash"

        /// Gen-3 models take `thinkingLevel` ("low"…) and prefer default
        /// sampling; 2.5 takes `thinkingBudget` + explicit temperature.
        var isGen3: Bool { self != .flash25 }
    }

    struct Message {
        enum Role: String { case user, model }
        let role: Role
        let content: String
        /// Optional audio attached alongside the text (conversation turns
        /// attach the user's own recorded utterance so the model hears what
        /// was actually said instead of trusting on-device STT). The audio
        /// part is sent FIRST, the text rides along as the ASR hint.
        var inlineAudio: InlineAudio? = nil

        struct InlineAudio {
            let mimeType: String     // e.g. "audio/wav"
            let base64Data: String
        }
    }

    // MARK: - Public

    func send(
        system: String,
        messages: [Message],
        model: Model = .flash36,
        maxTokens: Int = 512,
        temperature: Double = 0.7,
        searchGrounding: Bool = false,
        purpose: String? = nil,
        idempotencyKey: String? = nil,
        jsonResponse: Bool = false,
        requestTimeout: TimeInterval? = nil
    ) async throws -> String {
        let url = functionsBaseURL.appendingPathComponent("gemini")

        // Optionals encode via encodeIfPresent, so a text part carries no
        // "inlineData" key and vice versa — matching Gemini's part union.
        struct InlineData: Encodable { let mimeType: String; let data: String }
        struct Part: Encodable {
            var text: String? = nil
            var inlineData: InlineData? = nil
        }
        struct Content: Encodable { let role: String; let parts: [Part] }
        struct SystemInstruction: Encodable { let parts: [Part] }
        struct ThinkingConfig: Encodable {
            var thinkingBudget: Int? = nil   // 2.5 family: 0 = thinking off
            var thinkingLevel: String? = nil // gen-3 family: "low" = minimum
        }
        struct GenerationConfig: Encodable {
            let temperature: Double?        // nil = omitted (model default)
            let maxOutputTokens: Int
            let thinkingConfig: ThinkingConfig
            let responseMimeType: String?   // nil = omitted
        }
        struct EmptyObject: Encodable {}
        struct Tool: Encodable { let google_search: EmptyObject }
        struct Body: Encodable {
            let model: String
            let system_instruction: SystemInstruction
            let contents: [Content]
            let generationConfig: GenerationConfig
            let tools: [Tool]?   // nil = omitted; edge function passes through
            let purpose: String? // nil = omitted; edge function bills per intent
        }
        let body = Body(
            model: model.rawValue,
            system_instruction: .init(parts: [.init(text: system)]),
            contents: messages.map { msg in
                var parts: [Part] = []
                if let audio = msg.inlineAudio {
                    parts.append(Part(inlineData: .init(mimeType: audio.mimeType,
                                                        data: audio.base64Data)))
                }
                parts.append(Part(text: msg.content))
                return Content(role: msg.role.rawValue, parts: parts)
            },
            generationConfig: .init(
                // Gemini 3.x: Google strongly recommends default sampling —
                // sub-1.0 temperatures can degrade or loop gen-3 models, so
                // the caller's value is only honored on the 2.5 family.
                temperature: model.isGen3 ? nil : temperature,
                maxOutputTokens: maxTokens,
                // Latency floor for the phone-call loop: thinking OFF on 2.5,
                // the minimum "low" level on gen-3 (which can't fully disable).
                thinkingConfig: model.isGen3
                    ? .init(thinkingLevel: "low")
                    : .init(thinkingBudget: 0),
                // Force JSON output at the API level — prompt-only JSON drifts
                // back to prose in long conversations because the model
                // imitates its own (plain-text) turns in the history.
                // Incompatible with the google_search tool, so grounded calls
                // keep relying on the prompt + extractJSON.
                responseMimeType: (jsonResponse && !searchGrounding) ? "application/json" : nil
            ),
            tools: searchGrounding ? [Tool(google_search: EmptyObject())] : nil,
            purpose: purpose
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Callers on a fallback ladder (audio turn → text-only rescue) pass a
        // shorter idle timeout so the rescue engages in seconds, not after
        // the session-wide 40s window.
        if let requestTimeout { request.timeoutInterval = requestTimeout }
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        // A caller-supplied key makes retries of the SAME logical request
        // (e.g. the inline turn Retry button) free — the edge function's
        // usage ledger dedupes charges on this key. Default stays one-shot.
        request.setValue(idempotencyKey ?? UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.dataWithRetry(for: request)
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
    /// Default temperature is low for analysis-style calls; conversation
    /// turns pass a higher one so the structured wrapper doesn't flatten tone.
    func sendJSON<T: Decodable>(
        system: String,
        messages: [Message],
        model: Model = .flash36,
        maxTokens: Int = 1024,
        temperature: Double = 0.4,
        searchGrounding: Bool = false,
        purpose: String? = nil,
        idempotencyKey: String? = nil,
        requestTimeout: TimeInterval? = nil
    ) async throws -> T {
        let raw = try await send(
            system: system,
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            searchGrounding: searchGrounding,
            purpose: purpose,
            idempotencyKey: idempotencyKey,
            jsonResponse: true,
            requestTimeout: requestTimeout
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
            if http.statusCode == 402 { throw GeminiError.insufficientCredits }
            let snippet = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            throw GeminiError.httpError(status: http.statusCode, body: snippet)
        }
    }
}

enum GeminiError: Error, LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)
    case jsonNotFound(raw: String)
    case insufficientCredits

    var errorDescription: String? {
        switch self {
        case .invalidResponse:               return "Gemini: invalid response"
        case .httpError(let status, let body): return "Gemini HTTP \(status): \(body)"
        case .jsonNotFound(let raw):         return "Gemini: no JSON found in reply: \(raw.prefix(200))"
        case .insufficientCredits:           return "You're out of credits. Check your plan under Me → Account."
        }
    }
}
