import SwiftUI
import AuthenticationServices

/// The first screen: what the app does, and the two sign-in buttons. An
/// account is needed from the start — the leaderboards carry a name, and
/// every score is read on the server.
struct SpeechWelcomeView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "music.mic")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(.tint)
                Text("Speak it like you mean it")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Read a script under a prompter that follows your voice, film it if you like, and get every take scored.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 8) {
                SignInWithAppleButton(
                    onRequest: { auth.configure($0) },
                    onCompletion: { auth.handle(result: $0) }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(Capsule())

                GoogleSignInButton(height: 52) { auth.signInWithGoogle() }

                Text("Your nawana account works here too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                if auth.isWorking { ProgressView().padding(.top, 4) }
                if let err = auth.lastError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}
