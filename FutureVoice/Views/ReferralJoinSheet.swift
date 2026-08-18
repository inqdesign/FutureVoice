import SwiftUI

/// "Your friend joined." Shown to the INVITER when someone signs up with
/// their code — the grant lands in a balance nobody watches, so without this
/// the whole loop is invisible from the giving side.
///
/// Presented from `ReferralInbox` by `RootTabView`, after the foreground poll
/// in `ReferralService.announceJoins()` (there is no push infrastructure, so
/// the local notification and this sheet are the whole delivery).
struct ReferralJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    let join: ReferralJoin
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "person.2.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .opacity(revealed ? 1 : 0)

            VStack(spacing: 12) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                if join.minutesEarned > 0 {
                    Text(explain("+\(join.minutesEarned) min"))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .opacity(revealed ? 1 : 0)
                        .scaleEffect(revealed ? 1 : 0.85)
                }

                Text(support)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Nice")
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

    private var headline: String {
        if let name = join.friendName {
            return explain("\(name) joined with your code")
        }
        return join.friendsJoined == 1
            ? explain("A friend joined with your code")
            : explain("\(join.friendsJoined) friends joined with your code")
    }

    /// Past the cap the friend still got their half, so the line stays warm
    /// instead of reading as a rejection.
    private var support: String {
        join.minutesEarned > 0
            ? explain("They got \(ReferralService.bonusMinutes) minutes too. That's \(join.totalJoined) of your \(ReferralService.rewardedInviteCap) rewarded invites.")
            : explain("They got \(ReferralService.bonusMinutes) minutes. Your \(ReferralService.rewardedInviteCap) rewarded invites are already used.")
    }
}
