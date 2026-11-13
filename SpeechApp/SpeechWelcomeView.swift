import SwiftUI
import AuthenticationServices

/// The first screen: the prompter at work, one line on what the app does,
/// and the way in.
struct SpeechWelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                SpeechWelcomePrompter()
                    .padding(.horizontal, 28)
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Speak it like you mean it")
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Read a script under a prompter that follows your voice, film it if you like, and get every take scored.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)

                NavigationLink {
                    SpeechSignInView()
                } label: {
                    Text("Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .accentProminent()
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
        }
    }
}

/// The second step. An account is needed from the start: the leaderboards
/// carry a name, and every score is read on the server.
struct SpeechSignInView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to start")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your scores and ranks stay on this account.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            Spacer(minLength: 24)
            VStack(spacing: 8) {
                SignInWithAppleButton(
                    onRequest: { auth.configure($0) },
                    onCompletion: { auth.handle(result: $0) }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(Capsule())

                GoogleSignInButton(height: 52) { auth.signInWithGoogle() }

                Text("On nawana already? Sign in the same way and your plan comes with you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A few lines of a speech with the prompter's own colouring walking over
/// them: read words solid, the newest in the accent, the rest dim. The whole
/// line is always laid out, so only the colours move.
private struct SpeechWelcomePrompter: View {
    private static let words = """
    Good morning, everyone. Thank you for being here. \
    Today I want to share one idea that changed the way I work.
    """.split(separator: " ").map(String.init)

    private static let secondsPerWord = 0.34
    /// Beats the finished script holds before it starts over.
    private static let holdBeats = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    private func line(lit: Int) -> AttributedString {
        var result = AttributedString()
        for (index, word) in Self.words.enumerated() {
            var piece = AttributedString(index == 0 ? word : " " + word)
            piece.foregroundColor = index == lit - 1 && !reduceMotion ? Color.accentColor
                : index < lit ? Color.primary
                : Color(.tertiaryLabel)
            result += piece
        }
        return result
    }

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: Self.secondsPerWord)) { context in
            let beat = Int(context.date.timeIntervalSince(startedAt) / Self.secondsPerWord)
            let lit = reduceMotion ? Self.words.count
                : min(beat % (Self.words.count + Self.holdBeats), Self.words.count)
            Text(line(lit: lit))
                .font(.system(size: 32, weight: .semibold))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}
