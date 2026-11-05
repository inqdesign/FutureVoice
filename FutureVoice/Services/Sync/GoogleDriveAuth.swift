import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// The learner's grant to the app's OWN hidden folder in their Google Drive
/// (`drive.appdata`) — the folder the Android app already syncs into. A Mac
/// or an iPhone that signs into the SAME Google account sees the same folder,
/// which is the whole point: an Android phone and a Mac become one app
/// (2026-11-05, founder: a learner uses exactly that pair).
///
/// No Google SDK: the OAuth "installed app" flow with PKCE through
/// `ASWebAuthenticationSession`, the same way `AuthService` runs its link
/// sheet. The client is an iOS-type OAuth client in the SAME Google Cloud
/// project as Android's (`nawana-507414`), because `appDataFolder` belongs to
/// the project — a client from another project would see an empty folder.
/// The client id is public by design (an installed app can't keep a secret);
/// it rides per config in Info.plist (`FVGoogleDriveClientID`).
///
/// The refresh token lives in the Keychain per APP account (a shared iPad
/// can hold two, each with its own Google account); access tokens live in
/// memory and are refreshed silently, so a background pass never needs UI.
enum GoogleDriveAuth {
    static let driveScope = "https://www.googleapis.com/auth/drive.appdata"
    /// `openid email` only so the settings row can say WHICH Google account
    /// is connected — the one mistake that makes this feature look broken is
    /// signing into a different account than the Android phone's.
    private static let scopes = ["openid", "email", driveScope]

