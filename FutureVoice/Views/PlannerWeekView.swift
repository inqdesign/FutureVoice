import SwiftUI

/// Everything one week of the timetable needs, read once per (week, plan).
@MainActor
struct PlannerSnapshot {
    var days: [Date]
    var planned: [Date: [StudyPlan.Occurrence]]
    var actuals: [Date: [PlannerDay.Actual]]
    var events: [Date: [ActivityEventLog.Event]]
    var done: [Date: Set<String>]
    /// Each planned block's progress, 0…1, per day.
    var progress: [Date: [String: Double]] = [:]
    /// Items each upcoming review slot will find waiting, keyed by the slot.
    var reviewLoad: [Date: Int]
    var startHour: Int
    var endHour: Int

    static func startOfWeek(_ date: Date, calendar cal: Calendar = .current) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    /// The weekly plan itself, with no dates: next week's Monday–Sunday as
    /// stand-ins (always in the future, so nothing reads as lapsed), with
    /// one-off edits and days off left out — they belong to dates.
    static func master(plan: StudyPlan, now: Date = Date(), calendar cal: Calendar = .current) -> PlannerSnapshot {
        var template = plan
        template.exceptions = [:]
        template.restDays = []
        let start = cal.date(byAdding: .day, value: 7, to: startOfWeek(now, calendar: cal)) ?? now
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let test = WeeklyTestSettings.shared.schedule
        var planned: [Date: [StudyPlan.Occurrence]] = [:]
        for day in days { planned[day] = template.occurrences(on: day, test: test, calendar: cal) }
        return PlannerSnapshot(days: days, planned: planned, actuals: [:], events: [:], done: [:],
                               reviewLoad: [:], startHour: 6, endHour: 24)
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
        var progress: [Date: [String: Double]] = [:]
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
            let totals = PlannerDay.totals(
                on: day, events: dayEvents,
                testFinished: finishedTests.contains { cal.isDate($0, inSameDayAs: day) })
            let prog = PlannerDay.progress(planned: occ, totals: totals)
            progress[day] = prog
            done[day] = Set(prog.filter { $0.value >= 1 }.map(\.key))
            // A past day draws no blocks (only its result), so it must not
            // stretch the hours either.
            guard day >= cal.startOfDay(for: now) else { continue }
            for d in occ.map(\.start) + acts.map(\.start) {
                minHour = min(minHour, cal.component(.hour, from: d))
            }
            for d in occ.map(\.end) + acts.map(\.end) where cal.isDate(d, inSameDayAs: day) {
                maxHour = max(maxHour, cal.component(.hour, from: d) + 1)
            }
        }

        // Upcoming review slots and what each will find waiting.
        var load: [Date: Int] = [:]
        if plan.hasReviewBlocks {
            let slots = plan.reviewSlots(from: now, days: 21, calendar: cal)
            let due = DrillStore.shared.load().filter { $0.box < DrillStore.maxBox }.map(\.nextReviewAt)
                + ReviewQueue.returnDates()
            load = StudyPlan.reviewLoad(slots: slots, dueDates: due)
        }
        return PlannerSnapshot(days: days, planned: planned, actuals: actuals, events: events,
                               done: done, progress: progress, reviewLoad: load,
                               startHour: max(0, minHour), endHour: min(24, max(maxHour, minHour + 6)))
    }
}

// MARK: - Look

