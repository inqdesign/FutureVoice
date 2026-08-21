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

    let onReview: () -> Void
    let onUpgrade: () -> Void

    @Environment(\.dismiss) private var dismiss

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
                // Order is the recommendation. On Light the upgrade leads
                // because it is the answer to "I want to keep talking"; review
                // stays one tap away and free either way.
                if canUpgrade {
                    Button {
                        onUpgrade()
                        dismiss()
                    } label: {
                        Text("Move to Plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        onReview()
                        dismiss()
                    } label: {
                        Text("Go to Practice").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button {
                        onReview()
                        dismiss()
                    } label: {
                        Text("Go to Practice").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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

    private var title: String {
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
        switch kind {
        case .talk:
            guard let allowance else { return explain("This month's talk time is used up.") }
            return explain("All \(allowance) minutes of talk are used up.")
        case .scenes:
            guard let allowance else { return explain("This month's scenes are used up.") }
            return explain("All \(allowance) scenes are used up.")
        }
    }

    /// What to do about it — the whole reason this isn't an alert.
    private var nextLine: String {
        canUpgrade
            ? explain("Review what this month left you, or move to Plus to keep going now.")
            : explain("Review stays free, and always did.")
    }

    /// The one fact a monthly pool needs and a daily one never did: WHEN it
    /// comes back. "Tomorrow" explained itself; a date has to be said.
    private var renewalLine: String? {
        guard !renewsOn.isEmpty else { return nil }
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

#Preview("Plus") {
    Text("host")
        .sheet(isPresented: .constant(true)) {
            DailyAllowanceSheet(kind: .talk, canUpgrade: false, allowance: 1800,
                                renewsOn: "Sep 14", onReview: {}, onUpgrade: {})
        }
}
