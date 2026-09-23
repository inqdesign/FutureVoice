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

/// When the welcome is due: on the first visit of an account that has never
/// talked, and AGAIN whenever the free pool GROWS (2026-09-22). A grant is
/// the one thing that raises a free account's balance, and the app had no way
/// to mention it — the sheet was gated on a one-shot flag, so time added
/// later landed silently and the learner only met it by not being stopped.
///
/// What is remembered is therefore the balance this install last SAW, not
/// whether the sheet has been shown. Spending lowers it like anything else,
/// so any later grant clears the bar; without that, time added to someone who
/// had already used most of their pool would still say nothing.
enum FreeTalkWelcome {
    /// Pre-2026-09-22 one-shot flag. Still written, and still read once — as
    /// the answer to "has this install already been congratulated", which is
    /// all it can say about an account whose earlier balance nobody recorded.
    private static let shownKey = "futurevoice.freeTalkWelcome.shown"
    private static let seenKey = "futurevoice.freeTalkWelcome.seenSeconds"

    /// Below this, a rise isn't worth a sheet — and it is a whole minute
    /// because the sheet counts in minutes and would otherwise announce a
    /// number that hasn't moved.
    private static let riseSeconds = 60

    /// Whole minutes to announce, or nil when the sheet shouldn't show.
    static func minutesToAnnounce() async -> Int? {
        let defaults = UserDefaults.standard
        guard let account = await BillingGate.shared.snapshot(),
              !account.isEntitled, !account.unlimited else { return nil }
        let balance = account.secondsBalance
        // Every pass records what it saw, including the ones that show
        // nothing — the baseline has to exist before a grant can beat it.
        defer { defaults.set(balance, forKey: seenKey) }
        guard balance >= 60 else { return nil }

        guard let seen = defaults.object(forKey: seenKey) as? Int else {
            // First pass on this install. An account that has already been
            // congratulated, or has already talked, has met its minutes by
            // using them — take the baseline and say nothing.
            guard !defaults.bool(forKey: shownKey),
                  SessionStore.shared.loadAcrossLanguages().isEmpty else {
                markShown()
                return nil
            }
            markShown()
            return balance / 60
        }
        guard balance >= seen + riseSeconds else { return nil }
        markShown()
        return balance / 60
    }

    /// Whether this install has been congratulated before — the caller logs
    /// a first welcome and a top-up as the same event with different reasons.
    static func hasBeenShown() -> Bool {
        UserDefaults.standard.bool(forKey: shownKey)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: shownKey)
    }
}
