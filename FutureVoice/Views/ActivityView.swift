import SwiftUI

/// Activity calendar — not just WHICH days you practiced but HOW MUCH:
/// the month grid is a heat map of minutes actually spoken (darker = more),
/// tapping a day opens its breakdown (minutes, talks, shadow takes, drill
/// reviews), and the header carries streaks plus total speaking time.
/// Reached by tapping the streak on Home and from Progress.
struct ActivityView: View {
    @EnvironmentObject private var appState: AppState

    @State private var activeDays: Set<Date> = []
    @State private var displayedMonth = Date()
    @State private var currentStreak = 0
    @State private var longestStreak = 0
    /// Whole minutes of USER speech per day (start-of-day keyed).
    @State private var minutesByDay: [Date: Int] = [:]
    /// The day's finished talks, newest first — the tap-through to their books.
    @State private var sessionsByDay: [Date: [Session]] = [:]
    @State private var totalSpeakingSeconds = 0.0
    @State private var drillCards: [DrillCard] = []
    @State private var selectedDay: Date?

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                statsHeader
                calendarCard
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
        .onAppear(perform: load)
    }

    // MARK: - Stats

    private var statsHeader: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            statTile("\(currentStreak)", "day streak", icon: "flame.fill",
                     tint: currentStreak > 0 ? .orange : .secondary)
            statTile("\(longestStreak)", "longest streak", icon: "trophy.fill", tint: .accentColor)
            statTile(totalTimeString, "total speaking", icon: "waveform", tint: .accentColor)
            statTile("\(activeDays.count)", "active days", icon: "calendar", tint: .accentColor)
        }
    }

    /// Lifetime user speech, humanized: "47m" → "3h 12m".
    private var totalTimeString: String {
        let mins = Int(totalSpeakingSeconds / 60)
        return mins < 60 ? "\(mins)m" : "\(mins / 60)h \(mins % 60)m"
    }

    private func statTile(_ value: String, _ label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(tint)
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                }
                .disabled(isCurrentMonth)
                .opacity(isCurrentMonth ? 0.3 : 1)
            }

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

            // Month roll-up + how to read the heat.
            HStack {
                Text(monthSummary)
                Spacer()
                Text("darker = more minutes")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let comparison = monthComparison {
                Text(comparison)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var monthSummary: String {
        let days = monthCells.compactMap { $0 }.map { cal.startOfDay(for: $0) }
        let active = days.filter { activeDays.contains($0) }.count
        let mins = days.reduce(0) { $0 + (minutesByDay[$1] ?? 0) }
        return "This month: \(active) active days · \(mins) min spoken"
    }

    /// Minutes spoken in any calendar month.
    private func monthMinutes(_ month: Date) -> Int {
        minutesByDay.reduce(0) { acc, entry in
            cal.isDate(entry.key, equalTo: month, toGranularity: .month) ? acc + entry.value : acc
        }
    }

    /// "+32 min vs June" — only once the previous month has anything to
    /// compare against.
    private var monthComparison: String? {
        guard let prev = cal.date(byAdding: .month, value: -1, to: displayedMonth) else { return nil }
        let prevMins = monthMinutes(prev)
        guard prevMins > 0 else { return nil }
        let delta = monthMinutes(displayedMonth) - prevMins
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM")
        return "\(delta >= 0 ? "+" : "")\(delta) min vs \(f.string(from: prev))"
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let day = cal.startOfDay(for: date)
            let active = activeDays.contains(day)
            let isToday = cal.isDateInToday(date)
            let mins = minutesByDay[day] ?? 0
            let strong = active && heatOpacity(mins) >= 0.6
            let isSelected = selectedDay == day
            Text("\(cal.component(.day, from: date))")
                .font(.callout)
                .foregroundStyle(strong ? Color.white : (isToday ? Color.accentColor : Color.primary))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    ZStack {
                        if active {
                            Circle().fill(Color.accentColor.opacity(heatOpacity(mins)))
                        } else if isToday {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                        if isSelected {
                            Circle().strokeBorder(Color.primary, lineWidth: 2)
                        }
                    }
                    .frame(width: 38, height: 38)
                )
                .contentShape(Circle())
                .onTapGesture {
                    selectedDay = (selectedDay == day) ? nil : day
                }
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 38)
        }
    }

    /// Minutes → heat bucket, anchored to the ~10-minute daily-goal scale.
    private func heatOpacity(_ minutes: Int) -> Double {
        switch minutes {
        case ..<1:   return 0.25   // talked, but under a minute
        case 1..<5:  return 0.4
        case 5..<10: return 0.65
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
                Text("No practice this day.")
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
                    Divider()
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

    // MARK: - Month math

    private var monthTitle: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: displayedMonth)
    }

    private var isCurrentMonth: Bool {
        cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private var weekdaySymbols: [String] {
        let s = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(s[shift...] + s[..<shift])
    }

    /// Leading blanks + each day of the displayed month.
    private var monthCells: [Date?] {
        let comps = cal.dateComponents([.year, .month], from: displayedMonth)
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

    private func shiftMonth(_ by: Int) {
        if by > 0, isCurrentMonth { return }
        displayedMonth = cal.date(byAdding: .month, value: by, to: displayedMonth) ?? displayedMonth
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
        // Land with today's story open when there is one.
        if selectedDay == nil {
            let today = cal.startOfDay(for: Date())
            if days.contains(today) { selectedDay = today }
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
