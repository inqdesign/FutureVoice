import SwiftUI

/// Shown once right after onboarding, in place of a paywall — during the beta
/// there's no subscription. Explains the free starting quota and sets the
/// expectation that it's final: reviewing stays free, and inviting friends to
/// earn more opens up only after launch (see `BetaConfig`).
struct BetaWelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "gift.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)

            VStack(spacing: 10) {
                Text("Welcome to the beta")
                    .font(.title.bold())
                Text(explain("No subscription while we're in beta. You start with 300 credits — enough to clone your voice, talk for about a week, and try Watch + shadowing."))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Text("When you run low")
                    .font(.headline)
                Text(explain("These 300 credits are your full beta quota. When they run out, reviewing saved words, drills, and past dialogues stays free. After launch you'll pick Pro or Premium — until then, just practice."))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Start practicing").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .iPadContentPadding()
        .interactiveDismissDisabled(true)
    }
}
