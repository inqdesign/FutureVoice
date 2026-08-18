import SwiftUI

/// "Where did my talk time go?" — the receipt behind the plan row.
///
/// A bare "49 of 60 min" is the same opacity that made beta users afraid to
/// tap anything: it says how much is gone without saying what took it. This
/// page answers both halves — what SPENT minutes (talking, Watch scenes),
/// and, just as deliberately, what didn't (every review surface, listed with
/// its count and a "Free" tag). Seeing "Review drills · 34 · Free" is the
/// only way the promise stops being marketing copy.
struct UsageDetailView: View {
    let account: AccountStatus
    /// Screenshot harness only — renders this instead of fetching, so the
    /// page can be reviewed without a signed-in account carrying real usage.
    var previewUsage: UsageBreakdown? = nil

    @State private var usage = UsageBreakdown()
    @State private var loading = true

    var body: some View {
        List {
            headerSection
            if loading && !usage.loaded {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else {
                todaySection
                scenesSection
                freeSection
                weekSection
            }
        }
        .navigationTitle("Talk time")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let previewUsage {
                usage = previewUsage
                loading = false
                return
            }
            usage = await UsageBreakdown.fetch()
            loading = false
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(account.talkTimeLabel)
                    .font(.title2.weight(.semibold))
                if let headerCaption {
                    Text(headerCaption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// The ONE thing the number above can't say for itself: whether it comes
    /// back. Nil where it has no answer to give — on Unlimited nothing counts
    /// down, so the header is already the whole story and a caption under it
    /// ("talk as much as you want") was words with no instruction in them.
    private var headerCaption: String? {
        if account.isUnlimitedPlan { return nil }
        if account.isTrialing {
            // The trial is metered as Daily whatever plan is being trialed.
            return explain("Your trial gives you \(account.tankMinutes) minutes a day, refilled at midnight.")
        }
        if account.isEntitled {
            return explain("Refills to \(account.tankMinutes) minutes every day at midnight.")
        }
        if account.hasLegacyPool {
            // A one-time pool never refills — say so, or the number reads
            // like a daily allowance that comes back tomorrow. Doesn't name
            // its source: beta leftovers and an invite bonus land here alike.
            return explain("What's left of your free talk time. It doesn't refill — only talking and Watch scenes use it.")
        }
        return explain("Talking needs a plan.")
    }

    // MARK: - Today

    /// Scenes left the talk meter on 2026-08-14: with a plan they cost one
    /// COUNT off `daily_scenes`, not seconds off the talk allowance. Without
    /// one they're still priced in seconds out of the balance.
    private var scenesMeteredByCount: Bool { account.dailyScenesCap != nil }

    /// The meters that actually spend TALK minutes for this account.
    private var talkMeters: [UsageBreakdown.Meter] {
        scenesMeteredByCount ? usage.today.filter { $0.key != "tts_scene" } : usage.today
    }

    @ViewBuilder
    private var todaySection: some View {
        Section {
            if talkMeters.isEmpty {
                Text(explain("You haven't used any talk time today."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(talkMeters) { meter in
                    row(icon: meter.icon,
                        title: meter.title,
                        detail: countLabel(meter),
                        trailing: meter.durationLabel,
                        trailingTint: .primary)
                }
                HStack {
                    Text("Total").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(totalLabel(talkMeters.reduce(0) { $0 + $1.seconds }))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Today")
        }
        // No footer. It said talking is metered by the call clock, under rows
        // that already read "Talking · 8 min" — and its second half ("Watch
        // scenes have their own count") is the Watch section sitting right
        // below it. A receipt explains itself or it isn't a receipt.
    }

    /// Watch's own allowance — a COUNT, so it gets its own section rather
    /// than a minutes row that would imply it drains the same pool.
    @ViewBuilder
    private var scenesSection: some View {
        if let cap = account.dailyScenesCap {
            Section {
                row(icon: "play.circle.fill",
                    title: explain("Watch scenes"),
                    detail: nil,
                    trailing: explain("\(account.scenesUsedToday) of \(cap)"),
                    trailingTint: .primary)
            } header: {
                Text("Watch today")
            }
        }
    }

    private func countLabel(_ meter: UsageBreakdown.Meter) -> String {
        meter.key == "tts_scene"
            ? explain("\(meter.count) lines played")
            : explain("\(meter.count) check-ins")
    }

    // MARK: - Free

    @ViewBuilder
    private var freeSection: some View {
        if !usage.freeToday.isEmpty {
            Section {
                ForEach(usage.freeToday) { item in
                    row(icon: item.icon,
                        title: item.title,
                        detail: explain("\(item.count) times today"),
                        trailing: explain("Free"),
                        trailingTint: .green)
                }
            } header: {
                Text("Used no talk time")
            }
        }
    }

    // MARK: - Last 7 days

    @ViewBuilder
    private var weekSection: some View {
        if !usage.days.isEmpty {
            Section {
                ForEach(usage.days) { day in
                    HStack(spacing: 12) {
                        Text(UsageBreakdown.dayLabel(day.date))
                            .font(.subheadline)
                            .frame(width: 92, alignment: .leading)
                        // A plain proportional bar — the shape carries the
                        // comparison, the number carries the fact.
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.accentColor.opacity(0.75))
                                .frame(width: max(2, geo.size.width * barFraction(daySeconds(day))),
                                       height: 8)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 16)
                        Text(totalLabel(daySeconds(day)))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            } header: {
                Text("Last 7 days")
            }
        }
    }

    /// Scene seconds belong to a different allowance once a plan meters them
    /// by count, so they must not be added into a "talk time per day" bar.
    private func daySeconds(_ day: UsageBreakdown.Day) -> Int {
        scenesMeteredByCount ? day.talkSeconds : day.seconds
    }

    private func barFraction(_ seconds: Int) -> Double {
        let peak = usage.days.map(daySeconds).max() ?? 0
        guard peak > 0 else { return 0 }
        return Double(seconds) / Double(peak)
    }

    // MARK: - Shared

    private func totalLabel(_ seconds: Int) -> String {
        seconds >= 60 ? explain("\(seconds / 60) min")
                      : explain("\(seconds) sec")
    }

    /// `detail` is a COUNT, not prose — "18 check-ins", "34 times today". A
    /// row with nothing to count passes nil rather than a sentence: the
    /// Watch row's caption used to explain the rules of scene counting in the
    /// slot where every other row shows a number.
    private func row(icon: String, title: String, detail: String?,
                     trailing: String, trailingTint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(trailing)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(trailingTint)
        }
    }
}
