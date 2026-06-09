import AuthenticationServices
import SwiftUI

/// First-screen gate. Sign in with Apple is the only auth path — keeps the
/// flow zero-friction (Touch/Face ID), no third-party login form, and
/// satisfies App Store §4.8 trivially since no other login is offered.
struct SignInView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Text("Future Me")
                    .font(.system(size: 34, weight: .bold))
                Text("Practice speaking with your future, fluent self.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            SignInWithAppleButton(
                onRequest: { _ in
                    // No-op: AuthService configures the request when it
                    // creates the ASAuthorizationController itself. We use
                    // this SwiftUI button only for its native styling +
                    // accessibility — the actual nonce/scope setup lives
                    // in AuthService so the same code path works from any
                    // entry point (e.g. re-auth after sign-out).
                },
                onCompletion: { _ in }
            )
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .padding(.horizontal, 32)
            .overlay {
                // Swallow taps and re-route through AuthService so the
                // nonce flow stays centralized. SignInWithAppleButton's
                // built-in handler doesn't give us the nonce we need.
                Button("Sign in with Apple") {
                    auth.startSignInWithApple()
                }
                .opacity(0.001) // invisible but tappable
                .frame(height: 50)
                .padding(.horizontal, 32)
            }

            if auth.isWorking {
                ProgressView().tint(.white).padding(.top, 8)
            }
            if let err = auth.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
