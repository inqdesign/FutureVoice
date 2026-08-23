import Foundation
import Network

/// Live snapshot of the current network path, for adapting request payloads
/// BEFORE they fail (e.g. skip the audio attachment on a constrained link
/// instead of burning 40s discovering the uplink can't carry it).
final class NetworkPathStatus: @unchecked Sendable {
    static let shared = NetworkPathStatus()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var _isExpensive = false      // cellular / hotspot
    private var _isConstrained = false    // Low Data Mode
    private var _isSatisfied = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.lock()
            _isExpensive = path.isExpensive
            _isConstrained = path.isConstrained
            _isSatisfied = path.status == .satisfied
            lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "network-path-status"))
    }

    var isExpensive: Bool { lock.lock(); defer { lock.unlock() }; return _isExpensive }
    var isConstrained: Bool { lock.lock(); defer { lock.unlock() }; return _isConstrained }
    var isSatisfied: Bool { lock.lock(); defer { lock.unlock() }; return _isSatisfied }

    /// One-word label for telemetry ("wifi" / "cellular" / "constrained" / "offline").
    var label: String {
        if !isSatisfied { return "offline" }
        if isConstrained { return "constrained" }
        return isExpensive ? "cellular" : "wifi"
    }
}

/// Fire-and-forget error breadcrumbs → `client_events` (write-only RLS).
/// Never throws, never blocks the caller, silently drops when signed out —
/// a telemetry failure must not become a second user-facing failure.
enum Telemetry {
    /// Read straight off the bundle rather than through `AppUpdateService`,
    /// which is `@MainActor` and therefore unreachable from the detached task
    /// below. `Bundle.main.infoDictionary` is safe from any thread, and both
    /// values are constant for the process, so they're resolved once.
    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    private static let version =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

    static func log(_ event: String, _ properties: [String: String] = [:]) {
        Task.detached(priority: .utility) {
            struct Row: Encodable {
                let user_id: String
                let event: String
                let properties: [String: String]
            }
            guard let session = try? await SupabaseProvider.shared.auth.session else { return }
            var props = properties
            props["network"] = NetworkPathStatus.shared.label
            // Which build produced this event. Without it, every gap in
            // server-side data is unfalsifiable: talk-tick rows missing for an
            // account read identically whether the meter is broken or the
            // phone is simply on a build that predates it — which is exactly
            // the question that could not be answered on 2026-08-23. One
            // string per event, and it makes the whole table diagnosable.
            props["build"] = Self.build
            props["version"] = Self.version
            try? await SupabaseProvider.shared
                .from("client_events")
                .insert(Row(user_id: session.user.id.uuidString,
                            event: event, properties: props))
                .execute()
        }
    }
}

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

    /// Edge-function work whose result NOBODY is waiting to hear — today just
    /// the per-turn verbatim transcription.
    ///
    /// Same settings as `edgeFunctions`; the point is the separate SESSION.
    /// URLSession keeps its connection pool per instance, so the ~100 KB
    /// base64 audio upload this carries gets its own connection instead of
    /// sharing one HTTP/2 connection's stream window and send buffer with the
    /// turn reply and the ElevenLabs stream — which both live on
    /// `edgeFunctions` and both point at the same Supabase host. Measured
    /// same-day, turns that carried the upload reached the reply's first
    /// sentence 0.8–2.2 s later than turns that didn't.
    static let edgeFunctionsBackground: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 40
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
