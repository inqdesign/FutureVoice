import SwiftUI

/// Me → Talk time. Four facts and nothing else (2026-09-04):
///
///   · which plan this is           — the row above this page, in `MeTab`
///   · Light: minutes used, minutes left
///   · Plus:  minutes actually talked this period
///   · invite minutes, on Light only, as a SEPARATE "+N" — never folded into
///     the figure above
///
/// The page kept growing sideways from that. It had a receipt behind it, then
/// a week of day bars, and the two numbers came from different places: the
/// header counted only what the PLAN paid for, the bars counted every metered
/// second — so one screen read "5 min this month" above "47 min" and "46 min"
/// on the two days before. Nothing on the page can disagree with anything else
/// on it now: Light's number is the pool the meter enforces, Plus's is what
/// the ledger says was spoken, and those are the only two questions each tier
/// has.
///
/// **Plus's figure is the LEDGER, not the pool.** Plus has no talk ceiling, so
/// the pool figure measures nothing — and it excluded any call that invite
/// minutes had paid for, which is how a 46-minute Sunday reported zero.
///
/// **Buying is not here.** The subscription sits on its own row at the TOP of
/// settings, because "do I have a plan at all" and "how much of it is left"
/// are different questions asked by different people — and the first is asked
/// by someone who cannot talk yet.
struct PlanPageView: View {
    let account: AccountStatus
    /// Screenshot harness only — renders this instead of fetching, so the page
    /// can be reviewed without a signed-in account carrying real usage.
    var previewUsage: UsageBreakdown? = nil

    @State private var usage = UsageBreakdown()

    var body: some View {
        List {
            Section {
                row(icon: "bolt.fill",
                    title: explain("Talk time"),
                    value: talkValue)
                // Invite minutes are time ON TOP of the pool, so they are
                // their own row and never part of the figure above — added in,
                // they would make the fraction stop adding up; left out
                // silently, the account would look smaller than it is. Only
                // where there is a pool for them to be on top of: an uncapped
                // plan cannot run out, so nothing is waiting to be topped up.
                if !isUncappedTalk, account.hasBonusMinutes {
                    row(icon: "gift.fill",
                        title: explain("Invite minutes"),
                        value: explain("+\(account.bonusMinutes) min"))
                }
                // Scenes are capped on EVERY tier — a scene plays itself, so a
                // count is the only limit there is. A real limit is never
                // hidden.
                if account.monthlyScenesCap != nil {
                    row(icon: "play.circle.fill",
                        title: explain("Watch scenes"),
                        value: sceneAllowanceValue)
                }
                if account.isEntitled, !account.renewalLabel.isEmpty {
                    // A trial's date is not a refill — it is the day it starts
                    // costing money. And a plan told to stop does not refill on
                    // that date either; it ends on it. Same date, three
                    // different promises.
                    row(icon: refillIcon,
                        title: refillTitle,
                        subtitle: account.isTrialing
                            ? explain("Cancel any time before then in the App Store")
                            : nil)
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
                // Only where minutes actually run down. On an uncapped plan
                // nothing is being spent, so this would describe a meter the
                // account doesn't have.
                if !isUncappedTalk {
                    Text(explain("Minutes buy talk time with your fluent self. Reviewing always stays free."))
                }
            }
        }
        .navigationTitle("Talk time")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Only an uncapped plan needs the ledger: every other tier's
            // number is the pool the server already reported.
            guard isUncappedTalk else { return }
            if let previewUsage { usage = previewUsage; return }
            usage = await UsageBreakdown.fetch(periodStart: account.periodStart)
        }
    }

    /// Uncapped talk is decided by the TIER, never by the cap the server
    /// reports. The deployed `talk_allowance` has no unlimited branch — it
    /// hands every plan its `monthly_seconds` — so a Plus account was told it
    /// had 1,795 of 1,800 minutes left, which is a pool that tier does not
    /// have and a number nothing enforces. Same lesson as the paywall's
    /// `isUncappedTalk`: read the plan id, and the client never waits on a
    /// server deploy to be right about what it sold.
    private var isUncappedTalk: Bool {
        account.isPlusPlan || (account.isEntitled && account.monthlyCapSeconds == nil)
    }

    /// The one number this tier is owed.
    ///
    ///   · uncapped plan — what was TALKED, from the ledger, whoever paid for
    ///     it. There is no pool to count down and no cap to count against, so
    ///     the only honest figure is the one the day bars and the home ring
    ///     are also made of.
    ///   · a pool — both halves of it: spent and left. "55 of 150" made the
    ///     reader do the subtraction, and under a row titled Talk time the
    ///     single figure was read as whichever one the reader expected.
    ///   · no plan — what is left of the one-time balance.
    private var talkValue: String {
        if isUncappedTalk {
            guard usage.loaded else { return "" }
            return explain("\(usage.periodTalkSeconds / 60) min talked")
        }
        if account.isEntitled, account.monthlyCapSeconds != nil {
            let left = max(0, account.tankMinutes - account.minutesUsedPeriod)
            return explain("\(account.minutesUsedPeriod) min used · \(left) min left")
        }
        if account.unlimited || account.hasLegacyPool {
            return explain("\(account.minutesRemaining) min")
        }
        return explain("None")
    }

    private var refillIcon: String {
        if account.isTrialing { return "calendar.badge.exclamationmark" }
        return account.cancelAtPeriodEnd ? "calendar.badge.minus" : "arrow.clockwise"
    }

    private var refillTitle: String {
        if account.isTrialing {
            return explain("Your trial becomes paid on \(account.renewalLabel)")
        }
        if account.cancelAtPeriodEnd {
            return explain("Your plan ends on \(account.renewalLabel)")
        }
        return explain("Refills on \(account.renewalLabel)")
    }

    /// Scenes are capped on EVERY tier — a scene plays itself, so a count is
    /// the only limit there is — which is why this stays a fraction even for
    /// the plan whose talking isn't counted at all.
    private var sceneAllowanceValue: String {
        guard let cap = account.monthlyScenesCap else { return "" }
        return "\(account.scenesUsedPeriod) / \(cap)"
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
