import SwiftUI
import UIKit

/// Inviting a friend as an ANSWER to a spent talk pool.
///
/// The minutes have always worked this way — `redeem_referral` grants 30 min
/// to both sides and `consume_metered_seconds` spends `user_credits.balance`
/// BEFORE the plan's pool (`20260821100000`), so a subscriber whose month has
/// run out starts talking again the moment a friend joins. What was missing
/// was anyone ever saying so at the one moment it answers a question: the
/// invite lived behind Me → Usage → "Invite & earn talk time", two taps from
/// a learner who has just been stopped mid-call.
///
/// Two surfaces, one offer (`InviteOffer`):
///   · `InviteShareRow` — a quiet line in `DailyAllowanceSheet`, UNDER the
///     things that work right now. An invite cannot resume this call: the
///     friend has to join first. Putting it above the pack or the plan move
///     would sell a wait as an instant fix.
///   · `InviteMinutesCard` — on Me → Usage, where it takes the place of the
///     ordinary invite row for as long as the pool is empty.
///
/// Three things decide whether it is offered at all, and each is a way the
/// card could otherwise lie — see `InviteOffer.load`.
@MainActor
struct InviteOffer {
    /// This account's own code. Without it there is nothing to share.
    let code: String
    /// How many friends have joined with it, for the cap below.
    let invitesUsed: Int

    var bonusMinutes: Int { ReferralService.bonusMinutes }

    /// Nil = do not offer. The three gates:
    ///
    ///   · **An entitled account only.** A free account's answer to "no talk
    ///     time" is the paywall; offering it a way around the purchase is
    ///     the one place this would cost the product real money. A TRIAL
    ///     counts as entitled and is deliberately included (user decision,
    ///     2026-09-27) — everything else on that sheet stands down for a
    ///     trialer, so without this a spent trial has nothing at all to do,
    ///     and step 1 spends the balance during a trial exactly as it does
    ///     after one, so the offer is true there.
    ///   · **A COUNTED pool only.** Step 1 of `consume_metered_seconds`
    ///     skips the balance on an uncapped plan (the Plus rows sold before
    ///     2026-09-26) — the minutes are granted and never spent — so on
    ///     those three accounts the whole card is false.
    ///   · **Rewards left.** The inviter is paid for their first
    ///     `rewardedInviteCap` friends and nothing after; past it the friend
    ///     still gets their 30 minutes, but this card promises the LEARNER's,
    ///     so it stops being shown.
    static func load(for account: AccountStatus) async -> InviteOffer? {
        guard account.isEntitled, !account.isUncappedTalk else { return nil }
        let referral = await ReferralService.fetchMine()
        guard let code = referral.code,
              referral.invitesUsed < ReferralService.rewardedInviteCap else { return nil }
        return InviteOffer(code: code, invitesUsed: referral.invitesUsed)
    }
}

/// The spent-pool sheet's invite line. A `ShareLink`, so one tap is the share
/// sheet with the App Store card and the code in its message — never a page
/// about inviting, which is one more screen between being stopped and doing
/// the thing.
struct InviteShareRow: View {
    let offer: InviteOffer

    var body: some View {
        ShareLink(item: ReferralService.appStoreURL,
                  subject: Text("nawana"),
                  message: Text(ReferralService.shareMessage(code: offer.code))) {
            Label(explain("Invite a friend · \(offer.bonusMinutes) min each"),
                  systemImage: "gift")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .padding(.top, 2)
    }
}

/// Me → Usage, while the month's pool is empty. Carries what the row it
/// replaces could not: what the offer is, the code itself (a friend sitting
/// next to you types it; the share message is for everyone else), and the
/// share action.
struct InviteMinutesCard: View {
    let offer: InviteOffer

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(explain("\(offer.bonusMinutes) minutes each, together"),
                  systemImage: "gift.fill")
                .font(.headline)
            Text(explain("When a friend joins with your code, you both get \(offer.bonusMinutes) minutes — and invite minutes are spent before the month's pool."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(offer.code)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .tracking(2)
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = offer.code
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(explain("Copy code"))
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill)))

                ShareLink(item: ReferralService.appStoreURL,
                          subject: Text("nawana"),
                          message: Text(ReferralService.shareMessage(code: offer.code))) {
                    Text(explain("Share invite"))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            Text(explain("Rewarded for your first \(ReferralService.rewardedInviteCap) friends."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

#Preview("Card") {
    NavigationStack {
        List {
            Section {
                InviteMinutesCard(offer: InviteOffer(code: "K3MQ9F", invitesUsed: 2))
            }
        }
        .navigationTitle("Usage")
    }
}
