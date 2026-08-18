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
    /// False until the very first session restore attempt finishes. RootView
    /// shows a blank launch background until this flips, so a returning user
    /// goes straight to Home instead of flashing the Welcome screen while the
    /// stored session is still being restored.
    @Published private(set) var didResolveInitialSession = false
    @Published private(set) var isWorking = false
    @Published var lastError: String?

    private(set) var currentRawNonce: String?

    /// Where the Apple-provided given name is stashed at first sign-in, for
    /// persona setup to prefill. Read once, then it's just a fallback.
    static let appleNameKey = "futurevoice.appleName"

    /// An invite code the user typed on the Welcome screen BEFORE signing in.
    /// Redeeming needs an authenticated session, so we hold the code here and
    /// apply it the moment sign-in succeeds.
    static let pendingInviteKey = "futurevoice.pendingInviteCode"

    /// The code still waiting to be applied, if any. The Welcome screen takes
    /// it several steps before the sign-up button exists, so the account step
    /// shows it back — an invisible pending code reads as a lost one.
    static func pendingInviteCode() -> String? {
        let code = UserDefaults.standard.string(forKey: pendingInviteKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return code.isEmpty ? nil : code
    }

    override init() {
        super.init()
        Task { await loadInitialSession() }
        Task { await observeSession() }
    }

    private func loadInitialSession() async {
        session = try? await SupabaseProvider.shared.auth.session
        didResolveInitialSession = true
    }

    private func observeSession() async {
        for await change in SupabaseProvider.shared.auth.authStateChanges {
            self.session = change.session
            // A code held back by a network blip during sign-up had only one
            // retry trigger — another sign-in, which a signed-in user never
            // performs, so the invite was silently lost for good. Every
            // session event is a retry now; it's a no-op unless a code is
            // actually pending, and the server's ALREADY_REDEEMED guard makes
            // a duplicate attempt harmless.
            if change.session != nil, Self.pendingInviteCode() != nil {
                await redeemPendingInviteIfAny()
            }
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

            // Apple returns the user's name ONLY on the first authorization,
            // and only on the credential (never from the ID token / Supabase).
            // Capture it now so persona setup can prefill the name field —
            // there's no second chance to read it.
            if let name = credential.fullName {
                let full = PersonNameComponentsFormatter().string(from: name)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let given = name.givenName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let chosen = (given?.isEmpty == false ? given! : full)
                if !chosen.isEmpty {
                    UserDefaults.standard.set(chosen, forKey: Self.appleNameKey)
                }
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
                    await self.redeemPendingInviteIfAny()
                } catch {
                    self.lastError = "Supabase exchange failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Redeem a Welcome-screen invite code once we have a session. Server-side
    /// guards handle self-referral / already-redeemed / invalid; we just clear
    /// the pending code on any permanent outcome and publish a note the app can
    /// surface. A transient failure keeps the code so a later sign-in retries.
    private func redeemPendingInviteIfAny() async {
        let key = Self.pendingInviteKey
        let code = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !code.isEmpty else { return }
        do {
            let balance = try await ReferralService.redeem(code: code)
            UserDefaults.standard.removeObject(forKey: key)
            redeemedInviteBalance = balance
        } catch ReferralService.RedeemError.unknown {
            // Could be a network blip — keep the code for a future attempt.
        } catch {
            // Permanent (invalid / self / already redeemed): stop retrying.
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Set once when a Welcome invite code redeems successfully — the new
    /// balance, so the app can confirm "invite applied" after onboarding.
    @Published var redeemedInviteBalance: Int?

    /// Signs THIS install out. Scope is `.local` on purpose.
    ///
    /// supabase-swift defaults `signOut()` to `.global`, which revokes every
    /// refresh token the user holds — including other installs (the `.dev`
    /// build sitting beside the TestFlight one). Those installs are then stuck:
    /// they still hold a stored session so the UI says "signed in", but the
    /// token can no longer refresh, so every request 401s, `user_credits` reads
    /// back empty and renders as a 0 balance, and their own sign-out button
    /// needs the very token that was revoked — leaving no in-app way out.
    /// A sign-out here must only affect the install the user tapped it in.
    ///
    /// `.local` also cannot fail on a dead token: the session is cleared even
    /// offline, so the button always works.
    func signOut() async {
        try? await SupabaseProvider.shared.auth.signOut(scope: .local)
        session = nil
        Analytics.reset()   // drop identity so the next user isn't merged in
    }

    /// Server-side account deletion (Apple Guideline 5.1.1(v)). The Edge
    /// Function deletes the ElevenLabs clones, cancels any Stripe web
    /// subscription, and destroys the auth user — every user table cascades
    /// from auth.users. On success the server-side user no longer exists, so
    /// we only clear the LOCAL session; a server sign-out would just 401.
    /// Throws on failure so the UI can show the error and keep the account.
    func deleteAccount() async throws {
        isWorking = true
        defer { isWorking = false }
        try await SupabaseProvider.shared.functions.invoke("account-delete")
        try? await SupabaseProvider.shared.auth.signOut(scope: .local)
        session = nil
        Analytics.reset()   // drop identity on account deletion
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
