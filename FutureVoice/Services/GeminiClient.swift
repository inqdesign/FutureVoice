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

    /// Fire-and-forget connection warm-up. Called during the VAD silence
    /// window so the TCP+TLS handshake (and a fresh cached auth token)
    /// happens BEFORE the turn request instead of on its critical path —
    /// on a cold cellular radio that handshake alone is 200–600ms. The
    /// OPTIONS preflight needs no auth and bills nothing; ElevenLabs shares
    /// the same host + session, so one warm-up covers both legs.
    func preconnect() {
        let url = functionsBaseURL.appendingPathComponent("gemini")
        let session = self.session
        Task.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.httpMethod = "OPTIONS"
            _ = try? await session.data(for: request)
            _ = try? await SupabaseProvider.shared.auth.session   // refresh token cache
        }
    }

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
        try await sendRaw(
            system: system, messages: messages, model: model, maxTokens: maxTokens,
            temperature: temperature, searchGrounding: searchGrounding,
            purpose: purpose, idempotencyKey: idempotencyKey,
            jsonResponse: jsonResponse, requestTimeout: requestTimeout
        ).text
    }

    /// Same request as `send`, but also surfaces the candidate's
    /// `finishReason`. `sendJSON` needs it to tell a genuinely malformed reply
    /// apart from one the token ceiling cut in half: after decoding fails the
    /// two are indistinguishable, yet only the latter is fixed by raising
    /// `maxTokens`. Keeping them separate in telemetry is the only way to know
    /// whether a ceiling bump actually landed.
    private func sendRaw(
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
    ) async throws -> (text: String, finishReason: String?) {
        let request = try await makeRequest(
            system: system, messages: messages, model: model, maxTokens: maxTokens,
            temperature: temperature, searchGrounding: searchGrounding,
            purpose: purpose, idempotencyKey: idempotencyKey,
            jsonResponse: jsonResponse, requestTimeout: requestTimeout, stream: false
        )

        let (data, response) = try await session.dataWithRetry(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        let candidate = decoded.candidates?.first
        let text = candidate?.content?.parts?.compactMap { $0.text }.joined() ?? ""
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), candidate?.finishReason)
    }

    /// One `generateContent` candidate — shared by the buffered response and
    /// by every SSE event of the streaming one (each event carries the same
    /// shape, holding that step's text delta).
    private struct APIResponse: Decodable {
        struct Candidate: Decodable {
            struct ContentR: Decodable {
                struct PartR: Decodable { let text: String? }
                let parts: [PartR]?
            }
            let content: ContentR?
            let finishReason: String?
        }
        let candidates: [Candidate]?
    }

    private func makeRequest(
        system: String,
        messages: [Message],
        model: Model,
        maxTokens: Int,
        temperature: Double,
        searchGrounding: Bool,
        purpose: String?,
        idempotencyKey: String?,
        jsonResponse: Bool,
        requestTimeout: TimeInterval?,
        stream: Bool
    ) async throws -> URLRequest {
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
            let stream: Bool?    // nil = omitted; true = SSE passthrough
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
            purpose: purpose,
            stream: stream ? true : nil
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
        return request
    }

    /// One-shot JSON request. Caller specifies the expected `Decodable` shape.
    /// Default temperature is low for analysis-style calls; conversation
    /// turns pass a higher one so the structured wrapper doesn't flatten tone.
    ///
    /// SIZING `maxTokens` (applies to every send* on this client): budget it
    /// for the worst-case payload and then some — not for the typical one.
    ///   • gen-3 spends THINKING tokens out of this SAME ceiling, and that
    ///     spend is invisible, uncapped from the caller's side, and largest
    ///     on exactly the long/messy inputs whose output is also longest.
    ///   • Native-language coaching prose costs far more tokens per sentence
    ///     in CJK than the English the schema was eyeballed in.
    ///   • The failure is not a shorter answer, it is `GeminiError.truncated`:
    ///     the JSON stops mid-body and the WHOLE call is lost.
    ///   • The ceiling is not billed — only tokens actually produced — so
    ///     headroom costs nothing. A tight ceiling buys nothing either: it
    ///     cannot make the model brief, only cut it off. Bound length in the
    ///     PROMPT, bound disaster with this number.
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
        let (raw, finishReason) = try await sendRaw(
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
        // Reclassify ONLY after parsing has actually failed — never on the
        // flag alone, so a response that happens to be complete is still used.
        let truncated = finishReason == "MAX_TOKENS"
        guard let jsonData = Self.extractJSON(from: raw) else {
            throw truncated ? GeminiError.truncated : GeminiError.jsonNotFound(raw: raw)
        }
        do {
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            if truncated { throw GeminiError.truncated }
            throw error
        }
    }

    /// Streaming sibling of `sendJSON`, for the conversation turn.
    ///
    /// The turn schema puts `reply` FIRST, and `onEarlyField` fires up to
    /// TWICE for it:
    ///   1. `(firstSentence, isComplete: false)` — the opening sentence, the
    ///      moment it is unambiguously finished, while the model is still
    ///      writing the rest. The caller can start synthesizing here.
    ///   2. `(fullValue, isComplete: true)` — the field's closing quote.
    /// A reply with no sentence break before its close only fires step 2.
    /// Either way the suggestion that follows is written while the voice is
    /// already loading, instead of ahead of the first sound.
    ///
    /// Degrades in three silent steps:
    ///   • edge deploy without SSE support (no `X-Gemini-Stream` handshake) →
    ///     buffer the plain JSON body and decode as usual, no early fire;
    ///   • stream dies AFTER the early field → `fallbackFromEarly` rebuilds the
    ///     payload from what already arrived, so the user still hears the turn;
    ///   • stream dies BEFORE it → throws, and the caller's non-streaming retry
    ///     runs on the same idempotency key (no second charge).
    func sendJSONStream<T: Decodable>(
        system: String,
        messages: [Message],
        model: Model = .flash36,
        maxTokens: Int = 1024,
        temperature: Double = 0.4,
        purpose: String? = nil,
        idempotencyKey: String? = nil,
        requestTimeout: TimeInterval? = nil,
        earlyField: String,
        onEarlyField: @MainActor @escaping (String, Bool) -> Void,
        fallbackFromEarly: (String) -> T?
    ) async throws -> T {
        let request = try await makeRequest(
            system: system, messages: messages, model: model, maxTokens: maxTokens,
            temperature: temperature, searchGrounding: false,
            purpose: purpose, idempotencyKey: idempotencyKey,
            jsonResponse: true, requestTimeout: requestTimeout, stream: true
        )

        // One immediate re-dial on a transient connect failure, matching the
        // TTS stream: a radio blip at stream OPEN otherwise drops the turn
        // into the buffered path and costs more than it saves.
        var opened: (URLSession.AsyncBytes, URLResponse)
        do {
            opened = try await session.bytes(for: request)
        } catch where error.isTransientNetworkError {
            opened = try await session.bytes(for: request)
        }
        let (bytes, response) = opened
        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            var errBody = Data()
            for try await b in bytes.prefix(512) { errBody.append(b) }
            if http.statusCode == 402 { throw GeminiError.insufficientCredits }
            throw GeminiError.httpError(status: http.statusCode,
                                        body: String(data: errBody, encoding: .utf8) ?? "<binary>")
        }

        // No handshake → this deploy ignored `stream` and sent one JSON body.
        guard http.value(forHTTPHeaderField: "X-Gemini-Stream") == "sse" else {
            var all = Data()
            for try await b in bytes { all.append(b) }
            let decoded = try JSONDecoder().decode(APIResponse.self, from: all)
            let candidate = decoded.candidates?.first
            let text = candidate?.content?.parts?.compactMap { $0.text }.joined() ?? ""
            guard let jsonData = Self.extractJSON(from: text) else {
                throw candidate?.finishReason == "MAX_TOKENS"
                    ? GeminiError.truncated : GeminiError.jsonNotFound(raw: text)
            }
            return try JSONDecoder().decode(T.self, from: jsonData)
        }

        var raw = ""                 // model text accumulated across events
        var finishReason: String?
        var early: String?
        var earlyPrefix: String?     // first sentence, emitted before the close
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let event = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard !event.isEmpty, event != "[DONE]",
                      let data = event.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(APIResponse.self, from: data)
                else { continue }
                let candidate = chunk.candidates?.first
                if let reason = candidate?.finishReason { finishReason = reason }
                let delta = candidate?.content?.parts?.compactMap { $0.text }.joined() ?? ""
                guard !delta.isEmpty else { continue }
                raw += delta
                guard early == nil,
                      let field = Self.streamingStringField(earlyField, in: raw) else { continue }
                if field.isComplete {
                    early = field.value
                    await MainActor.run { onEarlyField(field.value, true) }
                } else if earlyPrefix == nil,
                          let sentence = Self.firstSpeakableSentence(in: field.value) {
                    // The opening sentence stands alone — hand it over now and
                    // let the caller start synthesizing while the model is
                    // still writing the rest.
                    earlyPrefix = sentence
                    await MainActor.run { onEarlyField(sentence, false) }
                }
            }
        } catch {
            // `earlyPrefix` counts too: if the stream died after the opening
            // sentence went to TTS, the user is already HEARING this turn.
            // Rebuilding from the prefix keeps the line they heard instead of
            // dead-ending it on a Retry chip that would speak it twice.
            if let early = early ?? earlyPrefix,
               let payload = fallbackFromEarly(early) { return payload }
            throw error
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = finishReason == "MAX_TOKENS"
        guard let jsonData = Self.extractJSON(from: trimmed) else {
            // `earlyPrefix` counts too: if the stream died after the opening
            // sentence went to TTS, the user is already HEARING this turn.
            // Rebuilding from the prefix keeps the line they heard instead of
            // dead-ending it on a Retry chip that would speak it twice.
            if let early = early ?? earlyPrefix,
               let payload = fallbackFromEarly(early) { return payload }
            throw truncated ? GeminiError.truncated : GeminiError.jsonNotFound(raw: trimmed)
        }
        do {
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            // The reply already shipped; a malformed or cut-off tail must not
            // undo a turn the user has heard.
            // `earlyPrefix` counts too: if the stream died after the opening
            // sentence went to TTS, the user is already HEARING this turn.
            // Rebuilding from the prefix keeps the line they heard instead of
            // dead-ending it on a Retry chip that would speak it twice.
            if let early = early ?? earlyPrefix,
               let payload = fallbackFromEarly(early) { return payload }
            if truncated { throw GeminiError.truncated }
            throw error
        }
    }

    /// Streaming sibling of `sendJSON` for payloads whose LEADING fields can
    /// be used before the body closes — the Watch scene plays its title and
    /// turns while the model is still writing the words/expressions tail.
    ///
    /// `onPartial` fires on the main actor with the full accumulated model
    /// text after every chunk; callers parse it incrementally
    /// (`completedStringField`, `completedArrayObjects`) and must tolerate
    /// seeing the same prefix again. Returns the fully decoded payload —
    /// persistence must wait for THAT, so a stream that dies mid-scene throws
    /// instead of yielding half a book. A deploy without SSE support degrades
    /// to buffering the one JSON body; `onPartial` then never fires and the
    /// caller's incremental path just stays quiet.
    func sendJSONStreamAccumulating<T: Decodable>(
        system: String,
        messages: [Message],
        model: Model = .flash36,
        maxTokens: Int = 1024,
        purpose: String? = nil,
        idempotencyKey: String? = nil,
        requestTimeout: TimeInterval? = nil,
        onPartial: @MainActor @escaping (String) -> Void
    ) async throws -> T {
        let request = try await makeRequest(
            system: system, messages: messages, model: model, maxTokens: maxTokens,
            temperature: 0.4, searchGrounding: false,
            purpose: purpose, idempotencyKey: idempotencyKey,
            jsonResponse: true, requestTimeout: requestTimeout, stream: true
        )

        // Same one-shot re-dial as the turn stream: a radio blip at stream
        // OPEN is the common failure, and the idempotency key dedupes billing.
        var opened: (URLSession.AsyncBytes, URLResponse)
        do {
            opened = try await session.bytes(for: request)
        } catch where error.isTransientNetworkError {
            opened = try await session.bytes(for: request)
        }
        let (bytes, response) = opened
        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            var errBody = Data()
            for try await b in bytes.prefix(512) { errBody.append(b) }
            if http.statusCode == 402 { throw GeminiError.insufficientCredits }
            throw GeminiError.httpError(status: http.statusCode,
                                        body: String(data: errBody, encoding: .utf8) ?? "<binary>")
        }

        // No handshake → this deploy ignored `stream` and sent one JSON body.
        guard http.value(forHTTPHeaderField: "X-Gemini-Stream") == "sse" else {
            var all = Data()
            for try await b in bytes { all.append(b) }
            let decoded = try JSONDecoder().decode(APIResponse.self, from: all)
            let candidate = decoded.candidates?.first
            let text = candidate?.content?.parts?.compactMap { $0.text }.joined() ?? ""
            guard let jsonData = Self.extractJSON(from: text) else {
                throw candidate?.finishReason == "MAX_TOKENS"
                    ? GeminiError.truncated : GeminiError.jsonNotFound(raw: text)
            }
            return try JSONDecoder().decode(T.self, from: jsonData)
        }

        var raw = ""
        var finishReason: String?
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let event = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !event.isEmpty, event != "[DONE]",
                  let data = event.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(APIResponse.self, from: data)
            else { continue }
            let candidate = chunk.candidates?.first
            if let reason = candidate?.finishReason { finishReason = reason }
            let delta = candidate?.content?.parts?.compactMap { $0.text }.joined() ?? ""
            guard !delta.isEmpty else { continue }
            raw += delta
            let snapshot = raw
            await MainActor.run { onPartial(snapshot) }
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = finishReason == "MAX_TOKENS"
        guard let jsonData = Self.extractJSON(from: trimmed) else {
            throw truncated ? GeminiError.truncated : GeminiError.jsonNotFound(raw: trimmed)
        }
        do {
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            if truncated { throw GeminiError.truncated }
            throw error
        }
    }

    // MARK: - Helpers

    /// Pulls the COMPLETE objects out of a named array in a JSON body that is
    /// still being streamed — `"turns": [ {…}, {…}, {"speak` yields the two
    /// closed objects and ignores the half-written third. Scanning stops at
    /// the array's own `]`, so a later array (words, expressions) can never
    /// leak elements into this one. Objects come back as raw JSON slices for
    /// the caller to decode; non-object elements are skipped.
    static func completedArrayObjects(_ name: String, in partial: String) -> [Substring] {
        guard let key = partial.range(of: "\"\(name)\"") else { return [] }
        var i = key.upperBound
        func skipSpace() {
            while i < partial.endIndex, partial[i].isWhitespace { i = partial.index(after: i) }
        }
        skipSpace()
        guard i < partial.endIndex, partial[i] == ":" else { return [] }
        i = partial.index(after: i)
        skipSpace()
        guard i < partial.endIndex, partial[i] == "[" else { return [] }
        i = partial.index(after: i)

        var objects: [Substring] = []
        var objStart: String.Index?
        var depth = 0
        var inString = false
        var escaped = false
        while i < partial.endIndex {
            let c = partial[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else {
                switch c {
                case "\"":
                    inString = true
                case "{":
                    if depth == 0 { objStart = i }
                    depth += 1
                case "}":
                    if depth > 0 {
                        depth -= 1
                        if depth == 0, let s = objStart {
                            objects.append(partial[s...i])
                            objStart = nil
                        }
                    }
                case "]":
                    if depth == 0 { return objects }   // array closed — done
                default:
                    break
                }
            }
            i = partial.index(after: i)
        }
        return objects
    }

    /// Pulls a top-level string field out of a JSON body that is still being
    /// streamed, returning it only once its CLOSING quote has arrived. Returns
    /// nil while the value is incomplete, and for a non-string value (`null`,
    /// an object) so a `"suggestion": null` never reads as a finished string.
    ///
    /// A completed value that OPENS a JSON body (`{…`) is not a real field —
    /// it's the model nesting the whole turn schema inside the value without
    /// escaping (`"reply": "{"reply": "text"…`), where the unescaped inner
    /// quote closes the outer string after one `{`. Skip that occurrence and
    /// keep scanning: the next `"reply"` key is the INNER, real one, so the
    /// turn recovers instead of speaking "{" (seen in beta 11 feedback).
    static func completedStringField(_ name: String, in partial: String) -> String? {
        guard let found = streamingStringField(name, in: partial), found.isComplete else {
            return nil
        }
        return found.value
    }

    /// Same scan as `completedStringField`, but also reports a value that is
    /// still being written. `isComplete` says whether the closing quote has
    /// arrived. Used to start speaking a reply's FIRST SENTENCE before the
    /// model has finished writing the rest of it.
    ///
    /// Returns nil until the field's opening quote is on the wire, and for a
    /// non-string value, so a `"suggestion": null` never reads as text.
    static func streamingStringField(_ name: String, in partial: String)
        -> (value: String, isComplete: Bool)? {
        var searchFrom = partial.startIndex
        scan: while let key = partial.range(of: "\"\(name)\"",
                                            range: searchFrom..<partial.endIndex) {
            searchFrom = key.upperBound
            var i = key.upperBound
            func skipSpace() {
                while i < partial.endIndex, partial[i].isWhitespace { i = partial.index(after: i) }
            }
            skipSpace()
            guard i < partial.endIndex, partial[i] == ":" else { return nil }
            i = partial.index(after: i)
            skipSpace()
            guard i < partial.endIndex, partial[i] == "\"" else { return nil }
            i = partial.index(after: i)

            var out = ""
            var escaped = false
            while i < partial.endIndex {
                let c = partial[i]
                if escaped {
                    switch c {
                    case "n":  out.append("\n")
                    case "t":  out.append("\t")
                    case "r":  out.append("\r")
                    case "\"": out.append("\"")
                    case "\\": out.append("\\")
                    case "/":  out.append("/")
                    case "u":
                        // \uXXXX. Surrogate halves can't be resolved one escape at
                        // a time — bail and let the fully decoded payload win.
                        let start = partial.index(after: i)
                        guard let end = partial.index(start, offsetBy: 4, limitedBy: partial.endIndex),
                              let value = UInt32(String(partial[start..<end]), radix: 16),
                              let scalar = Unicode.Scalar(value) else { return nil }
                        out.append(Character(scalar))
                        i = partial.index(before: end)
                    default:   out.append(c)
                    }
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    // Closing quote → the field is complete, unless the "value"
                    // is a nested JSON opener — then hunt for the inner key.
                    if out.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                        continue scan
                    }
                    return (out, true)
                } else {
                    out.append(c)
                }
                i = partial.index(after: i)
            }
            // Ran out of input: the value is still being written. A value that
            // OPENS a nested body is schema debris, not speech — report it as
            // absent rather than let a caller act on "{".
            if out.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { return nil }
            return (out, false)
        }
        return nil
    }

    /// The first sentence of a still-streaming value, once it is unambiguously
    /// finished — a terminator FOLLOWED BY whitespace, so "3.5" and "e.g. " are
    /// not mistaken for sentence ends.
    ///
    /// Below `minSpeakableSentence` we don't split at all: the point is to get
    /// a LONG reply talking sooner, and cutting "Sure." off the front of a
    /// short one buys a few milliseconds in exchange for an audible seam.
    ///
    /// Measured in `speakableWeight`, not characters — a CJK/Hangul syllable
    /// carries about twice the speech of a Latin letter, so a plain character
    /// count would never split a Korean reply at all.
    private static let minSpeakableSentence = 25

    static func firstSpeakableSentence(in partial: String) -> String? {
        let terminators: Set<Character> = [".", "!", "?", "。", "！", "？"]
        var i = partial.startIndex
        var weight = 0
        while i < partial.endIndex {
            let next = partial.index(after: i)
            weight += speakableWeight(partial[i])
            if terminators.contains(partial[i]), weight >= minSpeakableSentence,
               next < partial.endIndex, partial[next].isWhitespace {
                let sentence = String(partial[partial.startIndex...i])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return sentence.isEmpty ? nil : sentence
            }
            i = next
        }
        return nil
    }

    /// Rough "how much speech is this character" weight. Hangul syllables,
    /// CJK ideographs and kana are whole syllables or words; Latin letters are
    /// a fraction of one.
    private static func speakableWeight(_ c: Character) -> Int {
        guard let v = c.unicodeScalars.first?.value else { return 1 }
        switch v {
        case 0xAC00...0xD7A3,   // Hangul syllables
             0x1100...0x11FF,   // Hangul jamo
             0x3130...0x318F,   // Hangul compatibility jamo
             0x3040...0x30FF,   // hiragana + katakana
             0x3400...0x4DBF,   // CJK ext A
             0x4E00...0x9FFF:   // CJK unified ideographs
            return 2
        default:
            return 1
        }
    }

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
    // Append-only: telemetry logs the bridged NSError code, which is the case
    // INDEX. Reordering these silently rewrites history (insufficientCredits
    // must stay 3).
    case truncated

    var errorDescription: String? {
        switch self {
        case .invalidResponse:               return "Gemini: invalid response"
        case .httpError(let status, let body): return "Gemini HTTP \(status): \(body)"
        case .jsonNotFound(let raw):         return "Gemini: no JSON found in reply: \(raw.prefix(200))"
        case .insufficientCredits:           return "You're out of credits. Check your plan under Me → Account."
        case .truncated:                     return "Gemini: reply hit the token ceiling before it finished"
        }
    }
}
