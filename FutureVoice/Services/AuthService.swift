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
@MainActor
final class AuthService: NSObject, ObservableObject {
    @Published private(set) var session: Auth.Session?
    @Published private(set) var isWorking = false
    @Published var lastError: String?

    private var currentNonce: String?

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

    /// Call from a SwiftUI button. Builds an `ASAuthorizationAppleIDRequest`
    /// with a hashed nonce — the raw nonce is then passed to Supabase along
    /// with the identityToken so Supabase can verify replay protection.
    func startSignInWithApple() {
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
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

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            Task { @MainActor in self.lastError = "Apple did not return an ID token" }
            return
        }

        Task { @MainActor in
            self.isWorking = true
            defer { self.isWorking = false }
            do {
                let nonce = self.currentNonce
                self.currentNonce = nil
                let session = try await SupabaseProvider.shared.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                self.session = session
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        // User cancel is also an error here — swallow it quietly so the UI
        // doesn't show a scary message every time they back out.
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
        Task { @MainActor in self.lastError = error.localizedDescription }
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Find the active foreground window. Using `.first` on UIApplication's
        // windows is unsafe in multi-scene apps, but FutureVoice is single-scene.
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
