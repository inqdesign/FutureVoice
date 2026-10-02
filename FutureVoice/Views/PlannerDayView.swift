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
    static let hourHeight: CGFloat = 46
    private let labelWidth: CGFloat = 40

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

    /// The hours shown: the day's own span, never less than 7–22.
    private var hours: ClosedRange<Int> {
        let starts = items.map { cal.component(.hour, from: $0.start) }
        let ends = items.map { min(24, cal.component(.hour, from: $0.end) + 1) }
        return min(7, starts.min() ?? 7)...max(22, ends.max() ?? 22)
    }

    private func y(_ date: Date) -> CGFloat {
        let c = cal.dateComponents([.hour, .minute], from: date)
        let h: Int = c.hour ?? 0
        let m: Int = c.minute ?? 0
        let mins: Int = h * 60 + m - hours.lowerBound * 60
        return CGFloat(mins) / 60 * Self.hourHeight
    }

    private func blockHeight(_ item: Item) -> CGFloat {
        let h = CGFloat(item.end.timeIntervalSince(item.start)) / 3600 * Self.hourHeight
        return max(30, h)
    }

    /// Tops, pushed down so a short block drawn taller than its minutes never
    /// covers the next one.
    private func tops(_ items: [Item]) -> [String: CGFloat] {
        var out: [String: CGFloat] = [:]
        var bottom: CGFloat = -.infinity
        for item in items {
            let top = max(y(item.start), bottom + 2)
            out[item.id] = top
            bottom = top + blockHeight(item)
        }
        return out
    }

    private var timeline: some View {
        let list = items
        let tops = tops(list)
        let height = CGFloat(hours.upperBound - hours.lowerBound) * Self.hourHeight
        return HStack(alignment: .top, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ForEach(Array(hours), id: \.self) { h in
                    Text(verbatim: "\(h):00")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .offset(y: CGFloat(h - hours.lowerBound) * Self.hourHeight - 7)
                }
            }
            .frame(width: labelWidth, height: height, alignment: .topTrailing)

            ZStack(alignment: .topLeading) {
                ForEach(Array(hours), id: \.self) { h in
                    Rectangle().fill(Color(.separator).opacity(0.5))
                        .frame(height: 0.5)
                        .offset(y: CGFloat(h - hours.lowerBound) * Self.hourHeight)
                }
                ForEach(list) { item in
                    block(item)
                        .frame(height: blockHeight(item))
                        .offset(y: tops[item.id] ?? y(item.start))
                }
                if list.isEmpty {
                    Text("Nothing planned this day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .offset(y: Self.hourHeight * 2)
                }
                if cal.isDateInToday(day), hours.contains(cal.component(.hour, from: Date())) {
                    Rectangle().fill(Color.red).frame(height: 1.5)
                        .offset(y: y(Date()))
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .clipped()
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
            .disabled(occ.kind != .sayItAgain || done)
        }
    }
}