extension StudyPlan.Kind {
    var color: Color {
        switch self {
        // Not the accent: a theme's accent can be green, and then a talk
        // reads as a review.
        // One colour per kind: the promise card stacks them in a single
        // column per day, so two kinds sharing a colour read as one.
        case .talk: return .blue
        case .sayItAgain: return .teal
        case .review: return .green
        case .words: return .purple
        case .expressions: return .pink
        case .shadow: return .yellow
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

    /// The amount in its own unit: minutes for a talk, a count otherwise;
    /// empty for a one-off (one run of say it again, one test).
    func amountText(_ n: Int) -> String {
        switch self {
        case .talk: return explain("\(n) min")
        case .words, .expressions: return explain("\(n) items")
        case .review: return explain("\(n) cards")
        case .shadow: return explain("\(n) lines")
        case .sayItAgain, .test: return n == 1 ? "" : explain("\(n) times")
        }
    }

    /// "Words 10 items", or just "Say it again".
    func titled(_ n: Int) -> String {
        let a = amountText(n)
        return a.isEmpty ? label : label + " " + a
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
/// what happened as filled blocks.
///
/// Two modes, because they are two different things. `.record` is a dated
/// week in Activity — read-only, what was planned against what happened.
/// `.master` is the weekly plan itself, Monday to Sunday with no dates
/// (`WeeklyPlanEditor`): there a block is long-pressed and dragged — up and
/// down for the time, sideways for the weekday, 15-minute steps — and an
/// empty spot is tapped to add one.
struct PlannerWeekCard: View {
    enum Mode { case record, master }

    let snapshot: PlannerSnapshot
    var mode: Mode = .record
    var hourHeight: CGFloat = 24
    @Binding var selectedDay: Date?
    var title: String = ""
    var onShift: (Int) -> Void = { _ in }
    /// `.record`: open the weekly plan editor.
    var onEditPlan: () -> Void = {}
    /// `.master`: a drag ended — the block, the day it was on, its new start.
    var onMove: (StudyPlan.Occurrence, Date, Date) -> Void = { _, _, _ in }
    /// `.master`: a planned block was tapped.
    var onEdit: (StudyPlan.Occurrence, Date) -> Void = { _, _ in }
    /// `.master`: an empty spot was tapped — a new block starting then.
    var onAdd: (Date) -> Void = { _ in }

    @State private var dragging: String?
    @State private var dragOffset: CGSize = .zero

    static let labelWidth: CGFloat = 16
    static let gap: CGFloat = 3
    private var labelWidth: CGFloat { Self.labelWidth }
    private var gap: CGFloat { Self.gap }
    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }
    private var isMaster: Bool { mode == .master }

    private var gridHeight: CGFloat { CGFloat(snapshot.endHour - snapshot.startHour) * hourHeight }

    var body: some View {
        if isMaster {
            grid
        } else {
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
                .padding(.horizontal, 6)
                dayHeader
                grid
                legend
                Button(action: onEditPlan) {
                    Label("Edit weekly plan", systemImage: "calendar.badge.clock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private var grid: some View {
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
    }

    /// A day already over: what is left of it is whether the plan was kept.
    private func isPast(_ day: Date) -> Bool {
        !isMaster && day < cal.startOfDay(for: Date())
    }

    /// (done, planned) for a past day; nil when nothing was planned.
    private func result(_ day: Date) -> (done: Int, total: Int)? {
        let total = snapshot.planned[day]?.count ?? 0
        guard total > 0 else { return nil }
        return (snapshot.done[day]?.count ?? 0, total)
    }

    @ViewBuilder
    private func resultMark(_ day: Date) -> some View {
        if let r = result(day) {
            if r.done >= r.total {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .accessibilityLabel(Text("Done"))
            } else {
                Text(verbatim: "\(r.done)/\(r.total)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            Color.clear
        }
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
                        // Same height on every day, so the dates line up.
                        resultMark(day)
                            .frame(height: 18)
                            .opacity(isPast(day) ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hourLabels: some View {
        let step = hourHeight >= 36 ? 1 : 3
        return ZStack(alignment: .topTrailing) {
            ForEach(Array(stride(from: snapshot.startHour, through: snapshot.endHour, by: step)), id: \.self) { h in
                Text("\(h)")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .offset(y: CGFloat(h - snapshot.startHour) * hourHeight - 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func clock(_ date: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
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
        let isToday = !isMaster && cal.isDateInToday(day)
        let planned = snapshot.planned[day] ?? []
        let actuals = snapshot.actuals[day] ?? []
        let done = snapshot.done[day] ?? []
        // A sitting that happened where it was planned is ONE block, not an
        // outline with another block on top of it.
        let absorbed = PlannerDay.absorbed(planned: planned, actuals: actuals)
        let fulfilling = Set(absorbed.values)
        // A past day is its result, nothing more (founder: "for days gone by
        // I only care whether I kept the plan"). The blocks are one tap away
        // in the day list below.
        let past = isPast(day)
        let kept = past && (result(day).map { $0.done >= $0.total } ?? false)
        let shownPlans = past ? [] : planned.filter { absorbed[$0.id] == nil }
        let shownActuals = past ? [] : actuals
        let tops = stackedTops(plans: shownPlans, actuals: shownActuals)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isToday ? Color.accentColor.opacity(0.08)
                      : kept ? Color.green.opacity(0.10)
                      : Color(.tertiarySystemFill).opacity(past ? 0.3 : 0.5))
            if isMaster {
                // Hour lines, so a drop lands where the eye expects.
                ForEach(snapshot.startHour..<snapshot.endHour, id: \.self) { h in
                    Rectangle().fill(Color(.separator).opacity(0.5))
                        .frame(width: width, height: 0.5)
                        .offset(y: CGFloat(h - snapshot.startHour) * hourHeight)
                }
                .allowsHitTesting(false)
            }
            ForEach(shownPlans) { occ in
                plannedBlock(occ, day: day, width: width, done: done.contains(occ.id),
                             top: tops["p" + occ.id] ?? y(occ.start))
            }
            ForEach(shownActuals) { a in
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
        // Late blocks pushed down by `stackedTops` must not spill past the
        // last hour onto the legend.
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            if isMaster {
                // Half-hour steps for a new block; dragging refines it.
                let minutes = Int((location.y / hourHeight * 60 / 30).rounded(.down)) * 30
                    + snapshot.startHour * 60
                let clamped = min(max(0, minutes), 23 * 60 + 30)
                onAdd(cal.startOfDay(for: day).addingTimeInterval(TimeInterval(clamped * 60)))
            } else {
                selectedDay = day
            }
        }
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
        isMaster && (occ.blockId != nil || occ.kind == .review || occ.kind == .test)
    }

    private func plannedBlock(_ occ: StudyPlan.Occurrence, day: Date, width: CGFloat, done: Bool,
                              top: CGFloat) -> some View {
        let isDragging = dragging == occ.id
        let h = height(occ.start, occ.end)
        // A plan whose time has passed without it: grey and quiet, never red.
        let lapsed = !isMaster && !done && occ.end < Date()
        let color = lapsed ? Color.secondary : occ.kind.color
        let draggable = canDrag(occ)
        let load = occ.kind == .review ? snapshot.reviewLoad[occ.start] : nil
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color.opacity(isMaster ? 0.16 : (done ? 0.15 : (isDragging ? 0.25 : 0.06))))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(color.opacity(done || lapsed ? 0.5 : 1),
                                  style: StrokeStyle(lineWidth: isMaster ? 1.4 : 1.2,
                                                     dash: isMaster ? [] : [3, 2]))
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    // Done at another time of the day: the plan is ticked
                    // here, and the filled block shows where it happened.
                    Image(systemName: done ? "checkmark" : occ.kind.symbol)
                        .font(.system(size: isMaster ? 10 : 9, weight: .bold))
                    if let load, load > 0, width >= 30 {
                        Text("\(load)").font(.system(size: 9, weight: .bold)).monospacedDigit()
                    }
                    // In the plan editor a block says when it is — that is
                    // what the learner is there to change.
                    if isMaster {
                        // 24-hour, like the axis beside it: a 12-hour time with
                        // the AM/PM dropped read 21:00 as "09:00".
                        Text(clock(occ.start))
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .foregroundStyle(color.opacity(lapsed ? 0.7 : 1))
                .padding(.leading, 3)
                .padding(.top, h >= 22 ? 3 : 1)
                .padding(.trailing, 2)
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
                if isMaster, occ.blockId != nil { onEdit(occ, day) }
                else if !isMaster { selectedDay = day }
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
    /// end of the target day or out of the week.
    private func newStart(_ occ: StudyPlan.Occurrence, translation: CGSize, columnWidth: CGFloat) -> Date? {
        let minutes = Int((translation.height / hourHeight * 60 / 15).rounded()) * 15
        let days = Int((translation.width / (columnWidth + gap)).rounded())
        guard let shifted = cal.date(byAdding: .day, value: days, to: occ.start),
              let first = snapshot.days.first, let last = snapshot.days.last,
              cal.startOfDay(for: shifted) >= first, cal.startOfDay(for: shifted) <= last
        else { return nil }
        let dayStart = cal.startOfDay(for: shifted)
        let offset = cal.dateComponents([.minute], from: dayStart, to: shifted).minute ?? 0
        let clamped = min(max(0, offset + minutes), 24 * 60 - max(15, occ.minutes))
        return dayStart.addingTimeInterval(TimeInterval(clamped * 60))
    }

    private func dropTime(_ occ: StudyPlan.Occurrence, translation: CGSize, columnWidth: CGFloat) -> String {
        let target = newStart(occ, translation: translation, columnWidth: columnWidth) ?? occ.start
        return target.formatted(Date.FormatStyle(locale: uiLocale).weekday(.abbreviated).hour().minute())
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
            }
        }
        .padding(.horizontal, 6)
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
