import Auth
import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

/// Sign in with Apple → exchange the Apple ID token for a Supabase session.
///
/// We use Supabase's `signInWithIdToken` rather than OAuth web flow because
/// Apple Sign-In on iOS already gives us a verified ID token natively, so
/// there's no reason to round-trip through a browser.
///
/// Implementation note: this used to manage its own ASAuthorizationController
/// + delegate, but the controller went out of scope before Apple's callback
/// could fire, so the sign-in sheet completed but nothing happened. The
/// SwiftUI `SignInWithAppleButton` view retains the underlying controller
/// for us, so we drive the flow from its `onRequest` / `onCompletion`
/// closures and this class just becomes a session store + nonce holder.
@MainActor
final class AuthService: NSObject, ObservableObject {
    @Published private(set) var session: Auth.Session?
    @Published private(set) var isWorking = false
    @Published var lastError: String?

    private(set) var currentRawNonce: String?

    override init() {
        super.init()
        Task { await loadInitialSession() }
        Task { await observeSession() }
    }

    private func loadInitialSession() async {
        session = try? await SupabaseProvider.shared.auth.session
    }

    private func observeSession() async {
        for await change in SupabaseProvider.shared.auth.authStateChanges {
            self.session = change.session
        }
    }

    /// Called by `SignInWithAppleButton`'s `onRequest` closure. Generates a
    /// fresh nonce, hashes it into the request, and stashes the raw nonce
    /// so we can hand it to Supabase together with Apple's ID token.
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentRawNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Called by `SignInWithAppleButton`'s `onCompletion`. Validates the
    /// credential shape and exchanges the ID token for a Supabase session.
    func handle(result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // User-canceled is also delivered as an error — swallow it so
            // backing out of the sheet doesn't scare anyone.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            lastError = error.localizedDescription

        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                lastError = "Apple did not return an ID token"
                return
            }

            let nonce = currentRawNonce
            currentRawNonce = nil

            Task {
                self.isWorking = true
                defer { self.isWorking = false }
                do {
                    let session = try await SupabaseProvider.shared.auth.signInWithIdToken(
                        credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                    )
                    self.session = session
                } catch {
                    self.lastError = "Supabase exchange failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func signOut() async {
        try? await SupabaseProvider.shared.auth.signOut()
        session = nil
    }

    // MARK: - Nonce helpers (Apple-recommended boilerplate)

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed: \(status)")
            }
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
