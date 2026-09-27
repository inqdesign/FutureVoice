import SwiftUI

/// This period's metered pool is spent — talk minutes, or Watch scenes.
///
/// Deliberately NOT the error alert and never a bare paywall: this learner
/// already paid, and a pool that runs out is the plan working exactly as
/// sold. So the sheet says the month's talking is done, points first at the
/// review that costs nothing, and only then — on Light, where there is still
/// something to sell — offers the way to keep going now. On Plus the upgrade
/// half is ABSENT rather than disabled: there is nothing left to offer that
/// account, and the honest answer really is the renewal date.
///
/// It replaced two alerts (talk / scenes) on 2026-08-20. An alert can hold a
/// sentence and two buttons, which was enough to state the rule but not
/// enough to offer a next thing to do — so the spent day read as a dead end
/// with an upsell attached, which is the one thing it must never be.
struct DailyAllowanceSheet: View {
    enum Kind { case talk, scenes }

    let kind: Kind

    /// This account is on Light → Plus is a real answer right now.
    /// False on Plus (and on the admin account): nothing to sell.
    let canUpgrade: Bool

    /// The pool's size, when the client knows it — the plan's own number,
    /// read live from the account snapshot rather than hardcoded.
    var allowance: Int? = nil

    /// When the pool refills ("9월 14일"). The single most useful fact at the
    /// moment someone is stopped, and the one a monthly pool has that a daily
    /// one didn't: "tomorrow" needed no date.
    var renewsOn: String = ""
    /// The plan stops on `renewsOn` instead of refilling — cancelled in the
    /// App Store. Same date, opposite promise.
    var endsInstead: Bool = false

    /// This account is TRIALING. The pool that ran out is the trial's own
    /// (35 min for the whole trial, whatever plan is being tried), so nothing
    /// here may say "this month", offer Plus (a Plus trial is metered at the
    /// same 35 min — the button would cost money and change nothing), or call
    /// `renewsOn` a refill: it is the day the subscription starts. Added
    /// 2026-09-25 after a trialer met the month's copy on day one, tapped
    /// through to the paywall three times, and left.
    var isTrial: Bool = false
    /// What the plan gives per month once the trial converts, when the client
    /// knows it (`AccountStatus.planMonthlySeconds` / 60). Nil = say only that
    /// the plan starts.
    var planMinutesAfterTrial: Int? = nil

    /// This account can buy a hundred more minutes right now (2026-09-26):
    /// entitled, counted, not trialing. The pack leads the buttons on a
    /// spent TALK pool — it is the literal answer to "I want to keep
    /// talking", and cheaper than moving plans. Never on a scenes wall
    /// (a pack buys minutes, not scenes).
    var canTopUp: Bool = false

    /// This account can still earn talk minutes by inviting someone
    /// (`InviteOffer.load` decides). Nil draws nothing — and it is never
    /// drawn on a SCENES wall, because an invite buys talk minutes and a
    /// scene pool cannot be topped up with them.
    var invite: InviteOffer? = nil

