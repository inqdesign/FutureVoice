import SwiftUI

/// Everything one week of the timetable needs, read once per (week, plan).
@MainActor
struct PlannerSnapshot {
    var days: [Date]
    var planned: [Date: [StudyPlan.Occurrence]]
    var actuals: [Date: [PlannerDay.Actual]]
    var events: [Date: [ActivityEventLog.Event]]
    var done: [Date: Set<String>]
    /// Items each upcoming review slot will find waiting, keyed by the slot.
    var reviewLoad: [Date: Int]
    var startHour: Int
    var endHour: Int

    static func startOfWeek(_ date: Date, calendar cal: Calendar = .current) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    static func make(weekStart: Date, plan: StudyPlan, now: Date = Date(),
                     calendar cal: Calendar = .current) -> PlannerSnapshot {
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let test = WeeklyTestSettings.shared.schedule
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let sessions = SessionStore.shared.loadAcrossLanguages()
            .filter { s in
                guard let end = s.endedAt else { return false }
                return end >= weekStart && s.startedAt < weekEnd
            }
        let allEvents = ActivityEventLog.shared.events(from: weekStart, to: weekEnd)
        let finishedTests = WeeklyTestStore.shared.load().compactMap(\.finishedAt)

        var planned: [Date: [StudyPlan.Occurrence]] = [:]
        var actuals: [Date: [PlannerDay.Actual]] = [:]
        var events: [Date: [ActivityEventLog.Event]] = [:]
        var done: [Date: Set<String>] = [:]
        var minHour = 7, maxHour = 23
        for day in days {
            let occ = plan.occurrences(on: day, test: test, calendar: cal)
            let dayEvents = allEvents.filter { cal.isDate($0.at, inSameDayAs: day) }
            let talks = sessions
                .filter { cal.isDate($0.startedAt, inSameDayAs: day) }
                .map { PlannerDay.Talk(id: $0.id, start: $0.startedAt,
                                       end: $0.endedAt ?? $0.startedAt, title: $0.displayTitle) }
            let acts = PlannerDay.actuals(talks: talks, events: dayEvents)
            planned[day] = occ
            actuals[day] = acts
            events[day] = dayEvents
            done[day] = PlannerDay.done(
                planned: occ, actuals: acts, events: dayEvents,
                testFinished: finishedTests.contains { cal.isDate($0, inSameDayAs: day) })
            for d in occ.map(\.start) + acts.map(\.start) {
                minHour = min(minHour, cal.component(.hour, from: d))
            }
            for d in occ.map(\.end) + acts.map(\.end) where cal.isDate(d, inSameDayAs: day) {
                maxHour = max(maxHour, cal.component(.hour, from: d) + 1)
            }
        }

        // Upcoming review slots and what each will find waiting.
        var load: [Date: Int] = [:]
        if plan.autoReview {
            let slots = plan.reviewSlots(from: now, days: 21, calendar: cal)
            let due = DrillStore.shared.load().filter { $0.box < DrillStore.maxBox }.map(\.nextReviewAt)
                + ReviewQueue.returnDates()
            load = StudyPlan.reviewLoad(slots: slots, dueDates: due)
        }
        return PlannerSnapshot(days: days, planned: planned, actuals: actuals, events: events,
                               done: done, reviewLoad: load,
                               startHour: max(0, minHour), endHour: min(24, max(maxHour, minHour + 6)))
    }
}

// MARK: - Look

extension StudyPlan.Kind {
    var color: Color {
        switch self {
        // Not the accent: a theme's accent can be green, and then a talk
        // reads as a review.
        case .talk: return .blue
        case .review, .words, .expressions: return .green
        case .shadow, .sayItAgain: return .teal
        case .test: return .orange
        }
    }

