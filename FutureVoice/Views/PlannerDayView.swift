import SwiftUI

/// Activity's top card: the learner's PROMISE and today (founder, 2026-10-02:
/// "it's a promise I kept to myself"; "what the learner cares about is today").
///
/// - The streak, by the learner's own rule (`PracticeStats.standing`): with
///   no promise made it counts days studied; once their plan is a promise it
///   counts days the plan was kept, and a day with nothing planned rests.
/// - The week as one circle per day — kept (green), missed (grey ring), rest
///   (just the number), today filling as it goes — with ‹ › and a swipe for
///   other weeks. Tapping a day shows it below.
/// - The day as a list in time order, each line with a ring that fills as the
///   block is done (a talk block by its minutes).
struct PlannerDayCard: View {
    let snapshot: PlannerSnapshot
    @Binding var selectedDay: Date?
    let isPromise: Bool
    let activeDays: Set<Date>
    let onShiftWeek: (Int) -> Void
    let onSayItAgain: () -> Void

    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }
    private var today: Date { cal.startOfDay(for: Date()) }

    private var day: Date {
        let d = selectedDay.map { cal.startOfDay(for: $0) } ?? today
        return snapshot.days.first { cal.isDate($0, inSameDayAs: d) } ?? snapshot.days.first ?? d
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            week
            Divider()
            dayList
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - The week

    private enum Mark { case kept, missed, rest, today(Double), ahead(planned: Bool) }

    private func mark(_ d: Date) -> Mark {
        if d > today {
            return .ahead(planned: !(snapshot.planned[d] ?? []).isEmpty)
        }
        let standing = PracticeStats.standing(of: d, activeDays: activeDays, calendar: cal)
        if d == today {
            if standing == .kept { return .kept }
            if isPromise, let e = PromiseLedger.shared.entry(d, calendar: cal), e.planned > 0 {
                return .today(Double(e.done) / Double(e.planned))
            }
            return .today(0)
        }
        switch standing {
        case .kept: return .kept
        case .missed: return .missed
        case .rest: return .rest
        }
    }

    private var week: some View {
        HStack(spacing: 0) {
            Button { onShiftWeek(-1) } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                    .frame(width: 22, height: 44)
            }
            ForEach(snapshot.days, id: \.self) { d in
                Button { selectedDay = d } label: {
                    VStack(spacing: 5) {
                        Text(d.formatted(Date.FormatStyle(locale: uiLocale).weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        dayCircle(d)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { onShiftWeek(1) } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                    .frame(width: 22, height: 44)
            }
        }
        .gesture(DragGesture(minimumDistance: 24).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) else { return }
            onShiftWeek(v.translation.width < 0 ? 1 : -1)
        })
    }

    @ViewBuilder
    private func circleFace(_ d: Date, number: Text) -> some View {
        switch mark(d) {
        case .kept:
            Circle().fill(Color.green)
            number.foregroundStyle(.white)
        case .missed:
            Circle().strokeBorder(Color(.systemGray4), lineWidth: 2)
            number.foregroundStyle(.secondary)
        case .rest:
            number.foregroundStyle(.tertiary)
        case .today(let progress):
            Circle().strokeBorder(Color(.systemGray5), lineWidth: 3)
            Circle().trim(from: 0, to: max(0.001, progress))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1.5)
            number.foregroundStyle(.primary)
        case .ahead(let planned):
            if planned {
                Circle().strokeBorder(Color(.systemGray4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
            number.foregroundStyle(.secondary)
        }
    }

    private func dayCircle(_ d: Date) -> some View {
        let number = Text("\(cal.component(.day, from: d))")
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
        let selected = cal.isDate(d, inSameDayAs: day)
        return ZStack { circleFace(d, number: number) }
            .frame(width: 32, height: 32)
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(d.formatted(Date.FormatStyle(locale: uiLocale).weekday(.wide).month().day())))
    }

    // MARK: - The day

    private struct Item: Identifiable {
        enum Body {
            case plan(StudyPlan.Occurrence, done: Bool)
            case actual(PlannerDay.Actual)
        }
        var id: String
        var start: Date
        var body: Body
    }

    private var items: [Item] {
        let planned = snapshot.planned[day] ?? []
        let actuals = snapshot.actuals[day] ?? []
        let done = snapshot.done[day] ?? []
        // Each planned block shows as itself; what happened OUTSIDE the plan
        // is listed too, so the day reads as the day.
        var out: [Item] = []
        for occ in planned {
            out.append(Item(id: "p" + occ.id, start: occ.start, body: .plan(occ, done: done.contains(occ.id))))
        }
        for a in PlannerDay.unplanned(actuals: actuals, planned: planned) {
            out.append(Item(id: "a" + a.id, start: a.start, body: .actual(a)))
        }
        out.sort { $0.start < $1.start }
        return out
    }

    private var dayList: some View {
        let list = items
        let talk = snapshot.progress[day] ?? [:]
        return VStack(alignment: .leading, spacing: 0) {
            Text(cal.isDateInToday(day) ? explain("Today")
                 : day.formatted(Date.FormatStyle(locale: uiLocale).month(.wide).day().weekday(.abbreviated)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            if list.isEmpty {
                Text(isPromise ? explain("Rest day.") : explain("Nothing planned this day."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 76) }
                row(item, talk: talk)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 24).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) * 1.5,
                  let next = cal.date(byAdding: .day, value: v.translation.width < 0 ? 1 : -1, to: day)
            else { return }
            selectedDay = next
        })
    }

    private func clock(_ d: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private func planDetail(_ occ: StudyPlan.Occurrence, done: Bool, progress: Double) -> String? {
        guard !done else { return nil }
        if progress > 0, occ.amount > 1 {
            let did = Int((progress * Double(occ.amount)).rounded(.down))
            return explain("\(did) of \(occ.kind.amountText(occ.amount))")
        }
        if occ.kind == .review, let n = snapshot.reviewLoad[occ.start], n > 0 {
            return explain("About \(n) waiting")
        }
        if occ.kind == .sayItAgain { return explain("Pick a talk") }
        return nil
    }

    @ViewBuilder
    private func row(_ item: Item, talk: [String: Double]) -> some View {
        switch item.body {
        case .actual(let a):
            rowLayout(time: clock(a.start), symbol: a.kind.symbol, tint: a.kind.color,
                      title: a.title ?? a.kind.label,
                      detail: explain("Extra · \(clock(a.start))–\(clock(a.end))"),
                      progress: 1)
        case .plan(let occ, let done):
            let lapsed = !done && occ.end < Date()
            let progress: Double = done ? 1 : (talk[occ.id] ?? 0)
            let line = rowLayout(time: clock(occ.start), symbol: occ.kind.symbol,
                                 tint: lapsed ? .secondary : occ.kind.color,
                                 title: occ.kind.titled(occ.amount),
                                 detail: planDetail(occ, done: done, progress: progress),
                                 progress: progress, faded: lapsed)
            if occ.kind == .sayItAgain && !done {
                Button(action: onSayItAgain) { line }.buttonStyle(.plain)
            } else {
                line
            }
        }
    }

    /// One line, like a row in Reminders: time, the kind's icon (the only
    /// colour), what it is over one detail line, and a ring that fills as it
    /// is done.
    private func rowLayout(time: String, symbol: String, tint: Color, title: String,
                           detail: String?, progress: Double, faded: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(time)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(faded ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ProgressRing(progress: progress, faded: faded)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Empty circle → filling ring → green tick.
private struct ProgressRing: View {
    let progress: Double
    var faded = false

    var body: some View {
        ZStack {
            if progress >= 1 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            } else {
                Circle().strokeBorder(Color(.systemGray4).opacity(faded ? 0.6 : 1), lineWidth: 2)
                if progress > 0 {
                    Circle().trim(from: 0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                }
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// The top of the routine journal: the learner's promise, and what a week of
/// it looks like (founder, 2026-10-02: "my routine at the top — I will do
/// this — and show the week simply: what Monday holds, what the weekend
/// holds"). Seven columns, each a stack of colour bars in the order of the
/// day — one bar per thing promised — with a legend that names the colours
/// and their amounts. A day with no bar is a rest day.
struct RoutinePromiseCard: View {
    let plan: StudyPlan
    let test: WeeklyTestSchedule
    let streak: Int
    let onEdit: () -> Void
    let onMakePromise: () -> Void

    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }
    private var isPromise: Bool { plan.streakSince != nil }

    /// The template's days, Monday-first (the learner's first weekday),
    /// as next week's dates so one-off edits and days off stay out.
    private var weekDays: [Date] {
        let start = cal.date(byAdding: .day, value: 7, to: PlannerSnapshot.startOfWeek(Date(), calendar: cal)) ?? Date()
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var template: StudyPlan {
        var p = plan
        p.exceptions = [:]
        p.restDays = []
        return p
    }

    private func blocks(on day: Date) -> [StudyPlan.Occurrence] {
        template.occurrences(on: day, test: test, calendar: cal)
    }

    /// One entry per kind in the week, with the amount it asks for.
    private var legend: [(kind: StudyPlan.Kind, amount: Int)] {
        var seen: [StudyPlan.Kind: Int] = [:]
        var order: [StudyPlan.Kind] = []
        for d in weekDays {
            for o in blocks(on: d) where seen[o.kind] == nil {
                seen[o.kind] = o.amount
                order.append(o.kind)
            }
        }
        return order.map { ($0, seen[$0] ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(isPromise ? explain("My promise") : explain("My routine"))
                    .font(.headline)
                Spacer()
                if streak > 0 {
                    Label(explain("\(streak) days in a row"), systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
            }
            weekGraphic
            legendRow
            HStack {
                if !isPromise && !legend.isEmpty {
                    Button(explain("Make it a promise"), action: onMakePromise)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Button(explain("Edit"), action: onEdit)
                    .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    /// The week's shape: what each day holds, as stacked bars.
    private var weekGraphic: some View {
        let todayWeekday = cal.component(.weekday, from: Date())
        let rows = max(1, weekDays.map { blocks(on: $0).count }.max() ?? 1)
        return HStack(alignment: .top, spacing: 6) {
            ForEach(weekDays, id: \.self) { d in
                let isToday = cal.component(.weekday, from: d) == todayWeekday
                VStack(spacing: 6) {
                    Text(d.formatted(Date.FormatStyle(locale: uiLocale).weekday(.narrow)))
                        .font(.caption.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.primary : Color.secondary)
                    VStack(spacing: 3) {
                        let list = blocks(on: d)
                        ForEach(list) { o in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(o.kind.color)
                                .frame(height: 10)
                        }
                        // Keep every column the same height, so the bars
                        // line up from the top like a timetable.
                        ForEach(0..<(rows - list.count), id: \.self) { _ in
                            Color.clear.frame(height: 10)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(d.formatted(Date.FormatStyle(locale: uiLocale).weekday(.wide))))
                .accessibilityValue(Text(blocks(on: d).map { $0.kind.label }.joined(separator: ", ")))
            }
        }
    }

    private var legendRow: some View {
        FlowLayout(spacing: 12) {
            ForEach(legend, id: \.kind) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(item.kind.color).frame(width: 10, height: 10)
                    Text(item.kind.titled(item.amount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
