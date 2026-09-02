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

    /// True while the session belongs to an ANONYMOUS user.
    ///
    /// The voice-clone step opens one of these silently so the fluent voice can
    /// be BUILT AND HEARD before anyone is asked to sign up — the edge
    /// functions verify a JWT, so without a session there is no way to
    /// synthesize a single word, and the app's strongest moment would stay
    /// locked behind a sign-in for a thing the user hasn't heard yet.
    ///
    /// It is a session, not an account: nothing identifies it, it can't be
    /// restored on another device, and it is deleted server-side along with its
    /// clone if it's still unclaimed days later. So every gate that means "does
    /// this person have an account" must ask `isSignedIn`, never `session !=
    /// nil` — that's the difference between finishing onboarding and finishing
    /// it into an account nobody can ever sign back into.
    var isAnonymous: Bool { session?.user.isAnonymous ?? false }

    /// A session with a real account behind it.
    var isSignedIn: Bool { session != nil && !isAnonymous }

    /// Open the pre-signup session. No-op once any session exists.
    func startAnonymousSession() async throws {
        guard session == nil else { return }
        session = try await SupabaseProvider.shared.auth.signInAnonymously()
    }

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
            // NOTE for the next supabase-swift MAJOR (warned about at runtime
            // on 2.47): today `.initialSession` is emitted only after a
            // refresh attempt, so what arrives here is valid or nil. The new
            // behaviour (`emitLocalSessionAsInitialSession: true`) emits the
            // locally stored session AS IS — possibly expired. Assigning that
            // unguarded would make `isSignedIn` true on dead credentials, and
            // `RootView` gates onboarding on exactly that: the learner would
            // land in the app with a session no edge function will accept.
            // When upgrading, drop an expired `.initialSession` here.
            // https://github.com/supabase/supabase-swift/pull/822
            self.session = change.session
            // A code held back by a network blip during sign-up had only one
            // retry trigger — another sign-in, which a signed-in user never
            // performs, so the invite was silently lost for good. Every
            // session event is a retry now; it's a no-op unless a code is
            // actually pending, and the server's ALREADY_REDEEMED guard makes
            // a duplicate attempt harmless.
            // Never under an anonymous session: a code redeemed there is spent,
            // and if Apple later signs the user into a DIFFERENT account (the
            // reinstall case in `linkOrSignIn`) the invite would have been
            // burned on a user nobody can sign into again.
            if isSignedIn, Self.pendingInviteCode() != nil {
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
                let credentials = OpenIDConnectCredentials(provider: .apple,
                                                           idToken: idToken, nonce: nonce)
                do {
                    // Anonymous session on stage: LINK Apple to it instead of
                    // signing in fresh. Same user id, so the voice clone,
                    // consent record and credit row minted before sign-up all
                    // stay attached — signing in fresh would mint a second user
                    // and orphan the voice the user just heard and accepted.
                    let session: Auth.Session
                    if self.isAnonymous {
                        session = try await self.linkOrSignIn(credentials)
                    } else {
                        session = try await SupabaseProvider.shared.auth
                            .signInWithIdToken(credentials: credentials)
                    }
                    self.session = session
                    await self.redeemPendingInviteIfAny()
                } catch {
                    self.lastError = "Supabase exchange failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Google (OAuth web flow)

    /// The OAuth callback for web-flow sign-ins. The `futurevoice` scheme is
    /// registered in Info.plist and `futurevoice://login` is on Supabase's
    /// redirect allow-list; ASWebAuthenticationSession captures it directly,
    /// so no onOpenURL handling is involved.
    static let oauthCallbackURL = URL(string: "futurevoice://login")!

    /// Google sign-in via Supabase's OAuth web flow — the same web client the
    /// site and the Android app use, so no extra SDK and the same Google
    /// account resolves to the same Supabase user everywhere.
    ///
    /// Mirrors the Apple paths exactly: an anonymous session on stage gets the
    /// identity LINKED to it (the voice clone, consent record and credit row
    /// minted before sign-up stay attached), and a refused link means the
    /// identity already owns an account (the reinstall case) — signing into
    /// that account is what the person wants, and the throwaway clone under
    /// the anonymous user is collected by the nightly cleanup.
    func signInWithGoogle() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                if isAnonymous {
                    do {
                        let linkURL = try await SupabaseProvider.shared.auth
                            .getLinkIdentityURL(provider: .google,
                                                redirectTo: Self.oauthCallbackURL).url
                        let callback = try await Self.runWebAuth(url: linkURL)
                        session = try await SupabaseProvider.shared.auth.session(from: callback)
                        adoptedExistingAccount = false
                    } catch let error as ASWebAuthenticationSessionError
                        where error.code == .canceledLogin {
                        return   // backed out of the sheet — never open a second one
                    } catch {
                        session = try await SupabaseProvider.shared.auth
                            .signInWithOAuth(provider: .google,
                                             redirectTo: Self.oauthCallbackURL)
                        adoptedExistingAccount = true
                    }
                } else {
                    session = try await SupabaseProvider.shared.auth
                        .signInWithOAuth(provider: .google,
                                         redirectTo: Self.oauthCallbackURL)
                }
                await redeemPendingInviteIfAny()
            } catch let error as ASWebAuthenticationSessionError
                where error.code == .canceledLogin {
                // Same swallow as the Apple path's user-cancel.
            } catch {
                lastError = "Google sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    /// Runs one ASWebAuthenticationSession and hands back the callback URL.
    /// Only the LINK path needs this — plain sign-in uses the SDK's built-in
    /// flow, but `linkIdentity`'s default opens Safari and would need a
    /// deep-link round trip; running the session ourselves keeps both paths
    /// inside one in-app sheet.
    @MainActor
    private static func runWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let webSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: oauthCallbackURL.scheme
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
                _ = webAuthPresenter   // keep the presenter alive until completion
            }
            webSession.presentationContextProvider = webAuthPresenter
            webSession.start()
        }
    }

    private static let webAuthPresenter = WebAuthPresenter()

    private final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            ASPresentationAnchor()
        }
    }

    /// Attach Apple to the anonymous user, falling back to a plain sign-in.
    ///
    /// The fallback is the returning user who reinstalled: their Apple identity
    /// already belongs to an account, so linking is refused server-side. Signing
    /// them into that account is exactly right — it holds their real voice,
    /// history and subscription. What's lost is the throwaway clone recorded
    /// minutes ago under the anonymous user, which the nightly cleanup collects.
    private func linkOrSignIn(_ credentials: OpenIDConnectCredentials) async throws -> Auth.Session {
        do {
            let session = try await SupabaseProvider.shared.auth
                .linkIdentityWithIdToken(credentials: credentials)
            adoptedExistingAccount = false
            return session
        } catch {
            let session = try await SupabaseProvider.shared.auth
                .signInWithIdToken(credentials: credentials)
            adoptedExistingAccount = true
            return session
        }
    }

    /// Set when the Apple sign-in landed on a DIFFERENT user than the anonymous
    /// one that was on stage — i.e. the identity was already an account. The
    /// voice-clone flow reads it to rebuild the clone under the account that
    /// actually owns the session now; anything minted under the throwaway user
    /// is about to be cleaned up server-side.
    @Published private(set) var adoptedExistingAccount = false

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
            let result = try await ReferralService.redeem(code: code)
            UserDefaults.standard.removeObject(forKey: key)
            redeemedInviteBalance = result.balance
            redeemedCompPlanId = result.compPlanId
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

    /// Non-nil when the code was a COMP code: it handed over a subscription
    /// instead of minutes, so the confirmation has to name the plan rather
    /// than a bonus that was never granted.
    @Published var redeemedCompPlanId: String?

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