    let onReview: () -> Void
    let onUpgrade: () -> Void
    /// The minutes are on the account. The sheet dismisses itself; the
    /// caller decides whether anything resumes.
    var onTopUp: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    /// The pack answered with a live App Store price. Until it does — and
    /// for as long as the consumable is not on sale — nothing is drawn for
    /// it and the lead slot belongs to whatever comes next.
    @State private var packOnSale = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.green)

            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                VStack(spacing: 4) {
                    Text(spentLine)
                    Text(nextLine)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // Without this the stack is given a height budget by the
                // detent and silently TRUNCATES these lines to one each —
                // which reads as a half-written sentence, and hid the whole
                // second half of what the sheet is for.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

                if let renewalLine {
                    Label(renewalLine, systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                // Order is the recommendation. A minute pack leads on a spent
                // talk pool because it is the answer to "I want to keep
                // talking"; on Light the plan move follows; review stays one
                // tap away and free either way.
                if packOffered {
                    TalkTopUpButton(onAvailability: { packOnSale = $0 }) {
                        onTopUp()
                        dismiss()
                    }
                }
                if canUpgrade && !isTrial {
                    action(explain("Move to Plus"), prominent: !packLeads) {
                        onUpgrade()
                        dismiss()
                    }
                }
                action(explain("Go to Practice"),
                       prominent: !packLeads && !(canUpgrade && !isTrial)) {
                    onReview()
                    dismiss()
                }
                // LAST, and deliberately the quietest thing here: an invite
                // is the only free way to get talk minutes back, but it
                // cannot resume THIS call — the friend has to join first.
                // Above the pack or the plan move it would read as an
                // instant fix, which is the one thing it is not. The sheet
                // stays up behind the share sheet; whatever they do next is
                // still here.
                if kind == .talk, let invite {
                    InviteShareRow(offer: invite)
                }

                Button("Not now") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .padding(.top, 24)
        // `.large` is offered as a second stop rather than a taller single
        // detent: at accessibility text sizes the copy grows past any fixed
        // height, and a sheet that cannot be dragged bigger clips instead.
        .presentationDetents([.medium, .large])
    }

    /// The pack is asked for: a spent TALK pool on a counted, non-trial
    /// subscription. Asking is not selling — see `packLeads`.
    private var packOffered: Bool { canTopUp && kind == .talk && !isTrial }

    /// The pack is the first button — only once it has a PRICE. It led the
    /// row on the strength of the account alone until 2026-09-27, and with
    /// the consumable not yet on sale that handed the lead to a button that
    /// draws nothing: a Plus subscriber whose month ran out met a sheet
    /// with no primary action on it at all.
    private var packLeads: Bool { packOffered && packOnSale }

    /// One full-width button; the leading one is prominent, the rest
    /// bordered. Two styles are two view types, so this is a branch rather
    /// than a ternary on `.buttonStyle`.
    @ViewBuilder
    private func action(_ title: String, prominent: Bool,
                        _ perform: @escaping () -> Void) -> some View {
        if prominent {
            Button(action: perform) { Text(title).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else {
            Button(action: perform) { Text(title).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private var title: String {
        if isTrial {
            switch kind {
            case .talk:   return explain("That's your trial's talk time")
            case .scenes: return explain("That's your trial's scenes")
            }
        }
        switch kind {
        case .talk:   return explain("That's this month's talk time")
        case .scenes: return explain("That's this month's scenes")
        }
    }

    /// What ran out. Names the pool's own size — that is what the learner
    /// bought, and a spent allowance they can't see the size of reads as an
    /// arbitrary stop. Both tiers print it now: Plus is no longer sold as
    /// unlimited, so hiding its number would be the old concealment again.
    private var spentLine: String {
        if isTrial {
            switch kind {
            case .talk:
                guard let allowance else { return explain("The trial's talk time is used up.") }
                return explain("All \(allowance) minutes of trial talk are used up.")
            case .scenes:
                guard let allowance else { return explain("The trial's scenes are used up.") }
                return explain("All \(allowance) trial scenes are used up.")
            }
        }
        switch kind {
        case .talk:
            guard let allowance else { return explain("This month's talk time is used up.") }
            // Names the figure as the fair-use line it was sold as, not as an
            // allowance that ran out. Same number, and it was on the card
            // before the purchase — that is what keeps this from being a
            // limit sprung on someone.
            return explain("All \(allowance) minutes of talk are used up.")
        case .scenes:
            guard let allowance else { return explain("This month's scenes are used up.") }
            return explain("All \(allowance) scenes are used up.")
        }
    }

    /// What to do about it — the whole reason this isn't an alert.
    private var nextLine: String {
        if isTrial {
            // The one thing a stopped trialer needs to hear: this is the
            // trial's pool, not the plan's, and the plan is a different size.
            if endsInstead || renewsOn.isEmpty {
                return explain("Review stays free, and always did.")
            }
            if let planMinutesAfterTrial {
                return explain("Your plan starts on \(renewsOn) with \(planMinutesAfterTrial) minutes of talk a month. Review stays free until then.")
            }
            return explain("Your plan starts on \(renewsOn). Review stays free until then.")
        }
        // `packLeads`, not `canTopUp`: this sentence names the pack button,
        // and a line that says "add minutes" above a sheet with no such
        // button is the same wrong promise the prominence rule had.
        if packLeads {
            return canUpgrade
                ? explain("Add minutes to keep going now, move to Plus, or review what this month left you.")
                : explain("Add minutes to keep going now, or review what this month left you.")
        }
        return canUpgrade
            ? explain("Review what this month left you, or move to Plus to keep going now.")
            : explain("Review stays free, and always did.")
    }

    /// The one fact a monthly pool needs and a daily one never did: WHEN it
    /// comes back. "Tomorrow" explained itself; a date has to be said.
    private var renewalLine: String? {
        guard !renewsOn.isEmpty else { return nil }
        if isTrial {
            // The start date is already in `nextLine`; only a cancelled trial
            // has a separate thing to say about that day.
            return endsInstead ? explain("Your trial ends on \(renewsOn).") : nil
        }
        if endsInstead { return explain("Your plan ends on \(renewsOn).") }
        return explain("Your pool refills on \(renewsOn).")
    }
}

#Preview("Light") {
    Text("host")
        .sheet(isPresented: .constant(true)) {
            DailyAllowanceSheet(kind: .talk, canUpgrade: true, allowance: 150,
                                renewsOn: "Sep 14", onReview: {}, onUpgrade: {})
        }
}

#Preview("Trial") {
    Text("host")
        .sheet(isPresented: .constant(true)) {
            DailyAllowanceSheet(kind: .talk, canUpgrade: true, allowance: 35,
                                renewsOn: "Sep 28", isTrial: true, planMinutesAfterTrial: 150,
                                onReview: {}, onUpgrade: {})
        }
}

#Preview("Plus") {
    Text("host")
        .sheet(isPresented: .constant(true)) {
            DailyAllowanceSheet(kind: .talk, canUpgrade: false, allowance: 300,
                                renewsOn: "Sep 14", canTopUp: true,
                                invite: InviteOffer(code: "K3MQ9F", invitesUsed: 2),
                                onReview: {}, onUpgrade: {})
        }
}
