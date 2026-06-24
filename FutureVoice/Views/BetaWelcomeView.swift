import SwiftUI

/// Shown once right after onboarding, in place of a paywall — during the beta
/// there's no subscription. Explains the free quota and how to earn more by
/// inviting friends, and surfaces the user's own code to share.
struct BetaWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "gift.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)

            VStack(spacing: 10) {
                Text("Welcome to the beta")
                    .font(.title.bold())
                Text("No subscription while we're in beta. You start with 500 credits — enough to talk, practice, and clone your voice.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Text("Running low? Invite friends.")
                    .font(.headline)
                Text("You and your friend each get 500 credits — for up to 10 friends.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if let code {
                    Text(code)
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .tracking(3)
                        .padding(.top, 2)
                    ShareLink(item: shareText(code)) {
                        Label("Share your invite", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))

            Spacer()

            VStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Text("Start practicing").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Your code is always in Settings → Invite.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .interactiveDismissDisabled(true)
        .task { code = await ReferralService.fetchMine().code }
    }

    private func shareText(_ c: String) -> String {
        "I'm practicing speaking with my own AI voice on Future Me. Join with my code \(c) and we both get bonus credits."
    }
}
