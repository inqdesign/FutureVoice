import SwiftUI

/// Activity's planner: ONE day at a time, today first (founder, 2026-10-02:
/// "what the learner cares about is today — the days before and after are a
/// tap or a swipe away, and each date says whether it was done"). A seven-
/// column grid read as a table of coloured bars, and its past columns were
/// empty space; a day at full width can SAY what each block is.
///
/// Above: the week's dates, each carrying its result (a tick when every
/// planned block was done, `done/planned` otherwise). Swipe the strip for the
/// week before or after. Below: the selected day's timeline — the plan as
/// outlines, what happened as filled blocks, each labelled. Swipe it for the
/// day before or after.
struct PlannerDayCard: View {
    let snapshot: PlannerSnapshot
    @Binding var selectedDay: Date?
    let onShiftWeek: (Int) -> Void
    let onEditPlan: () -> Void
    let onSayItAgain: () -> Void

    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }

    private var day: Date {
        let d = selectedDay.map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: Date())
        return snapshot.days.first { cal.isDate($0, inSameDayAs: d) } ?? snapshot.days.first ?? d
    }

    var body: some View {
        VStack(spacing: 12) {
            dateStrip
            dayTitle
            timeline
            Button(action: onEditPlan) {
                Label("Edit weekly plan", systemImage: "calendar.badge.clock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Dates

    private func result(_ d: Date) -> (done: Int, total: Int)? {
        let total = snapshot.planned[d]?.count ?? 0
        guard total > 0 else { return nil }
        return (snapshot.done[d]?.count ?? 0, total)
    }

    private var dateStrip: some View {
        HStack(spacing: 2) {
            ForEach(snapshot.days, id: \.self) { d in
                let isToday = cal.isDateInToday(d)
                let isSelected = cal.isDate(d, inSameDayAs: day)
                let future = d > cal.startOfDay(for: Date())
                Button { selectedDay = d } label: {
                    VStack(spacing: 4) {
                        Text(d.formatted(Date.FormatStyle(locale: uiLocale).weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(cal.component(.day, from: d))")
                            .font(.subheadline.weight(isSelected || isToday ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(isSelected ? Color.accentColor : Color.clear))
                        mark(for: d, future: future)
                            .frame(height: 16)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // Swipe the dates for the week before or after.
        .gesture(DragGesture(minimumDistance: 24).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) else { return }
            onShiftWeek(v.translation.width < 0 ? 1 : -1)
        })
    }

    /// Whether the day's plan was kept, and nothing else: a green tick when
    /// every planned block was done, blank otherwise (founder: counts like
    /// 2/4 were noise — done or not is the only question).
    @ViewBuilder
    private func mark(for d: Date, future: Bool) -> some View {
        if !future, let r = result(d), r.done >= r.total {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.green)
                .accessibilityLabel(Text("Done"))
        } else {
            Color.clear
        }
    }

    private var dayTitle: some View {
        HStack {
            Text(day.formatted(Date.FormatStyle(locale: uiLocale).month(.wide).day().weekday(.wide)))
                .font(.headline)
            if cal.isDateInToday(day) {
                Text("Today").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - The day

    private struct Item: Identifiable {
        enum Body {
            case plan(StudyPlan.Occurrence, done: Bool)
            case actual(PlannerDay.Actual, fulfils: Bool)
        }
        var id: String
        var start: Date
        var end: Date
        var body: Body
    }

    private var items: [Item] {
        let planned = snapshot.planned[day] ?? []
        let actuals = snapshot.actuals[day] ?? []
        let done = snapshot.done[day] ?? []
        let absorbed = PlannerDay.absorbed(planned: planned, actuals: actuals)
        let fulfilling = Set(absorbed.values)
        var out: [Item] = []
        for occ in planned where absorbed[occ.id] == nil {
            out.append(Item(id: "p" + occ.id, start: occ.start, end: occ.end,
                            body: .plan(occ, done: done.contains(occ.id))))
        }
        for a in actuals {
            out.append(Item(id: "a" + a.id, start: a.start, end: a.end,
                            body: .actual(a, fulfils: fulfilling.contains(a.id))))
        }
        out.sort { $0.start < $1.start }
        return out
    }

    /// The day as a list, in order — no hour axis. A scaled timeline was
    /// mostly empty hours to scroll past (founder: "the timeline only means
    /// something when editing"); that lives in the weekly plan editor.
    private var timeline: some View {
        let list = items
        let isToday = cal.isDateInToday(day)
        let now = Date()
        // Where "now" falls: before the first item that hasn't started.
        let nowIndex = isToday ? (list.firstIndex { $0.start > now } ?? list.count) : nil
        return VStack(spacing: 0) {
            if list.isEmpty {
                Text("Nothing planned this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                if index == nowIndex { nowLine(now) }
                else if index > 0 { Divider().padding(.leading, 76) }
                row(item)
            }
            if let nowIndex, nowIndex == list.count, !list.isEmpty { nowLine(now) }
        }
        .contentShape(Rectangle())
        // Swipe the day for the one before or after.
        .gesture(DragGesture(minimumDistance: 24).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) * 1.5,
                  let next = cal.date(byAdding: .day, value: v.translation.width < 0 ? 1 : -1, to: day)
            else { return }
            selectedDay = next
        })
    }

    /// Where today stands: the time in red, the way Calendar marks it —
    /// a label, not a rule across the card.
    private func nowLine(_ now: Date) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.red).frame(width: 6, height: 6)
            Text(clock(now))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(.leading, 4)
        .padding(.vertical, 6)
        .accessibilityLabel(Text("Now"))
    }

    private func clock(_ d: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// One line of the day, like a row in Reminders: the time, the kind's
    /// icon (the only colour), what it is, and a circle that is ticked once
    /// it happened. No borders, no fills.
    @ViewBuilder
    private func row(_ item: Item) -> some View {
        switch item.body {
        case .actual(let a, _):
            rowLayout(time: clock(a.start), symbol: a.kind.symbol, tint: a.kind.color,
                      title: a.title ?? a.kind.label,
                      detail: a.title == nil ? "\(clock(a.start))–\(clock(a.end))"
                                             : "\(a.kind.label) · \(clock(a.start))–\(clock(a.end))",
                      state: .done)
        case .plan(let occ, let done):
            let lapsed = !done && occ.end < Date()
            let load = occ.kind == .review ? snapshot.reviewLoad[occ.start] : nil
            let detail: String? = done ? explain("Done at another time")
                : load.flatMap { $0 > 0 ? explain("About \($0) waiting") : nil }
                ?? (occ.kind == .sayItAgain ? explain("Pick a talk") : nil)
            let line = rowLayout(time: clock(occ.start), symbol: occ.kind.symbol,
                                 tint: lapsed ? .secondary : occ.kind.color,
                                 title: explain("\(occ.kind.label) · \(occ.minutes) min"),
                                 detail: detail,
                                 state: done ? .done : (lapsed ? .missed : .planned))
            if occ.kind == .sayItAgain && !done {
                Button(action: onSayItAgain) { line }.buttonStyle(.plain)
            } else {
                line
            }
        }
    }

    private enum RowState { case done, planned, missed }

    private func rowLayout(time: String, symbol: String, tint: Color, title: String,
                           detail: String?, state: RowState) -> some View {
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
                    .foregroundStyle(state == .missed ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: state == .done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(state == .done ? Color.green
                                 : Color.secondary.opacity(state == .missed ? 0.4 : 0.8))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