    var symbol: String {
        switch self {
        case .talk: return "phone.fill"
        case .review: return "rectangle.stack.fill"
        case .words: return "textformat"
        case .expressions: return "quote.bubble.fill"
        case .shadow: return "waveform"
        case .sayItAgain: return "arrow.counterclockwise"
        case .test: return "checkmark.seal.fill"
        }
    }

    var label: String {
        switch self {
        case .talk: return explain("Talk")
        case .review: return explain("Review")
        case .words: return explain("Words")
        case .expressions: return explain("Expressions")
        case .shadow: return explain("Shadowing")
        case .sayItAgain: return explain("Say it again")
        case .test: return explain("Weekly test")
        }
    }
}

extension PlannerDay.Actual.Kind {
    var color: Color {
        switch self {
        case .talk: return .blue
        case .review: return .green
        case .shadow, .sayItAgain: return .teal
        case .scene: return .gray
        }
    }

    var symbol: String {
        switch self {
        case .talk: return "phone.fill"
        case .review: return "rectangle.stack.fill"
        case .shadow: return "waveform"
        case .sayItAgain: return "arrow.counterclockwise"
        case .scene: return "play.rectangle.fill"
        }
    }

    var label: String {
        switch self {
        case .talk: return explain("Talk")
        case .review: return explain("Review")
        case .shadow: return explain("Shadowing")
        case .sayItAgain: return explain("Say it again")
        case .scene: return explain("Watch scene")
        }
    }
}

// MARK: - The week grid

/// Seven days side by side, time running down: the plan as dashed outlines,
/// what happened as filled blocks on top. In edit mode a future planned block
/// can be long-pressed and dragged — up and down for the time, sideways for
/// the day, snapping to 15 minutes.
struct PlannerWeekCard: View {
    let snapshot: PlannerSnapshot
    @Binding var selectedDay: Date?
    let editing: Bool
    let title: String
    let onShift: (Int) -> Void
    /// A drag ended: the block, the day it was on, its new start.
    let onMove: (StudyPlan.Occurrence, Date, Date) -> Void
    /// A planned block was tapped in edit mode.
    let onEdit: (StudyPlan.Occurrence, Date) -> Void

    @State private var dragging: String?
    @State private var dragOffset: CGSize = .zero

