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
    /// A line was tapped: open that kind of practice (every line is a door).
    let onOpen: (StudyPlan.Kind) -> Void
    /// A talk in the day's list was tapped: open its book.
    var onOpenTalk: (UUID) -> Void = { _ in }
    /// The day's journal entry (its share card and numbers), at the foot.
    var footer: AnyView? = nil

    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }
    private var today: Date { cal.startOfDay(for: Date()) }

    private var day: Date {
        let d = selectedDay.map { cal.startOfDay(for: $0) } ?? today
        return snapshot.days.first { cal.isDate($0, inSameDayAs: d) } ?? snapshot.days.first ?? d
    }

    var body: some View {
        // A panel pinned to the bottom of the page: its height never follows
        // the list, which scrolls inside it.
        // The share card sits at the panel's FOOT: a short day leaves the
        // space between the list and the card, a long one pushes it down.
        PinnedPanel {
            dayList
            Spacer(minLength: 0)
            if let footer {
                Divider()
                footer
            }
        }
    }

    private func go(to d: Date) {
        withAnimation(.snappy(duration: 0.28)) { selectedDay = d }
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
            if list.isEmpty {
                Text(isPromise ? explain("Rest day.") : explain("Nothing planned this day."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 48) }
                row(item, talk: talk)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) * 1.5,
                  let next = cal.date(byAdding: .day, value: v.translation.width < 0 ? 1 : -1, to: day)
            else { return }
            go(to: next)
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
        // A timed talk IS the daily call; with the call off it won't ring.
        if occ.kind == .talk, !occ.anytime, !DailyCallStore.shared.isEnabled {
            return explain("No call")
        }
        return nil
    }

    /// Every line is a door (founder, 2026-10-02: some lines tapped and
    /// some didn't). A talk that happened opens its book; a planned talk
    /// already done opens the talk that did it; everything else opens that
    /// kind of practice.
    @ViewBuilder
    private func row(_ item: Item, talk: [String: Double]) -> some View {
        switch item.body {
        case .actual(let a):
            Button {
                if let id = a.sessionId { onOpenTalk(id) }
                else if let kind = a.planKind { onOpen(kind) }
            } label: {
                rowLayout(time: "\(clock(a.start))–\(clock(a.end))", symbol: a.kind.symbol, tint: a.kind.color,
                          title: a.title ?? a.kind.label,
                          detail: explain("Extra"),
                          progress: 1)
            }
            .buttonStyle(.plain)
        case .plan(let occ, let done):
            let lapsed = !done && occ.isOver()
            let progress: Double = done ? 1 : (talk[occ.id] ?? 0)
            Button {
                if occ.kind == .talk, done, let id = talkThatDidIt {
                    onOpenTalk(id)
                } else {
                    onOpen(occ.kind)
                }
            } label: {
                rowLayout(time: occ.anytime ? explain("Anytime") : clock(occ.start), symbol: occ.kind.symbol,
                          tint: lapsed ? .secondary : occ.kind.color,
                          title: occ.kind.titled(occ.amount),
                          detail: planDetail(occ, done: done, progress: progress),
                          progress: progress, faded: lapsed)
            }
            .buttonStyle(.plain)
        }
    }

    /// The day's latest talk, for a planned talk that is already done.
    private var talkThatDidIt: UUID? {
        (snapshot.actuals[day] ?? []).filter { $0.kind == .talk }.last?.sessionId
    }

    /// One line, like a row in Settings or Reminders: the kind's icon on a
    /// tinted tile (the only colour), what it is over its time and one
    /// detail, and a ring that fills as it is done.
    private func rowLayout(time: String, symbol: String, tint: Color, title: String,
                           detail: String?, progress: Double, faded: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(faded ? Color.secondary : tint)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((faded ? Color.secondary : tint).opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(faded ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Text([time, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ProgressRing(progress: progress, faded: faded)
        }
        .padding(.vertical, 8)
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

/// The day strip, OUTSIDE the day's card (founder, 2026-10-02, after a
/// reference with a scrolling row of days): one continuous row you scroll
/// through, the chosen day held in the middle on a soft tile, the row running
/// off both edges. Where the scroll settles is the day shown; a tap scrolls
/// that day to the middle. Each circle keeps the day's standing — kept
/// (green), missed (grey ring), rest (just the number), today filling.
struct PlannerDayStrip: View {
    @Binding var selectedDay: Date?
    let isPromise: Bool
    let activeDays: Set<Date>
    let plan: StudyPlan
    let streak: Int

    @State private var scrolled: Date?
    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }
    private var today: Date { cal.startOfDay(for: Date()) }

    /// Every day the strip can reach: half a year back, a month ahead.
    private var days: [Date] {
        (-180...30).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    private var shown: Date { cal.startOfDay(for: selectedDay ?? today) }

    var body: some View {
        VStack(spacing: 12) {
            JourneyHeader(title: shown.formatted(Date.FormatStyle(locale: uiLocale).month(.abbreviated).day().weekday(.abbreviated)),
                          streak: streak,
                          away: cal.isDate(shown, inSameDayAs: today) ? nil : (shown < today ? .past : .future),
                          onToday: { scrollTo(today) })

            CenteredStrip(items: days, selection: $scrolled) { d, selected in
                VStack(spacing: 6) {
                    Text(d.formatted(Date.FormatStyle(locale: uiLocale).weekday(.narrow)))
                        .font(.caption2.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                    dayCircle(d)
                }
            }
        }
        .onAppear { scrolled = shown }
        .onChange(of: scrolled) { _, d in
            guard let d, !cal.isDate(d, inSameDayAs: shown) else { return }
            selectedDay = d
        }
        .onChange(of: selectedDay) { _, d in
            let d = cal.startOfDay(for: d ?? today)
            guard scrolled.map({ !cal.isDate($0, inSameDayAs: d) }) ?? true else { return }
            withAnimation(.snappy(duration: 0.3)) { scrolled = d }
        }
    }

    private func scrollTo(_ d: Date) {
        withAnimation(.snappy(duration: 0.35)) { scrolled = d }
    }

    private enum Mark { case kept, missed, rest, today(Double), ahead(planned: Bool) }

    private func mark(_ d: Date) -> Mark {
        if d > today {
            return .ahead(planned: !plan.occurrences(on: d, test: WeeklyTestSettings.shared.schedule).isEmpty)
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
        return ZStack { circleFace(d, number: number) }
            .frame(width: 32, height: 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(d.formatted(Date.FormatStyle(locale: uiLocale).weekday(.wide).month().day())))
    }

}

private struct TodayLabelStyle: LabelStyle {
    let trailingIcon: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            if !trailingIcon { configuration.icon }
            configuration.title
            if trailingIcon { configuration.icon }
        }
    }
}

/// How long the promise has been kept, one line wherever it is shown.
struct StreakLine: View {
    let streak: Int
    var body: some View {
        Label {
            Text(streak > 0 ? explain("Kept for \(streak) days") : explain("Keep it today for day 1"))
                .monospacedDigit()
        } icon: {
            Image(systemName: "flame.fill")
                .foregroundStyle(streak > 0 ? Color.orange : Color.secondary)
        }
    }
}

/// The header over a journey strip: what is chosen, how long the promise has
/// been kept, and a "Today" capsule when the strip is elsewhere — the same
/// for a day, a month and a year.
struct JourneyHeader: View {
    enum Away { case past, future }
    let title: String
    let streak: Int
    let away: Away?
    let onToday: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .contentTransition(.numericText())
                StreakLine(streak: streak)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let away {
                Button(action: onToday) {
                    Label(explain("Today"), systemImage: away == .past ? "arrow.right" : "arrow.left")
                        .labelStyle(TodayLabelStyle(trailingIcon: away == .past))
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .animation(.easeOut(duration: 0.2), value: away == nil)
    }
}

/// One continuous row you scroll through, the chosen item held in the middle
/// on a soft tile, the row running off both edges with a fade. Where the
/// scroll settles is the selection; a tap scrolls that item to the middle;
/// each new item in the middle ticks like a picker wheel.
struct CenteredStrip<Item: Hashable, Cell: View>: View {
    let items: [Item]
    @Binding var selection: Item?
    var cellWidth: CGFloat = 52
    @ViewBuilder let cell: (Item, Bool) -> Cell

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        let selected = item == selection
                        Button {
                            withAnimation(.snappy(duration: 0.35)) { selection = item }
                        } label: {
                            cell(item, selected)
                                .frame(width: cellWidth, height: 72)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(selected ? Color(.secondarySystemGroupedBackground) : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(selected ? Color(.separator) : .clear, lineWidth: 0.5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(item)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, (geo.size.width - cellWidth) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection, anchor: .center)
            .sensoryFeedback(.selection, trigger: selection)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                         .init(color: .black, location: 0.12),
                                         .init(color: .black, location: 0.88),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .frame(height: 76)
    }
}

/// The panel a journey's content lives in: pinned to the bottom of the page,
/// its height never following its content, which scrolls inside it. Content
/// is laid out at least the panel's height, so a `Spacer` in it pushes what
/// follows to the foot.
struct PinnedPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content() }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .shadow(color: .black.opacity(0.06), radius: 12, y: -2)
            .ignoresSafeArea(edges: .bottom))
    }
}
