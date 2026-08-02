import SwiftUI

/// Activity — not just WHICH days you practiced but HOW MUCH: every grid cell
/// is a heat square of minutes actually spoken (darker = more). Month view is
/// a calendar; Year view is a contribution grid of the whole year. Tapping a
/// day opens its breakdown (minutes, talks, shadow takes, drill reviews) and
/// links back to that day's talks. Reached from Home's streak and Progress.
struct ActivityView: View {
    @EnvironmentObject private var appState: AppState

    @State private var activeDays: Set<Date> = []
    @State private var displayedMonth = Date()
    @State private var viewMode: ViewMode = .month
    @State private var currentStreak = 0
    @State private var longestStreak = 0
    /// Whole minutes of USER speech per day (start-of-day keyed).
    @State private var minutesByDay: [Date: Int] = [:]
    /// The day's finished talks, newest first — the tap-through to their books.
    @State private var sessionsByDay: [Date: [Session]] = [:]
    @State private var totalSpeakingSeconds = 0.0
    @State private var drillCards: [DrillCard] = []
    @State private var selectedDay: Date?

    enum ViewMode: String, CaseIterable, Identifiable {
        case month, year
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                statsBar
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
                switch viewMode {
                case .month: monthCard
                case .year:  yearCard
                }
                // Always rendered when a day is selected — never toggled off,
                // so switching days doesn't pop the card in and out and jump
                // the scroll position.
                if let day = selectedDay {
                    dayDetailCard(day)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: load)
    }

    // MARK: - Stats (compact single row)

