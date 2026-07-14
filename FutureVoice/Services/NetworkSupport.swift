import Foundation

/// Networking defaults for the Supabase Edge Function clients (Gemini,
/// ElevenLabs). Two cellular-hardening pieces:
///
/// 1. `URLSession.edgeFunctions` — waits out short connectivity blips
///    (radio handoffs, Wi-Fi↔cellular transitions) instead of failing the
///    request the instant the pooled connection turns out to be dead.
/// 2. `dataWithRetry` / `uploadWithRetry` — automatic re-send on transient
///    transport errors and 5xx gateway hiccups. Every edge-function request
///    carries an `X-Idempotency-Key`, so a retried POST is charge-deduped
///    server-side; the retry the user used to perform by tapping the inline
///    Retry button now happens silently first.
extension URLSession {
    static let edgeFunctions: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        // Idle timeout. Search-grounded Gemini calls (news openers) can run
        // 15–25s server-side before the first byte; 40s covers them without
        // letting genuinely dead requests hang.
        config.timeoutIntervalForRequest = 40
        // Hard ceiling per attempt. This ALSO bounds the waitsForConnectivity
        // wait (the request timeout doesn't run while waiting for
        // connectivity) — so a truly offline user sees a failure in ≤60s,
        // not minutes. Every interactive payload here is small; only the
        // voice-clone upload needs longer → `edgeFunctionUploads`.
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    /// Voice-clone sample upload: ~1–2 MB of WAV on a possibly-slow cellular
    /// uplink. Same connectivity behavior, roomier ceiling.
    static let edgeFunctionUploads: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 40
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    /// `data(for:)` that retries transient failures. Only pass requests
    /// carrying an idempotency key (all edge-function calls do).
    func dataWithRetry(for request: URLRequest, attempts: Int = 3) async throws -> (Data, URLResponse) {
        try await withRetry(attempts: attempts) { try await self.data(for: request) }
    }

    /// `upload(for:from:)` with the same retry policy — the body lives in
    /// memory, so a re-send is just a re-send.
    func uploadWithRetry(for request: URLRequest, from body: Data,
                         attempts: Int = 3) async throws -> (Data, URLResponse) {
        try await withRetry(attempts: attempts) { try await self.upload(for: request, from: body) }
    }

    private func withRetry(attempts: Int,
                           _ send: () async throws -> (Data, URLResponse)) async throws -> (Data, URLResponse) {
        var attempt = 1
        while true {
            do {
                let (data, response) = try await send()
                // Gateway-side transience (cold start, brief upstream outage)
                // comes back as 5xx, not a thrown URLError — retry those too.
                // 4xx (including 402 credits) is the caller's to handle.
                if let http = response as? HTTPURLResponse,
                   (500..<600).contains(http.statusCode), attempt < attempts {
                    attempt += 1
                    try await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                return (data, response)
            } catch {
                guard attempt < attempts, error.isTransientNetworkError else { throw error }
                attempt += 1
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

extension Error {
    /// Failures worth an automatic re-send: the connection died under us or
    /// never came up — typical of cellular radio transitions. These all fail
    /// FAST, so retrying them is nearly free. `.timedOut` is deliberately
    /// absent: with waitsForConnectivity on, a timeout means the network was
    /// down for the whole 60s window — repeating that (3 × 60s of "thinking")
    /// is worse than surfacing the Retry row. Cancellation, TLS trust, and
    /// HTTP-level errors also surface immediately.
    var isTransientNetworkError: Bool {
        guard let urlError = self as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
             .secureConnectionFailed, .requestBodyStreamExhausted:
            return true
        default:
            return false
        }
    }
}