    enum AuthError: LocalizedError {
        case notConfigured
        case cancelled
        case scopeNotGranted
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return explain("Google Drive sync isn't available in this build.")
            case .cancelled: return nil
            case .scopeNotGranted:
                return explain("Allow nawana to use its own folder in your Google Drive, then try again.")
            case .failed(let reason): return reason
            }
        }
    }

    static var clientID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "FVGoogleDriveClientID") as? String,
              !id.isEmpty, !id.hasPrefix("$(") else { return nil }
        return id
    }

    static var isConfigured: Bool { clientID != nil }

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`,
    /// the redirect scheme Google gives every iOS client.
    private static func redirectScheme(for clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    // MARK: - Stored grant

    struct Grant: Codable {
        var refreshToken: String
        var email: String?
    }

    static func grant(userId: String) -> Grant? {
        guard let data = Keychain.read(account: keychainAccount(userId)) else { return nil }
        return try? JSONDecoder().decode(Grant.self, from: data)
    }

    static func email(userId: String) -> String? { grant(userId: userId)?.email }

    static func isConnected(userId: String) -> Bool { grant(userId: userId) != nil }

    /// Forgets the grant on this device. Google's side is revoked too, best
    /// effort — a token we no longer hold is better dead.
    static func disconnect(userId: String) {
        if let refresh = grant(userId: userId)?.refreshToken {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = form(["token": refresh])
            URLSession.shared.dataTask(with: request).resume()
        }
        Keychain.delete(account: keychainAccount(userId))
        tokens.forget(userId: userId)
    }

    private static func keychainAccount(_ userId: String) -> String { "googleDrive.\(userId)" }

    // MARK: - Sign in (needs a screen)

    /// Runs Google's consent sheet and keeps the grant. Returns the Google
    /// account's email when Google says it.
    @MainActor
    @discardableResult
    static func signIn(userId: String) async throws -> String? {
        guard let clientID else { throw AuthError.notConfigured }
        let scheme = redirectScheme(for: clientID)
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = randomVerifier()
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            // Always pick the account: the right one is the Android phone's,
            // and a silently reused Safari session may be someone else's.
            .init(name: "prompt", value: "select_account consent"),
        ]

        let callback: URL
        do {
            callback = try await runWebAuth(url: components.url!, scheme: scheme)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw AuthError.cancelled
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.first(where: { $0.name == "error" }) != nil { throw AuthError.cancelled }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value
        else { throw AuthError.failed(explain("Google didn't finish signing in. Try again.")) }

        let response = try await tokenRequest([
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        // Granular consent lets the learner untick the Drive box and still
        // come back with a token; a token that can't reach the folder is no
        // grant at all.
        if let granted = response.scope, !granted.split(separator: " ").contains(Substring(driveScope)) {
            throw AuthError.scopeNotGranted
        }
        guard let refresh = response.refresh_token else {
            throw AuthError.failed(explain("Google didn't finish signing in. Try again."))
        }
        let email = response.id_token.flatMap(emailFromIDToken)
        let data = try JSONEncoder().encode(Grant(refreshToken: refresh, email: email))
        Keychain.write(data, account: keychainAccount(userId))
        tokens.store(userId: userId, token: response.access_token, expiresIn: response.expires_in)
        return email
    }

    // MARK: - Access tokens (no screen)

    enum TokenOutcome {
        case token(String)
        /// No grant, or Google revoked it — only a screen can fix that.
        case needsSignIn
        case offline
    }

    /// A fresh access token for this account, refreshed when within a minute
    /// of expiring. `force` skips the cache (the server just said 401).
    static func accessToken(userId: String, force: Bool = false) async -> TokenOutcome {
        if !force, let cached = tokens.valid(userId: userId) { return .token(cached) }
        guard let clientID, let grant = grant(userId: userId) else { return .needsSignIn }
        do {
            let response = try await tokenRequest([
                "client_id": clientID,
                "refresh_token": grant.refreshToken,
                "grant_type": "refresh_token",
            ])
            tokens.store(userId: userId, token: response.access_token, expiresIn: response.expires_in)
            return .token(response.access_token)
        } catch TokenRequestError.invalidGrant {
            Keychain.delete(account: keychainAccount(userId))
            tokens.forget(userId: userId)
            return .needsSignIn
        } catch {
            return .offline
        }
    }

    // MARK: - Plumbing

    private struct TokenResponse: Decodable {
        var access_token: String
        var expires_in: Double?
        var refresh_token: String?
        var id_token: String?
        var scope: String?
    }

    private enum TokenRequestError: Error { case invalidGrant, http(Int, String) }

    private static func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(fields)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let text = String(decoding: data, as: UTF8.self)
            if text.contains("invalid_grant") { throw TokenRequestError.invalidGrant }
            throw TokenRequestError.http(status, text)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The email claim, for display only — nothing is authorised by it, so
    /// the signature isn't checked.
    private static func emailFromIDToken(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["email"] as? String
    }

    @MainActor
    private static func runWebAuth(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
                _ = presenter
            }
            session.presentationContextProvider = presenter
            session.start()
        }
    }

    private static let presenter = Presenter()

    private final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            ASPresentationAnchor()
        }
    }

    /// Access tokens in memory, per app account.
    private static let tokens = TokenCache()

    private final class TokenCache: @unchecked Sendable {
        private let lock = NSLock()
        private var byUser: [String: (token: String, expires: Date)] = [:]

        func valid(userId: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            guard let t = byUser[userId], t.expires.timeIntervalSinceNow > 60 else { return nil }
            return t.token
        }

        func store(userId: String, token: String, expiresIn: Double?) {
            lock.lock(); defer { lock.unlock() }
            byUser[userId] = (token, Date().addingTimeInterval(expiresIn ?? 3000))
        }

        func forget(userId: String) {
            lock.lock(); defer { lock.unlock() }
            byUser[userId] = nil
        }
    }

    /// Generic-password items, this app only, readable after first unlock so
    /// a background pass can refresh.
    private enum Keychain {
        static let service = "com.roro.futurevoice.googleDrive"

        static func read(account: String) -> Data? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var out: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
            return out as? Data
        }

        static func write(_ data: Data, account: String) {
            delete(account: account)
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            SecItemAdd(item as CFDictionary, nil)
        }

        static func delete(account: String) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
