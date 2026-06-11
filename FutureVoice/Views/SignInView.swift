import AuthenticationServices
import SwiftUI

/// First-screen gate. Sign in with Apple is the only auth path — keeps the
/// flow zero-friction (Touch/Face ID), no third-party login form, and
/// satisfies App Store §4.8 trivially since no other login is offered.
struct SignInView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme

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

            // Drive the whole flow from these two closures. We used to wrap
            // the button in our own Button overlay + custom controller, but
            // the controller went out of scope before Apple's callback fired,
            // so completion never reached us.
            SignInWithAppleButton(
                onRequest: { request in auth.configure(request) },
                onCompletion: { result in auth.handle(result: result) }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .padding(.horizontal, 32)

            if auth.isWorking {
                ProgressView().padding(.top, 8)
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
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}
