import SwiftUI

/// The week as a picture: Monday to Sunday, one column a day, one bar per
/// thing planned in the day's order — the same reading as My routine's
/// promise card, small enough for the end of setup. Talks are drawn taller,
/// because they are the time; everything else is a count. The weekly test
/// sits on its own day from its own settings.
struct RoutineWeekPicture: View {
    let blocks: [StudyPlan.Block]
    @ObservedObject private var test = WeeklyTestSettings.shared

    private var names: [String] {
        var cal = Calendar.current
        cal.locale = Locale(identifier: LanguageCatalog.currentNative)
        return cal.veryShortWeekdaySymbols
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        ForEach(kinds(on: day).indices, id: \.self) { i in
                            let k = kinds(on: day)[i]
                            RoundedRectangle(cornerRadius: 3)
                                .fill(k.color)
                                .frame(height: k == .talk ? 22 : 12)
                        }
                        Text(names[day - 1])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110)
            HStack(spacing: 12) {
                ForEach(legend, id: \.self) { k in
                    HStack(spacing: 4) {
                        Circle().fill(k.color).frame(width: 8, height: 8)
                        Text(k.label).font(.caption2)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(explain("The week at a glance")))
    }

    private func kinds(on day: Int) -> [StudyPlan.Kind] {
        var list = blocks.filter { $0.weekdays.contains(day) }
            .sorted { $0.startMinute < $1.startMinute }
            .map(\.kind)
        if day == test.weekday { list.append(.test) }
        return list
    }

    private var legend: [StudyPlan.Kind] {
        var seen: [StudyPlan.Kind] = []
        for b in blocks where !seen.contains(b.kind) { seen.append(b.kind) }
        return seen + [.test]
    }
}