    private var statsBar: some View {
        HStack(spacing: 0) {
            compactStat("\(currentStreak)", "day streak", icon: "flame.fill",
                        tint: currentStreak > 0 ? .orange : .secondary)
            statDivider
            compactStat("\(longestStreak)", "longest", icon: "trophy.fill", tint: .accentColor)
            statDivider
            compactStat(totalTimeString, "total", icon: "waveform", tint: .accentColor)
            statDivider
            compactStat("\(activeDays.count)", "days", icon: "calendar", tint: .accentColor)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var statDivider: some View {
        Divider().frame(height: 26)
    }

    /// Lifetime user speech, humanized: "47m" → "3h 12m".
    private var totalTimeString: String {
        let mins = Int(totalSpeakingSeconds / 60)
        return mins < 60 ? "\(mins)m" : "\(mins / 60)h \(mins % 60)m"
    }

    private func compactStat(_ value: String, _ label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundStyle(tint)
                Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Month view

    private var monthCard: some View {
        VStack(spacing: 14) {
            periodHeader

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                    dayCell(date)
                }
            }

            HStack {
                Text(monthSummary)
                Spacer()
                heatLegend
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let comparison = periodComparison {
                Text(comparison)
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Year view (contribution grid)

    private var yearCard: some View {
        VStack(spacing: 16) {
            periodHeader

            // 12 mini-months, 3 across — the whole year on one screen, no
            // horizontal scroll.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                      spacing: 16) {
                ForEach(Array(monthsOfYear.enumerated()), id: \.offset) { _, month in
                    miniMonth(month)
                }
            }

            HStack {
                Text(yearSummary)
                Spacer()
                heatLegend
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let comparison = periodComparison {
                Text(comparison)
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func miniMonth(_ month: Date) -> some View {
        VStack(spacing: 5) {
            Text(monthShortSymbol(month))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                      spacing: 2) {
                ForEach(Array(cells(for: month).enumerated()), id: \.offset) { _, date in
                    yearCell(date)
                }
            }
        }
    }

    private var heatLegend: some View {
        HStack(spacing: 4) {
            Text("less")
            ForEach([0.0, 0.4, 0.65, 0.85, 1.0], id: \.self) { o in
                RoundedRectangle(cornerRadius: 2)
                    .fill(o == 0 ? Color(.tertiarySystemFill) : Color.accentColor.opacity(o))
                    .frame(width: 9, height: 9)
            }
            Text("more")
        }
    }

    // MARK: - Period header (shared)

    private var periodHeader: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text(periodTitle).font(.headline)
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
            }
            .disabled(!canGoNext)
            .opacity(canGoNext ? 1 : 0.3)
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let day = cal.startOfDay(for: date)
            let active = activeDays.contains(day)
            let isToday = cal.isDateInToday(date)
            let future = isFuture(day)
            let mins = minutesByDay[day] ?? 0
            let strong = active && heatOpacity(mins) >= 0.6
            let isSelected = selectedDay == day
            Text("\(cal.component(.day, from: date))")
                .font(.callout)
                // Future days are dimmed and inert — they can't be selected.
                .foregroundStyle(future ? AnyShapeStyle(.tertiary)
                                 : (strong ? AnyShapeStyle(.white)
                                    : (isSelected || isToday ? AnyShapeStyle(Color.accentColor)
                                       : AnyShapeStyle(.primary))))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    ZStack {
                        if active {
                            Circle().fill(Color.accentColor.opacity(heatOpacity(mins)))
                        } else if isToday {
                            Circle().strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                        }
                        // Selection stays in the blue family — a solid accent
                        // ring, not the old black/white one.
                        if isSelected {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 2.5)
                        }
                    }
                    .frame(width: 38, height: 38)
                )
                .contentShape(Circle())
                .onTapGesture { if !future { selectedDay = day } }
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 38)
        }
    }

    @ViewBuilder
    private func yearCell(_ date: Date?) -> some View {
        if let date {
            let day = cal.startOfDay(for: date)
            let future = isFuture(day)
            let active = activeDays.contains(day)
            let mins = minutesByDay[day] ?? 0
            let isSelected = selectedDay == day
            RoundedRectangle(cornerRadius: 2)
                // Future days are drawn faint so the grid still reads as a full
                // year, but they're inert.
                .fill(active ? Color.accentColor.opacity(heatOpacity(mins))
                      : Color(.tertiarySystemFill).opacity(future ? 0.4 : 1))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.accentColor,
                                      lineWidth: isSelected ? 1.5 : (cal.isDateInToday(date) ? 1 : 0))
                )
                .contentShape(Rectangle())
                .onTapGesture { if !future { selectedDay = day } }
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit)
        }
    }

    /// A day strictly after today — not yet lived, so not selectable.
    private func isFuture(_ day: Date) -> Bool {
        day > cal.startOfDay(for: Date())
    }

    /// Minutes → heat bucket, anchored to the ~10-minute daily-goal scale.
    private func heatOpacity(_ minutes: Int) -> Double {
        switch minutes {
        case ..<1:    return 0.25   // talked, but under a minute
        case 1..<5:   return 0.4
        case 5..<10:  return 0.65
        case 10..<20: return 0.85
        default:      return 1.0
        }
    }

    // MARK: - Day detail (tap a day)

    private func dayDetailCard(_ day: Date) -> some View {
        let mins = minutesByDay[day] ?? 0
        let daySessions = sessionsByDay[day] ?? []
        let talks = daySessions.count
        // Same per-kind numbers (and the same log-plus-backfill policy) as
        // Progress's activity mix chart.
        let log = PracticeLog.shared.day(day)
        let shadowed = max(log?.shadowReps ?? 0,
                           appState.shadowAttempts.filter { cal.isDate($0.createdAt, inSameDayAs: day) }.count)
        let reviewed = max(log?.drillReps ?? 0,
                           drillCards.filter { c in
                               c.lastReviewedAt.map { cal.isDate($0, inSameDayAs: day) } ?? false
                           }.count)

        return VStack(alignment: .leading, spacing: 12) {
            Text(day.formatted(date: .complete, time: .omitted))
                .font(.headline)
            if mins == 0 && talks == 0 && shadowed == 0 && reviewed == 0 {
                Text(explain("No practice this day."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                detailRow(icon: "waveform", tint: .accentColor,
                          text: talks > 0
                            ? "\(mins) min spoken across \(talks) talk\(talks == 1 ? "" : "s")"
                            : "\(mins) min spoken")
                if shadowed > 0 {
                    detailRow(icon: "waveform.badge.mic", tint: .green,
                              text: "\(shadowed) shadow take\(shadowed == 1 ? "" : "s")")
                }
                if reviewed > 0 {
                    detailRow(icon: "rectangle.stack", tint: .orange,
                              text: "\(reviewed) drill review\(reviewed == 1 ? "" : "s")")
                }
                // The day's talks as tappable rows — the record links straight
                // back to each talk's book for review.
                if !daySessions.isEmpty {
                    CardDivider(inset: 0)
                    ForEach(daySessions) { session in
                        NavigationLink {
                            ConversationDetailView(session: session)
                                .environmentObject(appState)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.tint)
                                    .frame(width: 24)
                                Text(session.displayTitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func detailRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(text).font(.subheadline)
        }
    }

    // MARK: - Period math

    private var periodTitle: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(viewMode == .month ? "MMMM yyyy" : "yyyy")
        return f.string(from: displayedMonth)
    }

    private var canGoNext: Bool {
        switch viewMode {
        case .month: return !cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
        case .year:  return !cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .year)
        }
    }

    private func shift(_ by: Int) {
        if by > 0, !canGoNext { return }
        let unit: Calendar.Component = viewMode == .month ? .month : .year
        displayedMonth = cal.date(byAdding: unit, value: by, to: displayedMonth) ?? displayedMonth
    }

    private var weekdaySymbols: [String] {
        let s = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(s[shift...] + s[..<shift])
    }

    /// Leading blanks + each day of the displayed month.
    private var monthCells: [Date?] { cells(for: displayedMonth) }

    /// Leading blanks + each day of the month `date` falls in.
    private func cells(for date: Date) -> [Date?] {
        let comps = cal.dateComponents([.year, .month], from: date)
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let firstWeekday = cal.component(.weekday, from: first)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            cells.append(cal.date(byAdding: .day, value: day - 1, to: first))
        }
        return cells
    }

    /// The 12 months of the displayed year, Jan → Dec.
    private var monthsOfYear: [Date] {
        let comps = cal.dateComponents([.year], from: displayedMonth)
        guard let jan1 = cal.date(from: comps) else { return [] }
        return (0..<12).compactMap { cal.date(byAdding: .month, value: $0, to: jan1) }
    }

    private func monthShortSymbol(_ month: Date) -> String {
        let idx = cal.component(.month, from: month) - 1
        let symbols = cal.shortMonthSymbols
        return symbols.indices.contains(idx) ? symbols[idx] : ""
    }

    // MARK: - Summaries

    private var monthSummary: String {
        let days = monthCells.compactMap { $0 }.map { cal.startOfDay(for: $0) }
        let active = days.filter { activeDays.contains($0) }.count
        let mins = days.reduce(0) { $0 + (minutesByDay[$1] ?? 0) }
        return "\(active) active days · \(mins) min"
    }

    private var yearSummary: String {
        let year = cal.component(.year, from: displayedMonth)
        let active = activeDays.filter { cal.component(.year, from: $0) == year }.count
        let mins = periodMinutes(displayedMonth, granularity: .year)
        return explain("\(active) active days · \(mins) min this year")
    }

    /// Minutes spoken in the calendar month/year that `date` falls in.
    private func periodMinutes(_ date: Date, granularity: Calendar.Component) -> Int {
        minutesByDay.reduce(0) { acc, entry in
            cal.isDate(entry.key, equalTo: date, toGranularity: granularity) ? acc + entry.value : acc
        }
    }

    /// "+32 min vs June" / "+120 min vs 2025" — vs the previous period.
    private var periodComparison: String? {
        let unit: Calendar.Component = viewMode == .month ? .month : .year
        guard let prev = cal.date(byAdding: unit, value: -1, to: displayedMonth) else { return nil }
        let prevMins = periodMinutes(prev, granularity: unit)
        guard prevMins > 0 else { return nil }
        let delta = periodMinutes(displayedMonth, granularity: unit) - prevMins
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(viewMode == .month ? "MMMM" : "yyyy")
        return "\(delta >= 0 ? "+" : "")\(delta) min vs \(f.string(from: prev))"
    }

    // MARK: - Data

    private func load() {
        let sessions = SessionStore.shared.load().filter { $0.endedAt != nil }

        var days: Set<Date> = []
        var minutes: [Date: Int] = [:]
        var byDay: [Date: [Session]] = [:]
        var secondsByDay: [Date: Double] = [:]
        var totalSecs = 0.0
        for session in sessions.sorted(by: { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }) {
            let day = cal.startOfDay(for: session.endedAt ?? session.startedAt)
            days.insert(day)
            byDay[day, default: []].append(session)
            let secs = session.turns.filter { $0.role == .user }
                .reduce(0.0) { $0 + Double($1.durationMs) / 1000.0 }
            secondsByDay[day, default: 0] += secs
            totalSecs += secs
        }
        for (day, secs) in secondsByDay { minutes[day] = Int(secs / 60) }

        activeDays = days
        minutesByDay = minutes
        sessionsByDay = byDay
        totalSpeakingSeconds = totalSecs
        drillCards = DrillStore.shared.load()
        currentStreak = currentStreak(in: days)
        longestStreak = longestStreak(in: days)
        // Land with a day already open so the detail card is present from the
        // start (no first-tap height jump): today if active, else most recent.
        if selectedDay == nil {
            let today = cal.startOfDay(for: Date())
            selectedDay = days.contains(today) ? today : days.max()
        }
    }

    private func currentStreak(in days: Set<Date>) -> Int {
        let today = cal.startOfDay(for: Date())
        var cursor = today
        if !days.contains(today) {
            // A streak can still be "alive" if you practiced yesterday.
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    private func longestStreak(in days: Set<Date>) -> Int {
        let sorted = days.sorted()
        var longest = 0, run = 0
        var prev: Date?
        for d in sorted {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == d {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            prev = d
        }
        return longest
    }
}
