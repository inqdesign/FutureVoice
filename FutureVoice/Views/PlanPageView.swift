import SwiftUI

/// Me → Talk time. What this account has left this month, and where it went.
///
/// **Buying is not here.** The subscription sits on its own row at the TOP of
/// settings (`MeTab`), because "do I have a plan at all" and "how much of it
/// is left" are different questions asked by different people — and the first
/// one is asked by someone who cannot talk yet, so it must not be three rows
/// deep inside a page about metering. This page answers only the second.
///
/// It used to be one undivided run of six rows that said WHEN the pool refills
/// three separate times — its own row, that row's subtitle, and "lands
/// automatically every cycle" under Manage plan — while the two allowances the
/// page exists to report were shaped differently from each other, one a
/// sentence and one a fraction. Sibling numbers read as siblings now, and the
/// refill date is stated once.
///
/// It lives in its own file rather than as a `private var` on `MeTab` for the
/// same reason `UsageDetailView` and `CreditGuideView` do: a subpage nobody
/// can render on its own is a subpage nobody reviews, which is how it kept the
/// word "daily" for two days after the pools went monthly.
struct PlanPageView: View {
    let account: AccountStatus

    var body: some View {
        List {
            Section {
                // The two allowances, same shape, same unit per row. Talk time
                // is a fraction like the scenes are: "132 / 150분" and "12 / 60"
                // are the same kind of fact and must not look like two kinds.
                row(icon: "bolt.fill",
                    title: explain("Talk time"),
                    value: talkAllowanceValue)
                // Watch is a SECOND allowance since 2026-08-14, and an
                // invisible allowance is the thing that made the old shared
                // meter feel dishonest. Shown only when a plan actually grants
                // scenes — a free account still pays for them in seconds, so a
                // count would be a lie there.
                if let scenes = account.monthlyScenesCap {
                    row(icon: "play.circle.fill",
                        title: explain("Watch scenes"),
                        value: "\(account.scenesUsedPeriod) / \(scenes)")
                }
                // WHEN the pool refills — in the same section as the numbers
                // it refills, because it is a fact ABOUT them. A monthly pool
                // has a date; without it the fractions above are a countdown
                // to nothing in particular.
                if account.isEntitled, !account.renewalLabel.isEmpty {
                    row(icon: "arrow.clockwise",
                        title: explain("Refills on \(account.renewalLabel)"))
                }
                // Tapping through opens the receipt: what spent minutes, and
                // what didn't. A fraction alone is the same opacity that made
                // beta users afraid to tap anything.
                NavigationLink {
                    UsageDetailView(account: account)
                } label: {
                    row(icon: "list.bullet.rectangle",
                        title: explain("See where it went"))
                }
            } header: {
                Text(account.isEntitled ? explain("This month") : explain("Left to spend"))
            }

            Section {
                NavigationLink {
                    CreditGuideView(account: account)
                } label: {
                    row(icon: "questionmark.circle",
                        title: explain("What uses talk time?"),
                        subtitle: explain("And what's always free"))
                }
                NavigationLink {
                    InviteView()
                } label: {
                    row(icon: "gift",
                        title: explain("Invite & earn talk time"),
                        subtitle: explain("\(ReferralService.bonusMinutes) minutes each, per friend"))
                }
            } footer: {
                Text(explain("Minutes buy talk time with your fluent self. Reviewing always stays free."))
            }
        }
        .navigationTitle("Talk time")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The talk row's trailing figure. A subscriber gets the fraction their
    /// pool actually is; a one-time balance has no denominator to show, and an
    /// account with neither has nothing to count at all.
    private var talkAllowanceValue: String {
        if account.unlimited { return explain("\(account.minutesRemaining) min") }
        if account.isEntitled {
            return explain("\(account.minutesRemaining) / \(account.tankMinutes) min")
        }
        if account.hasLegacyPool { return explain("\(account.minutesRemaining) min") }
        return explain("None")
    }

    /// The same shape as `MeTab`'s settings row, so a pushed page can't drift
    /// visually from the list that pushed it. `subtitle` is optional: a row
    /// whose title and trailing value already say everything must not be given
    /// a line of prose to fill the slot.
    private func row(icon: String, title: String, subtitle: String? = nil,
                     value: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Color.secondary)
                }
            }
            if let value {
                Spacer(minLength: 8)
                Text(value)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
