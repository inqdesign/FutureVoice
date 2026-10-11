import SwiftUI
import Charts

/// Effort in depth — behind the Growth tab's "Your effort" card. A week or a
/// month: every kind of practice as a tile (total, and against the period
/// before), the picked kind's day-by-day trend, and what each day was made
/// of. The card on Growth stays small; this page is where the numbers live.
struct EffortDetailView: View {
    @EnvironmentObject private var appState: AppState

    enum Range: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
        var label: String { self == .week ? chrome("Week") : chrome("Month") }
        var previousLabel: String {
            self == .week ? explain("vs last week") : explain("vs previous 30 days")
        }
    }

    @State private var range: Range = .week
    @State private var selected: EffortCategory = .talk
    /// Two periods back to back, oldest first — the second half is the
    /// period on screen, the first half what it is compared with.
    @State private var history: [EffortDay] = []
    @State private var shadowTrend: PracticeStats.ShadowTrend?
    @State private var avgShadowScore = 0
    @AppStorage("futurevoice.dailyGoalMinutes") private var dailyGoalMinutes = 10

    private var current: ArraySlice<EffortDay> { history.suffix(range.days) }
    private var previous: ArraySlice<EffortDay> { history.dropLast(range.days).suffix(range.days) }

    /// Categories with anything in either period; talk always, so the page
    /// is never empty of its main number.
    private var shown: [EffortCategory] {
        EffortCategory.allCases.filter { c in
            c == .talk || EffortHistory.total(c, in: current) > 0 || EffortHistory.total(c, in: previous) > 0
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("", selection: $range) {
                    ForEach(Range.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                summary
                tiles
                trendPanel
                if mix.count > 0 { mixPanel }
                if avgShadowScore > 0 { shadowPanel }

                NavigationLink { ActivityView() } label: {
                    Label(explain("Calendar and routine"), systemImage: "calendar")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(explain("Your effort"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: range) { _, _ in
            if !shown.contains(selected) { selected = .talk }
        }
    }

    // MARK: - Summary

    /// The whole of it first: every minute spent studying, split into
    /// talking and everything else, before any one kind is picked apart.
    private var summary: some View {
        let activeDays = current.filter(\.isActive).count
        let talks = current.reduce(0) { $0 + $1.talks }
        let study = EffortHistory.studyMinutes(in: current)
        let before = EffortHistory.studyMinutes(in: previous)
        // App time is kept 45 days like the talk meter, so only a week has
        // a whole period before it to compare with.
        let comparable = range.days * 2 <= EffortHistory.talkReachDays
        return panel {
            HStack(alignment: .firstTextBaseline) {
                Text(explain("All activity")).font(.headline)
                Spacer()
                Text(periodText).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(study)").font(.largeTitle.weight(.bold)).monospacedDigit()
                Text(explain("min studied")).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if comparable, study != before {
                    let d = study - before
                    Text((d > 0 ? "+\(d)" : "\(d)") + " " + range.previousLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d > 0 ? Color.green : .secondary)
                }
            }
            Chart(timeEntries) { e in
                BarMark(x: .value("Day", e.day, unit: .day),
                        y: .value("Minutes", e.minutes))
                    .foregroundStyle(by: .value("Kind", e.label))
                    .cornerRadius(2)
            }
            .chartForegroundStyleScale(domain: [explain("Talking"), explain("Other practice")],
                                       range: [EffortCategory.talk.color, Color(.systemGray3)])
            .chartLegend(position: .bottom, spacing: 8)
            .chartXAxis { dayAxis }
            .frame(height: 150)
            CardDivider(inset: 0)
            HStack(spacing: 12) {
                stat(value: "\(Int(EffortHistory.total(.talk, in: current)))", label: explain("min talking"))
                stat(value: "\(EffortHistory.otherMinutes(in: current))", label: explain("min other practice"))
                stat(value: "\(talks)", label: talks == 1 ? explain("talk") : explain("talks"))
                stat(value: "\(activeDays)/\(range.days)", label: explain("days active"))
            }
            Text(explain("Time in the app, every day you opened it — talking, and everything around it: words, cards, shadowing, scenes."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct TimeEntry: Identifiable {
        let day: Date
        let label: String
        let minutes: Double
        var id: String { "\(label)\(day.timeIntervalSinceReferenceDate)" }
    }

    private var timeEntries: [TimeEntry] {
        current.flatMap { d in
            [TimeEntry(day: d.day, label: explain("Talking"), minutes: Double(d.talkSeconds) / 60),
             TimeEntry(day: d.day, label: explain("Other practice"), minutes: Double(d.otherSeconds) / 60)]
        }
    }

    private var periodText: String {
        guard let first = current.first?.day, let last = current.last?.day else { return "" }
        let f = Date.FormatStyle().month(.abbreviated).day().locale(Locale(identifier: UILanguage.chromeLanguage))
        return "\(first.formatted(f)) – \(last.formatted(f))"
    }

    // MARK: - Tiles

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(shown) { c in
                Button { withAnimation(.snappy(duration: 0.25)) { selected = c } } label: { tile(c) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func tile(_ c: EffortCategory) -> some View {
        let now = EffortHistory.total(c, in: current)
        let before = EffortHistory.total(c, in: previous)
        let isSelected = c == selected
        return VStack(alignment: .leading, spacing: 6) {
            Label(c.label, systemImage: c.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(c.color)
                .labelStyle(.titleAndIcon)
            Text(c.amountText(now))
                .font(.title3.weight(.bold)).monospacedDigit()
                .foregroundStyle(.primary)
            delta(c, now: now, before: before)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(isSelected ? c.color : .clear, lineWidth: 2))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Against the period before. Talk minutes only reach back
    /// `talkReachDays`, so a month's talk has nothing honest to compare
    /// with and says nothing rather than "+47 min" against an empty log.
    @ViewBuilder
    private func delta(_ c: EffortCategory, now: Double, before: Double) -> some View {
        if c.isTimed && range.days * 2 > EffortHistory.talkReachDays {
            Text(" ").font(.caption2)
        } else {
            let d = Int(now.rounded(.down)) - Int(before.rounded(.down))
            let text = d == 0 ? explain("same as before") : (d > 0 ? "+\(d)" : "\(d)") + " " + range.previousLabel
            Text(text)
                .font(.caption2)
                .foregroundStyle(d > 0 ? Color.green : .secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: - Trend (the picked kind, day by day)

    private var trendPanel: some View {
        let values = current.map { $0.amount(selected) }
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let best = current.max { $0.amount(selected) < $1.amount(selected) }
        return panel {
            HStack(alignment: .firstTextBaseline) {
                Label(selected.label, systemImage: selected.symbol)
                    .font(.headline).foregroundStyle(selected.color)
                Spacer()
                Text(explain("avg \(avgText(avg)) a day"))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(Array(current)) { d in
                    BarMark(x: .value("Day", d.day, unit: .day),
                            y: .value("Amount", d.amount(selected)))
                        .foregroundStyle(selected.color.gradient)
                        .cornerRadius(3)
                }
                if selected == .talk {
                    RuleMark(y: .value("Goal", Double(dailyGoalMinutes)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                } else if avg > 0 {
                    RuleMark(y: .value("Average", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis { dayAxis }
            .frame(height: 160)
            Group {
                if selected == .talk {
                    Text(explain("Minutes you actually talked, per day. The dashed line is your \(dailyGoalMinutes)-minute daily goal."))
                } else if let best, best.amount(selected) > 0 {
                    Text(explain("Dashed line: your daily average. Best day: \(best.day.formatted(Date.FormatStyle().month(.abbreviated).day().locale(Locale(identifier: UILanguage.chromeLanguage)))), \(selected.amountText(best.amount(selected)))."))
                } else {
                    Text(explain("Nothing yet in this period."))
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func avgText(_ v: Double) -> String {
        selected.isTimed ? explain("\(Int(v.rounded())) min")
                         : (v < 10 ? String(format: "%.1f", v) : "\(Int(v.rounded()))")
    }

    // MARK: - Mix (what each day was made of)

    private struct MixEntry: Identifiable {
        let day: Date
        let category: EffortCategory
        let count: Double
        var id: String { "\(category.rawValue)\(day.timeIntervalSinceReferenceDate)" }
    }

    /// Everything counted in things done, stacked. Talk stays out — minutes
    /// and counts on one axis would be one bar measured in two units.
    private var mix: [MixEntry] {
        current.flatMap { d in
            EffortCategory.allCases.filter { !$0.isTimed }.map {
                MixEntry(day: d.day, category: $0, count: d.amount($0))
            }
        }
        .filter { $0.count > 0 }
    }

    private var mixPanel: some View {
        let present = EffortCategory.allCases.filter { c in mix.contains { $0.category == c } }
        return panel {
            Text(explain("What each day was made of")).font(.headline)
            Chart(mix) { e in
                BarMark(x: .value("Day", e.day, unit: .day),
                        y: .value("Count", e.count))
                    .foregroundStyle(by: .value("Kind", e.category.label))
                    .cornerRadius(2)
            }
            .chartForegroundStyleScale(domain: present.map(\.label), range: present.map(\.color))
            .chartLegend(position: .bottom, spacing: 8)
            .chartXAxis { dayAxis }
            .frame(height: 150)
            Text(explain("Every word, expression and card you studied, shadow take, run and scene — one block each."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shadowing quality (moved from Growth's Activity panel)

    private var shadowPanel: some View {
        panel {
            HStack(alignment: .firstTextBaseline) {
                Text(explain("Shadowing score")).font(.headline)
                Spacer()
                if let d = shadowTrend?.delta {
                    Label(d >= 0 ? "+\(d)" : "\(d)",
                          systemImage: d >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d >= 0 ? Color.green : Color.orange)
                }
            }
            HStack(spacing: 16) {
                stat(value: "\(avgShadowScore)", label: explain("average of your last 10 takes"))
                if let t = shadowTrend, t.attemptsThisWeek > 0 {
                    stat(value: "\(t.attemptsThisWeek)", label: explain("takes this week"))
                }
            }
        }
    }

    // MARK: - Building blocks

    private var dayAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { _ in
            AxisGridLine()
            if range == .week {
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            } else {
                AxisValueLabel(format: .dateTime.day(), centered: true)
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func panel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func load() {
        let attempts = appState.shadowAttempts
        history = EffortHistory.days(Range.month.days * 2,
                                     sessions: SessionStore.shared.load(),
                                     shadowAttempts: attempts,
                                     drillCards: DrillStore.shared.load())
        shadowTrend = PracticeStats.shadowTrend(attempts: attempts, now: Date())
        let recent = attempts.sorted { $0.createdAt > $1.createdAt }.prefix(10).map(\.overallScore)
        avgShadowScore = recent.isEmpty ? 0 : recent.reduce(0, +) / recent.count
        #if DEBUG
        if let r = UserDefaults.standard.string(forKey: "effortRange").flatMap(Range.init(rawValue:)) { range = r }
        if let c = UserDefaults.standard.string(forKey: "effortKind").flatMap(EffortCategory.init(rawValue:)) { selected = c }
        #endif
    }
}

/// The Growth tab's one effort card: this week at a glance, everything else
/// one tap away in `EffortDetailView`.
struct EffortSummaryCard: View {
    let week: [EffortDay]
    let lastWeek: [EffortDay]

    private var talkMinutes: Int { Int(EffortHistory.total(.talk, in: week)) }
    private var activeDays: Int { week.filter(\.isActive).count }

    /// The kinds done this week, biggest change first is noise — keep the
    /// fixed order so the row reads the same every week.
    private var kinds: [EffortCategory] {
        EffortCategory.allCases.filter { !$0.isTimed && EffortHistory.total($0, in: week) > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(explain("Your effort")).font(.headline).foregroundStyle(.primary)
                Spacer()
                Text(explain("This week")).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(EffortHistory.studyMinutes(in: week))")
                            .font(.largeTitle.weight(.bold)).monospacedDigit()
                        Text(explain("min studied")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    legendLine(EffortCategory.talk.color, explain("\(talkMinutes) min talking"))
                    legendLine(Color(.systemGray3), explain("\(EffortHistory.otherMinutes(in: week)) min other practice"))
                    Text(explain("\(activeDays) of 7 days active"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                // Talking over everything else, a day per bar — the whole
                // week's time at a glance.
                Chart {
                    ForEach(week) { d in
                        BarMark(x: .value("Day", d.day, unit: .day),
                                y: .value("Minutes", Double(d.talkSeconds) / 60))
                            .foregroundStyle(EffortCategory.talk.color)
                        BarMark(x: .value("Day", d.day, unit: .day),
                                y: .value("Minutes", Double(d.otherSeconds) / 60))
                            .foregroundStyle(Color(.systemGray3))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
                .chartYAxis(.hidden)
                .frame(width: 120, height: 72)
            }
            if !kinds.isEmpty {
                CardDivider(inset: 0)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10, alignment: .leading)],
                          alignment: .leading, spacing: 10) {
                    ForEach(kinds) { c in kindChip(c) }
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func legendLine(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func kindChip(_ c: EffortCategory) -> some View {
        let now = Int(EffortHistory.total(c, in: week))
        let before = Int(EffortHistory.total(c, in: lastWeek))
        return HStack(spacing: 6) {
            Image(systemName: c.symbol).font(.caption).foregroundStyle(c.color).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    Text("\(now)").font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.primary)
                    if now > before {
                        Image(systemName: "arrow.up").font(.caption2.weight(.bold)).foregroundStyle(.green)
                    }
                }
                Text(c.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
