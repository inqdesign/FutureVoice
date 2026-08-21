import SwiftUI

/// "Where did my talk time go?" — the receipt behind the plan row.
///
/// A bare "49 of 150 min" is the same opacity that made beta users afraid to
/// tap anything: it says how much is gone without saying what took it. This
/// page answers both halves — what SPENT minutes (talking, Watch scenes),
/// and, just as deliberately, what didn't (every review surface, listed with
/// its count and a "Free" tag). Seeing "Review drills · 34 · Free" is the
/// only way the promise stops being marketing copy.
///
/// **The receipt is scoped to the BILLING PERIOD** (2026-08-20). It used to
/// open with "N of 150 min left this month" and then account for TODAY, with
/// a "Watch this month" section wedged between two today-scoped ones and a
/// 7-day chart at the bottom — three time-scales in one screen, and the one
/// the header actually counts down from was the only one never itemized. The
/// month leads now; today survives as a slice of it, because "what did the
/// call I just made cost?" is a real question, just not the page's subject.
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
                periodSection
                todaySection
                freeSection
                daysSection
            }
        }
        // "Usage", not "Talk time" — its parent page is called Talk time now
        // that buying moved out of it, and two pushes deep with the same title
        // reads as a navigation bug.
        .navigationTitle("Usage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let previewUsage {
                usage = previewUsage
                loading = false
                return
            }
            usage = await UsageBreakdown.fetch(periodStart: account.periodStart)
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

    /// The two things the number above can't say for itself: that nothing is
    /// rationed per day, and when the pool comes back.
    private var headerCaption: String? {
        if account.isTrialing {
            // The trial is metered at the Light tier's pool, pro-rated to the
            // length of the sample.
            return explain("Your trial gives you \(account.tankMinutes) minutes to use however you like.")
        }
        if account.isEntitled {
            // WHEN it comes back, and nothing else. It used to lead with "no
            // daily limit", which denies a rule this app has never had — the
            // useful half was always the date.
            return account.renewalLabel.isEmpty ? nil
                : explain("Refills on \(account.renewalLabel).")
        }
        if account.hasLegacyPool {
            // A one-time pool never refills — say so, or the number reads
            // like an allowance that comes back. Doesn't name its source:
            // beta leftovers and an invite bonus land here alike.
            return explain("What's left of your free talk time. It doesn't refill — only talking and Watch scenes use it.")
        }
        return explain("Talking needs a plan.")
    }

    // MARK: - This period

    /// Scenes left the talk meter on 2026-08-14: with a plan they cost one
    /// COUNT off `monthly_scenes`, not seconds off the talk pool. Without one
    /// they're still priced in seconds out of the balance.
    private var scenesMeteredByCount: Bool { account.monthlyScenesCap != nil }

    /// The meters that actually spend TALK minutes, out of a given split.
    private func talkMeters(_ meters: [UsageBreakdown.Meter]) -> [UsageBreakdown.Meter] {
        scenesMeteredByCount ? meters.filter { $0.key != "tts_scene" } : meters
    }

    /// Talk seconds this period. The SERVER's figure wherever it has one —
    /// `talk_allowance` is what the meter enforces, and the header above is
    /// counting down from it, so re-summing the ledger here would put two
    /// numbers for one month on one screen. The ledger only fills in for a
    /// free account, which has no pool for the server to report.
    private var periodTalkSeconds: Int {
        account.isEntitled && account.monthlyCapSeconds != nil
            ? account.secondsUsedPeriod
            : usage.periodTalkSeconds
    }

    @ViewBuilder
    private var periodSection: some View {
        Section {
            let meters = talkMeters(usage.period)
            if periodTalkSeconds <= 0 && meters.isEmpty {
                Text(explain("You haven't used any talk time yet this month."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                // One row per meter, but the TRAILING minutes on the talking
                // row come from the pool the server enforces — the ledger
                // supplies the count beside it, never the total.
                ForEach(meters) { meter in
                    row(icon: meter.icon,
                        title: meter.title,
                        detail: countLabel(meter),
                        trailing: meter.key == "talk_time"
                            ? totalLabel(periodTalkSeconds)
                            : meter.durationLabel,
                        trailingTint: .primary)
                }
                if meters.isEmpty {
                    row(icon: "phone.fill",
                        title: explain("Talking"),
                        detail: nil,
                        trailing: totalLabel(periodTalkSeconds),
                        trailingTint: .primary)
                }
                // Watch is the SECOND allowance and is counted, not timed, so
                // it sits with talking as a sibling rather than in a section
                // of its own — but keeps its own unit, which is what stops it
                // reading as minutes off the same pool.
                if let cap = account.monthlyScenesCap {
                    row(icon: "play.circle.fill",
                        title: explain("Watch scenes"),
                        detail: explain("A separate pool"),
                        trailing: explain("\(account.scenesUsedPeriod) of \(cap)"),
                        trailingTint: .primary)
                }
            }
        } header: {
            Text("This month")
        }
    }

    // MARK: - Today

    /// Today as a slice of the month above — no total line and no Watch row,
    /// because neither is the question this section answers ("what did the
    /// talking I just did cost?"). Hidden entirely on a quiet day: an empty
    /// state here would be answering a question nobody asked.
    @ViewBuilder
    private var todaySection: some View {
        let meters = talkMeters(usage.today)
        if !meters.isEmpty {
            Section {
                ForEach(meters) { meter in
                    row(icon: meter.icon,
                        title: meter.title,
                        detail: countLabel(meter),
                        trailing: meter.durationLabel,
                        trailingTint: .primary)
                }
            } header: {
                Text("Today")
            }
        }
    }

    /// The count under a meter's name, or nil where there isn't an honest
    /// one. Talking used to show "24 check-ins", which counted `talk-tick`
    /// posts — a 30-second server heartbeat, not anything the learner did.
    /// The minutes beside it are the whole fact; a second number derived from
    /// the same seconds only invited the reader to work out what it meant.
    private func countLabel(_ meter: UsageBreakdown.Meter) -> String? {
        meter.key == "tts_scene" ? explain("\(meter.count) lines played") : nil
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

    // MARK: - Recent days

    @ViewBuilder
    private var daysSection: some View {
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
                // Not "Last N days": the window now follows the billing
                // period, so any fixed number in this header would be wrong
                // for most accounts on most days.
                Text("Recent days")
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

    /// `detail` is a COUNT, not prose — "34 times today". A row with nothing
    /// to count passes nil rather than a sentence: the Watch row's caption
    /// used to explain the rules of scene counting in the slot where every
    /// other row shows a number. ("A separate pool" is the one exception, and
    /// earns it — it is the whole reason that row shows a different unit.)
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
