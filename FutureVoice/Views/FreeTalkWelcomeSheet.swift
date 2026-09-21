import SwiftUI

/// "Congratulations — here is time to talk with your fluent self." Shown once,
/// the first time a new account reaches the Talk home with free talk time on
/// it (2026-09-21, when the 7-day trial gave way to free minutes that end in a
/// subscribe decision).
///
/// It exists because the grant is otherwise invisible: onboarding's paywall
/// steps aside for any account with a balance, so without this the learner
/// is never told the minutes exist, how many, or what happens after them.
///
/// The minutes are read off the account, never written here — the grant is a
/// server constant (`handle_new_user_credits`) and a sheet quoting its own
/// number would drift the day that constant moves.
struct FreeTalkWelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let minutes: Int
    let onStart: () -> Void
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "gift.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .opacity(revealed ? 1 : 0)

            VStack(spacing: 12) {
                Text("Congratulations!")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(explain("\(minutes) min"))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .opacity(revealed ? 1 : 0)
                    .scaleEffect(revealed ? 1 : 0.85)

                Text(explain("You can talk with your fluent self for \(minutes) minutes. Once they're used up, choose a plan."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button {
                onStart()
                dismiss()
            } label: {
                Text("Start talking")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) { revealed = true }
        }
        .presentationDetents([.medium])
    }
}

/// When the welcome is due. Once per install, only for an account that has
/// free minutes and has never talked — so an existing learner with a few
/// seconds left over is never congratulated on them after an update.
enum FreeTalkWelcome {
    private static let shownKey = "futurevoice.freeTalkWelcome.shown"

    /// Whole minutes to announce, or nil when the sheet shouldn't show.
    static func minutesToAnnounce() async -> Int? {
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return nil }
        guard let account = await BillingGate.shared.snapshot(),
              !account.isEntitled, !account.unlimited,
              account.secondsBalance >= 60 else { return nil }
        guard SessionStore.shared.loadAcrossLanguages().isEmpty else {
            // Already talked: they have met the minutes by using them.
            markShown()
            return nil
        }
        return account.secondsBalance / 60
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: shownKey)
    }
}
