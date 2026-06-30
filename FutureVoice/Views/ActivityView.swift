import SwiftUI

/// Activity calendar — every day you had a conversation, marked on a month
/// grid, with your current streak, longest streak, and total active days.
/// Reached by tapping the streak on Home.
struct ActivityView: View {
    @State private var activeDays: Set<Date> = []
    @State private var displayedMonth = Date()
    @State private var currentStreak = 0
    @State private var longestStreak = 0

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                statsHeader
                calendarCard
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
        HStack(spacing: 12) {
            statTile("\(currentStreak)", "day streak", icon: "flame.fill",
                     tint: currentStreak > 0 ? .orange : .secondary)
            statTile("\(longestStreak)", "longest", icon: "trophy.fill", tint: .accentColor)
            statTile("\(activeDays.count)", "active days", icon: "calendar", tint: .accentColor)
        }
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
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let active = activeDays.contains(cal.startOfDay(for: date))
            let isToday = cal.isDateInToday(date)
            Text("\(cal.component(.day, from: date))")
                .font(.callout)
                .foregroundStyle(active ? Color.white : (isToday ? Color.accentColor : Color.primary))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    Group {
                        if active {
                            Circle().fill(Color.accentColor)
                        } else if isToday {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 38, height: 38)
                )
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 38)
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
        let days = Set(
            SessionStore.shared.load()
                .filter { $0.endedAt != nil }
                .map { cal.startOfDay(for: $0.endedAt ?? $0.startedAt) }
        )
        activeDays = days
        currentStreak = currentStreak(in: days)
        longestStreak = longestStreak(in: days)
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
