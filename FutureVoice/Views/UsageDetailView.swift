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
                Text(headerCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var headerCaption: String {
        if account.isUnlimitedPlan {
            return explain("Talk as much as you want — nothing here counts down.")
        }
        if account.isTrialing {
            // The trial is metered as Daily whatever plan is being trialed.
            return explain("Your trial gives you \(account.tankMinutes) minutes a day, refilled at midnight.")
        }
        if account.isEntitled {
            return explain("Refills to \(account.tankMinutes) minutes every day at midnight.")
        }
        if account.hasLegacyPool {
            // Beta leftovers never refill — say so, or the number reads like
            // a daily allowance that comes back tomorrow.
            return explain("What's left of your beta talk time. It doesn't refill — only talking and Watch scenes use it.")
        }
        return explain("Talking needs a plan. Reviewing, replaying and building situations stay free either way.")
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
        } footer: {
            Text(scenesMeteredByCount
                 ? explain("Talking is metered by the call clock. Watch scenes have their own daily count and never touch these minutes.")
                 : explain("Talking is metered by the call clock; a Watch scene costs the length of the scene it plays."))
        }
    }

    /// Watch's own allowance — a COUNT, so it gets its own section rather
    /// than a minutes row that would imply it drains the same pool.
    @ViewBuilder
    private var scenesSection: some View {
        if let cap = account.dailyScenesCap {
            Section {
                row(icon: "play.circle.fill",
                    title: chrome("Watch scenes"),
                    detail: explain("Replaying a scene you've already watched is free."),
                    trailing: chrome("\(account.scenesUsedToday) of \(cap)"),
                    trailingTint: .primary)
            } header: {
                Text("Watch today")
            } footer: {
                Text(explain("A scene costs one count however long it runs, and the count resets every day."))
            }
        }
    }

    private func countLabel(_ meter: UsageBreakdown.Meter) -> String {
        meter.key == "tts_scene"
            ? chrome("\(meter.count) lines played")
            : chrome("\(meter.count) check-ins")
    }

    // MARK: - Free

    @ViewBuilder
    private var freeSection: some View {
        if !usage.freeToday.isEmpty {
            Section {
                ForEach(usage.freeToday) { item in
                    row(icon: item.icon,
                        title: item.title,
                        detail: chrome("\(item.count) times today"),
                        trailing: chrome("Free"),
                        trailingTint: .green)
                }
            } header: {
                Text("Used no talk time")
            } footer: {
                Text(explain("Reviewing, replaying, and building situations never cost talk time — no matter how much you do."))
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
            } footer: {
                Text(scenesMeteredByCount
                     ? explain("Talk time per day. Watch scenes are counted separately and never appear here.")
                     : explain("Total talk time per day: calls plus the scenes you watched."))
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
        seconds >= 60 ? chrome("\(seconds / 60) min")
                      : chrome("\(seconds) sec")
    }

    private func row(icon: String, title: String, detail: String,
                     trailing: String, trailingTint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(trailing)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(trailingTint)
        }
    }
}
