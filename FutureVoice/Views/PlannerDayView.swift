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

    /// Whether the day's plan was kept: a tick when all of it was, the count
    /// otherwise. A day still ahead only says it has something planned.
    @ViewBuilder
    private func mark(for d: Date, future: Bool) -> some View {
        if let r = result(d) {
            if future {
                Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4)
            } else if r.done >= r.total {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text(verbatim: "\(r.done)/\(r.total)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            Color.clear.frame(width: 4, height: 4)
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
            if let r = result(day), day <= cal.startOfDay(for: Date()) {
                Text(verbatim: "\(r.done)/\(r.total)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(r.done >= r.total ? Color.green : Color.secondary)
            }
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
        return VStack(spacing: 6) {
            if list.isEmpty {
                Text("Nothing planned this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                if index == nowIndex { nowLine(now) }
                block(item).frame(height: 40)
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

    private func nowLine(_ now: Date) -> some View {
        HStack(spacing: 6) {
            Text(clock(now))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.red)
            Rectangle().fill(Color.red).frame(height: 1.5)
        }
        .padding(.vertical, 2)
        .accessibilityLabel(Text("Now"))
    }

    private func clock(_ d: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    @ViewBuilder
    private func block(_ item: Item) -> some View {
        switch item.body {
        case .actual(let a, let fulfils):
            HStack(spacing: 6) {
                Image(systemName: a.kind.symbol).font(.caption.weight(.bold))
                Text(a.title.map { "\(a.kind.label) · \($0)" } ?? a.kind.label)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: "\(clock(a.start))–\(clock(a.end))")
                    .font(.caption2).monospacedDigit()
                if fulfils { Image(systemName: "checkmark").font(.caption2.weight(.heavy)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(a.kind.color))
        case .plan(let occ, let done):
            let lapsed = !done && occ.end < Date()
            let color = lapsed ? Color.secondary : occ.kind.color
            let load = occ.kind == .review ? snapshot.reviewLoad[occ.start] : nil
            Button {
                if occ.kind == .sayItAgain, !done { onSayItAgain() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark" : occ.kind.symbol).font(.caption.weight(.bold))
                    Text(explain("\(occ.kind.label) · \(occ.minutes) min"))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    if let load, load > 0 {
                        Text(explain("About \(load) waiting")).font(.caption2).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(clock(occ.start)).font(.caption2).monospacedDigit()
                    if occ.kind == .sayItAgain, !done {
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                }
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(done ? 0.12 : 0.06)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(color.opacity(lapsed || done ? 0.5 : 1),
                                  style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            // Not `.disabled`: that greys the whole block, and an upcoming
            // plan must read as clearly as one you can tap.
            .allowsHitTesting(occ.kind == .sayItAgain && !done)
        }
    }
}