    private let hourHeight: CGFloat = 24
    private let labelWidth: CGFloat = 18
    private let gap: CGFloat = 3
    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }

    private var gridHeight: CGFloat { CGFloat(snapshot.endHour - snapshot.startHour) * hourHeight }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { onShift(-1) } label: {
                    Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text(title).font(.headline)
                Spacer()
                Button { onShift(1) } label: {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                }
            }
            dayHeader
            GeometryReader { geo in
                let colW = max(10, (geo.size.width - labelWidth - gap * 7) / 7)
                HStack(alignment: .top, spacing: gap) {
                    hourLabels.frame(width: labelWidth, height: gridHeight)
                    ForEach(snapshot.days, id: \.self) { day in
                        column(day, width: colW)
                    }
                }
            }
            .frame(height: gridHeight)
            legend
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var dayHeader: some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: labelWidth, height: 1)
            ForEach(snapshot.days, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
                Button { selectedDay = day } label: {
                    VStack(spacing: 2) {
                        Text(day.formatted(Date.FormatStyle(locale: uiLocale).weekday(.narrow)))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("\(cal.component(.day, from: day))")
                            .font(.caption.weight(isToday ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isToday ? Color.white : Color.primary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(isToday ? Color.accentColor : Color.clear))
                            .overlay(Circle().strokeBorder(isSelected && !isToday ? Color.primary.opacity(0.4) : .clear))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hourLabels: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Array(stride(from: snapshot.startHour, through: snapshot.endHour, by: 3)), id: \.self) { h in
                Text("\(h)")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .offset(y: CGFloat(h - snapshot.startHour) * hourHeight - 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func y(_ date: Date) -> CGFloat {
        let c = cal.dateComponents([.hour, .minute], from: date)
        let hour: Int = c.hour ?? 0
        let minute: Int = c.minute ?? 0
        let mins: Int = hour * 60 + minute - snapshot.startHour * 60
        return CGFloat(mins) / 60 * hourHeight
    }

    private func height(_ start: Date, _ end: Date) -> CGFloat {
        let hours = CGFloat(end.timeIntervalSince(start)) / 3600
        return max(16, hours * hourHeight)
    }

    private func column(_ day: Date, width: CGFloat) -> some View {
        let isToday = cal.isDateInToday(day)
        let planned = snapshot.planned[day] ?? []
        let actuals = snapshot.actuals[day] ?? []
        let done = snapshot.done[day] ?? []
        // A sitting that happened where it was planned is ONE block, not an
        // outline with another block on top of it.
        let absorbed = PlannerDay.absorbed(planned: planned, actuals: actuals)
        let fulfilling = Set(absorbed.values)
        let shownPlans = planned.filter { absorbed[$0.id] == nil }
        let tops = stackedTops(plans: shownPlans, actuals: actuals)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isToday ? Color.accentColor.opacity(0.08) : Color(.tertiarySystemFill).opacity(0.5))
            ForEach(shownPlans) { occ in
                plannedBlock(occ, day: day, width: width, done: done.contains(occ.id),
                             top: tops["p" + occ.id] ?? y(occ.start))
            }
            ForEach(actuals) { a in
                actualBlock(a, width: width, fulfilsPlan: fulfilling.contains(a.id),
                            top: tops["a" + a.id] ?? y(a.start))
            }
            if isToday {
                Rectangle().fill(Color.red)
                    .frame(width: width, height: 1.5)
                    .offset(y: y(Date()))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: gridHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { selectedDay = day }
    }

    /// Where each block is drawn. A short block is drawn taller than its
    /// minutes (so its icon fits), which made a talk and the say-it-again right
    /// after it overlap; each block now starts no higher than the bottom of
    /// the one before it. Order is kept, times shift by a few minutes at most.
    private func stackedTops(plans: [StudyPlan.Occurrence], actuals: [PlannerDay.Actual]) -> [String: CGFloat] {
        let items: [(id: String, top: CGFloat, height: CGFloat)] =
            plans.map { ("p" + $0.id, y($0.start), height($0.start, $0.end)) }
            + actuals.map { ("a" + $0.id, y($0.start), height($0.start, $0.end)) }
        var out: [String: CGFloat] = [:]
        var bottom: CGFloat = -.infinity
        for item in items.sorted(by: { $0.top < $1.top }) {
            let top = max(item.top, bottom + 1)
            out[item.id] = top
            bottom = top + item.height
        }
        return out
    }

    /// What happened: filled in its kind's colour, with its icon. A tick in
    /// the corner when it is the planned block, done where it was planned.
    private func actualBlock(_ a: PlannerDay.Actual, width: CGFloat, fulfilsPlan: Bool, top: CGFloat) -> some View {
        let h = height(a.start, a.end)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(a.kind.color)
            .overlay(alignment: .leading) {
                Image(systemName: a.kind.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.leading, 3)
            }
            .overlay(alignment: .topTrailing) {
                if fulfilsPlan && width >= 26 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(2)
                }
            }
            .frame(width: width - 2, height: h)
            .offset(x: 1, y: top)
            .allowsHitTesting(false)
    }

    private func canDrag(_ occ: StudyPlan.Occurrence) -> Bool {
        editing && occ.start > Date()
            && (occ.blockId != nil || occ.kind == .review || occ.kind == .test)
    }

    private func plannedBlock(_ occ: StudyPlan.Occurrence, day: Date, width: CGFloat, done: Bool,
                              top: CGFloat) -> some View {
        let isDragging = dragging == occ.id
        let h = height(occ.start, occ.end)
        // A plan whose time has passed without it: grey and quiet, never red.
        let lapsed = !done && occ.end < Date()
        let color = lapsed ? Color.secondary : occ.kind.color
        let draggable = canDrag(occ)
        let load = occ.kind == .review ? snapshot.reviewLoad[occ.start] : nil
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color.opacity(done ? 0.15 : (isDragging ? 0.25 : 0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(color.opacity(done || lapsed ? 0.5 : 1),
                                  style: StrokeStyle(lineWidth: draggable ? 1.6 : 1.2, dash: [3, 2]))
            )
            .overlay(alignment: .leading) {
                HStack(spacing: 1) {
                    // Done at another time of the day: the plan is ticked
                    // here, and the filled block shows where it happened.
                    Image(systemName: done ? "checkmark" : occ.kind.symbol)
                    if let load, load > 0, width >= 30 { Text("\(load)").monospacedDigit() }
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color.opacity(lapsed ? 0.7 : 1))
                .padding(.leading, 3)
            }
            .overlay(alignment: .topLeading) {
                if isDragging {
                    Text(dropTime(occ, translation: dragOffset, columnWidth: width))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color(.label)))
                        .foregroundStyle(Color(.systemBackground))
                        .fixedSize()
                        .offset(x: width + 2, y: -2)
                }
            }
            .frame(width: width - 2, height: h)
            .scaleEffect(isDragging ? 1.06 : 1)
            .offset(x: 1 + (isDragging ? dragOffset.width : 0),
                    y: top + (isDragging ? dragOffset.height : 0))
            .zIndex(isDragging ? 10 : 0)
            .onTapGesture {
                if editing, occ.blockId != nil { onEdit(occ, day) } else { selectedDay = day }
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.25)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        if dragging != occ.id {
                            dragging = occ.id
                            HapticEngine.selection()
                        }
                        dragOffset = drag?.translation ?? .zero
                    }
                    .onEnded { value in
                        if case .second(true, let drag?) = value,
                           let target = newStart(occ, translation: drag.translation, columnWidth: width),
                           target != occ.start {
                            onMove(occ, day, target)
                        }
                        dragging = nil
                        dragOffset = .zero
                    },
                including: draggable ? .all : .subviews
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(occ.kind.label), \(occ.start.formatted(date: .omitted, time: .shortened))"))
            .accessibilityValue(done ? Text("Done") : Text(""))
    }

    /// Where a drag would land: 15-minute steps, whole columns, never off the
    /// end of the target day.
    private func newStart(_ occ: StudyPlan.Occurrence, translation: CGSize, columnWidth: CGFloat) -> Date? {
        let minutes = Int((translation.height / hourHeight * 60 / 15).rounded()) * 15
        let days = Int((translation.width / (columnWidth + gap)).rounded())
        guard let shifted = cal.date(byAdding: .day, value: days, to: occ.start) else { return nil }
        let dayStart = cal.startOfDay(for: shifted)
        let offset = cal.dateComponents([.minute], from: dayStart, to: shifted).minute ?? 0
        let clamped = min(max(0, offset + minutes), 24 * 60 - max(15, occ.minutes))
        let target = dayStart.addingTimeInterval(TimeInterval(clamped * 60))
        return target > Date() ? target : nil
    }

    private func dropTime(_ occ: StudyPlan.Occurrence, translation: CGSize, columnWidth: CGFloat) -> String {
        let target = newStart(occ, translation: translation, columnWidth: columnWidth) ?? occ.start
        return target.formatted(Date.FormatStyle(locale: uiLocale).hour().minute())
    }

    /// What the colours and the two strokes mean. Without it the grid is
    /// coloured bars nobody can read.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 10) {
                kindKey(.talk); kindKey(.review); kindKey(.shadow); kindKey(.sayItAgain); kindKey(.test)
            }
            HStack(spacing: 12) {
                styleKey(filled: false, Text("Planned"))
                styleKey(filled: true, Text("Done"))
                Spacer()
                if editing {
                    Text("Hold and drag to move")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kindKey(_ kind: StudyPlan.Kind) -> some View {
        HStack(spacing: 3) {
            Image(systemName: kind.symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(RoundedRectangle(cornerRadius: 3).fill(kind.color))
            Text(kind.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func styleKey(filled: Bool, _ text: Text) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.2, dash: filled ? [] : [3, 2]))
                .background(RoundedRectangle(cornerRadius: 3).fill(filled ? Color.secondary : Color.clear))
                .frame(width: 14, height: 14)
            text.font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - One day, in order

/// The selected day as a list: every planned block and whether it happened,
/// what happened outside the plan, and — today — where "now" falls.
struct PlannerDayTimeline: View {
    let day: Date
    let snapshot: PlannerSnapshot
    let editing: Bool
    let onEdit: (StudyPlan.Occurrence, Date) -> Void

    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }

    private enum Row: Identifiable {
        case planned(StudyPlan.Occurrence, done: Bool)
        case extra(PlannerDay.Actual)
        case now(Date)
        var id: String {
            switch self {
            case .planned(let o, _): return "p" + o.id
            case .extra(let a): return "a" + a.id
            case .now: return "now"
            }
        }
        var time: Date {
            switch self {
            case .planned(let o, _): return o.start
            case .extra(let a): return a.start
            case .now(let d): return d
            }
        }
    }

    private var rows: [Row] {
        let planned = snapshot.planned[day] ?? []
        let done = snapshot.done[day] ?? []
        let actuals = snapshot.actuals[day] ?? []
        var out: [Row] = planned.map { .planned($0, done: done.contains($0.id)) }
        out += PlannerDay.unplanned(actuals: actuals, planned: planned).map { .extra($0) }
        if cal.isDateInToday(day) { out.append(.now(Date())) }
        return out.sorted { $0.time < $1.time }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text(explain("Nothing planned this day."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { CardDivider(inset: 52) }
                rowView(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func time(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(locale: uiLocale).hour().minute())
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .now(let d):
            HStack(spacing: 10) {
                Text(time(d)).font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(.red).frame(width: 42, alignment: .leading)
                Rectangle().fill(Color.red).frame(height: 1.5)
            }
            .padding(.vertical, 6)
        case .extra(let a):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(time(a.start)).font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Label(a.title ?? a.kind.label, systemImage: a.kind.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .labelStyle(TintedIconLabel(tint: a.kind.color))
                        .lineLimit(1)
                    Text(explain("Not in the plan"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        case .planned(let occ, let done):
            Button {
                if editing, occ.blockId != nil { onEdit(occ, day) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(time(occ.start)).font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Label(explain("\(occ.kind.label) · \(occ.minutes) min"), systemImage: occ.kind.symbol)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .labelStyle(TintedIconLabel(tint: occ.kind.color))
                        if let detail = detail(occ, done: done) {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    if done {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if editing, occ.blockId != nil {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func detail(_ occ: StudyPlan.Occurrence, done: Bool) -> String? {
        let actuals = snapshot.actuals[day] ?? []
        switch occ.kind {
        case .talk:
            let talks = actuals.filter { $0.kind == .talk }
            let plannedTalks = (snapshot.planned[day] ?? []).filter { $0.kind == .talk }
            if done, let i = plannedTalks.firstIndex(of: occ), talks.indices.contains(i) {
                let t = talks[i]
                return [time(t.start) + "–" + time(t.end), t.title].compactMap { $0 }.joined(separator: " · ")
            }
            return DailyCallStore.shared.isEnabled ? explain("Rings as your daily call") : nil
        case .review:
            if done { return nil }
            if let n = snapshot.reviewLoad[occ.start], n > 0 { return explain("About \(n) waiting") }
            return nil
        case .sayItAgain:
            return done ? nil : explain("Right after the talk")
        default:
            return nil
        }
    }
}

/// A label whose icon wears the block's colour and whose title stays primary.
private struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint).font(.caption)
            configuration.title
        }
    }
}
