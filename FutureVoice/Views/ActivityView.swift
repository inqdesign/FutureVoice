import SwiftUI

/// Activity — not just WHICH days you practiced but HOW MUCH: every grid cell
/// is a heat square of metered talk minutes (darker = more). Month view is
/// a calendar; Year view is a contribution grid of the whole year. Tapping a
/// day opens its breakdown (minutes, talks, shadow takes, drill reviews) and
/// links back to that day's talks. Reached from Home's streak and Progress.
struct ActivityView: View {
    @EnvironmentObject private var appState: AppState

    @State private var activeDays: Set<Date> = []
    @State private var displayedMonth = Date()
    @State private var viewMode: ViewMode = .day
    @State private var currentStreak = 0
    @State private var longestStreak = 0
    /// Whole minutes of TALK TIME per day (start-of-day keyed), floored —
    /// see `talkSeconds(on:)` for what that is and what it isn't.
    @State private var minutesByDay: [Date: Int] = [:]
    /// The same days in SECONDS — the day summary reads the day as a CLOCK
    /// (see PracticeStats.talkClock), which minutes alone cannot say. Minutes
    /// stay the unit everywhere else: the heat buckets, the month totals and
    /// the card all agree on floors.
    @State private var talkSecondsByDay: [Date: Int] = [:]
    /// Foreground minutes per day, floored — the card's "Study" figure.
    @State private var studyMinutesByDay: [Date: Int] = [:]
    /// The day's finished talks, newest first — the tap-through to their books.
    @State private var sessionsByDay: [Date: [Session]] = [:]
    @State private var totalTalkSeconds = 0
    @State private var drillCards: [DrillCard] = []
    @State private var selectedDay: Date?
    /// The selected day's share card (`DayCardSheet`) — the day summary is
    /// its home outside a talk: the summary already says what the day was,
    /// the card is that summary as a picture.
    @State private var cardDay: CardDay?
    private struct CardDay: Identifiable { let date: Date; var id: Date { date } }

    /// How the journey under the promise is read: one day, a month, a year.
    enum ViewMode: String, CaseIterable, Identifiable {
        case day, month, year
        var id: String { rawValue }
        var label: String {
            switch self {
            case .day: return chrome("Day")
            case .month: return chrome("Month")
            case .year: return chrome("Year")
            }
        }
    }

    /// The selected day's rendered card and the calendar cells' photo dots —
    /// the cards live INSIDE the calendar, not in a view of their own (one
    /// was built and folded back in the same week: a second grid of the same
    /// days was a parallel calendar).
    @State private var thumbs: [Date: UIImage] = [:]
    @State private var cellPhotos: [Date: UIImage] = [:]
    @ObservedObject private var cardStore = DayCardStore.shared

    private let cal = Calendar.current

    // MARK: Planner state
    @ObservedObject private var planStore = StudyPlanStore.shared
    @State private var weekStart = PlannerSnapshot.startOfWeek(Date())
    @State private var planner: PlannerSnapshot?
    @State private var showPlanEditor = false
    @State private var showSayItAgainPicker = false
    @State private var openTalk: Session?
    /// `PracticeStats.activeDays` — what the no-promise rule counts.
    @State private var studiedDays: Set<Date> = []


    var body: some View {
        // A journal of the learner's routine (founder, 2026-10-02). The view
        // switch spans the top like Health's D/W/M/Y; under it the streak
        // and the chosen day are ONE header. In the day view the page does
        // not scroll: the day's card is pinned to the bottom and its list
        // scrolls inside, so the card never jumps with the list's length.
        Group {
            if viewMode == .day {
                VStack(spacing: 14) {
                    modePicker.padding(.horizontal, 20)
                    PlannerDayStrip(selectedDay: $selectedDay,
                                    isPromise: planStore.plan.streakSince != nil,
                                    activeDays: studiedDays, plan: planStore.plan,
                                    streak: currentStreak)
                    plannerSection
                }
                .padding(.top, 8)
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        modePicker
                        streakLine.frame(maxWidth: .infinity, alignment: .leading)
                        if viewMode == .month { statsBar; monthCard } else { statsBar; yearCard }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(explain("My routine"))
        .sheet(item: $cardDay) { DayCardSheet(day: $0.date) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // The page is the routine, so its Edit is the page's own.
            ToolbarItem(placement: .topBarTrailing) {
                Button(explain("Edit")) {
                    Analytics.capture("plan_edit_opened", [:])
                    showPlanEditor = true
                }
            }
        }
        .onAppear {
            load()
            #if DEBUG
            if UserDefaults.standard.string(forKey: "capture") == "activity-week-edit" { showPlanEditor = true }
            #endif
            if selectedDay == nil { selectedDay = cal.startOfDay(for: Date()) }
        }
        .onChange(of: cardStore.version) { _, _ in thumbs = [:]; loadCellPhotos() }
        .fullScreenCover(isPresented: $showPlanEditor) { WeeklyPlanEditor() }
        .navigationDestination(isPresented: Binding(get: { openTalk != nil },
                                                    set: { if !$0 { openTalk = nil } })) {
            if let openTalk {
                ConversationDetailView(session: openTalk).environmentObject(appState)
            }
        }
        .sheet(isPresented: $showSayItAgainPicker, onDismiss: reloadPlanner) {
            SayItAgainPicker().environmentObject(appState)
        }
        .onChange(of: planStore.plan) { _, _ in reloadPlanner() }
        .onChange(of: weekStart) { _, _ in reloadPlanner() }
        // A day swiped or tapped into another week takes the week with it.
        .onChange(of: selectedDay) { _, day in
            guard let day else { return }
            let start = PlannerSnapshot.startOfWeek(day)
            if start != weekStart { weekStart = start }
        }
    }

    // MARK: - Planner (week)

    @ViewBuilder
    private var plannerSection: some View {
        if let planner {
            // The day is ONE card: its plan, what happened, and the day's
            // share card at the foot (founder: one card per day, and the
            // same width as the promise above).
            PlannerDayCard(snapshot: planner, selectedDay: $selectedDay,
                           isPromise: planStore.plan.streakSince != nil,
                           activeDays: studiedDays,
                           onSayItAgain: { showSayItAgainPicker = true },
                           onOpenTalk: { id in
                               openTalk = sessionsByDay.values.flatMap { $0 }.first { $0.id == id }
                                   ?? SessionStore.shared.loadAcrossLanguages().first { $0.id == id }
                           },
                           footer: selectedDay.map { AnyView(dayJournal(cal.startOfDay(for: $0))) })
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private var modePicker: some View {
        Picker("View", selection: $viewMode) {
            ForEach(ViewMode.allCases) { m in Text(m.label).tag(m) }
        }
        .pickerStyle(.segmented)
    }

    private var streakLine: some View {
        StreakLine(streak: currentStreak).font(.headline)
    }

    private func reloadPlanner() {
        planner = PlannerSnapshot.make(weekStart: weekStart, plan: planStore.plan)
        if let days = planner?.days,
           !(selectedDay.map { d in days.contains { cal.isDate($0, inSameDayAs: d) } } ?? false) {
            selectedDay = days.first { cal.isDateInToday($0) } ?? days.first
        }
    }

    /// Move a week; the selected day moves with it (same weekday), so the
    /// strip and the day under it never disagree.
    private func shiftWeek(_ by: Int) {
        let from = selectedDay ?? Date()
        selectedDay = cal.date(byAdding: .day, value: 7 * by, to: from) ?? from
    }


    // MARK: - The day's card, inside the calendar

    /// A photo day wears its photo in the calendar cell — the month reads as
    /// the places you studied. Tiny square crops, decoded once per photo.
    private func loadCellPhotos() {
        var out: [Date: UIImage] = [:]
        for day in cardStore.recordedDays() {
            let key = cal.startOfDay(for: day)
            guard cellPhotos[key] == nil else { out[key] = cellPhotos[key]; continue }
            out[key] = cardStore.photo(for: day)?.cellThumb(side: 132)
        }
        cellPhotos = out
    }

    /// The card's 4:5 feed format at a fixed size, so the day's facts can sit
    /// beside it instead of under it — the summary used to be a left-hung
    /// thumbnail with half the row empty.
    private static let cardThumbWidth: CGFloat = 132
    private static let cardThumbHeight: CGFloat = cardThumbWidth * 5 / 4

    /// The selected day's card, beside its facts — tap for the sheet (photo,
    /// share). Rendered lazily and cached for the page's life.
    @ViewBuilder
    private func cardPreviewRow(_ day: Date) -> some View {
        Button { cardDay = CardDay(date: day) } label: {
            ZStack {
                if let image = thumbs[day] {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color(.tertiarySystemFill)
                }
            }
            .frame(width: Self.cardThumbWidth, height: Self.cardThumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Share card"))
        .task(id: "\(day.timeIntervalSinceReferenceDate)-\(cardStore.version)") {
            guard thumbs[day] == nil else { return }
            let data = DayCardData.resolve(day: day)
            thumbs[day] = DayCardView(data: data, photo: cardStore.photo(for: day), format: .feed)
                .render(scale: 1)
        }
    }

    // MARK: - Stats (compact single row)
    // MARK: - Stats (compact single row)

    private struct HeadlineStat: Identifiable {
        let value: String
        let label: String
        let icon: String
        var tint: Color = .accentColor
        var id: String { label }
    }

    /// The past's totals. The streak and the best run live in the promise
    /// card above, by the learner's own rule — not repeated here.
    private var headlineStats: [HeadlineStat] {
        [HeadlineStat(value: totalTimeString, label: explain("total"), icon: "waveform"),
         HeadlineStat(value: "\(activeDays.count)", label: explain("days"), icon: "calendar")]
    }

    /// The four stats share the row by CONTENT, not as four equal columns.
    /// Equal columns handed "5h 30m" exactly the width of "3", so the one
    /// stat with something to say sat pressed against its dividers while the
    /// three single digits wasted theirs. The leftover is spread as equal
    /// gaps instead — every cell keeps a half-gap either side, so the
    /// dividers still land midway between them.
    private var statsBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(headlineStats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 { statDivider }
                Spacer(minLength: 8)
                compactStat(stat)
                Spacer(minLength: 8)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var statDivider: some View {
        Divider().frame(height: 26)
    }

    /// Lifetime talk time, humanized: "47m" → "3h 12m".
    private var totalTimeString: String {
        let mins = totalTalkSeconds / 60
        return mins < 60 ? "\(mins)m" : "\(mins / 60)h \(mins % 60)m"
    }

    private func compactStat(_ stat: HeadlineStat) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: stat.icon).font(.caption2).foregroundStyle(stat.tint)
                Text(stat.value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    // A years-old total ("153h 20m") must shrink rather than
                    // shove the row; the minimum gaps above are the floor.
                    .minimumScaleFactor(0.8)
            }
            Text(stat.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Month view

    private var monthCard: some View {
        VStack(spacing: 14) {
            periodHeader

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

            Text(periodFooter)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Year view (contribution grid)

    private var yearCard: some View {
        VStack(spacing: 16) {
            periodHeader

            // 12 mini-months, 3 across — the whole year on one screen, no
            // horizontal scroll.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                      spacing: 16) {
                ForEach(Array(monthsOfYear.enumerated()), id: \.offset) { _, month in
                    miniMonth(month)
                }
            }

            Text(periodFooter)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func miniMonth(_ month: Date) -> some View {
        VStack(spacing: 5) {
            Text(monthShortSymbol(month))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                      spacing: 2) {
                ForEach(Array(cells(for: month).enumerated()), id: \.offset) { _, date in
                    yearCell(date)
                }
            }
        }
    }

    // MARK: - Period header (shared)

    private var periodHeader: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text(periodTitle).font(.headline)
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
            }
            .disabled(!canGoNext)
            .opacity(canGoNext ? 1 : 0.3)
        }
    }

    // MARK: - Cells

    /// One day as a TILE, not a dot. The month is laid out as a photo wall
    /// — square rounded cells the full column wide — because the cards'
    /// photos live in it: a circle showed a photo as a smudge, a tile shows
    /// the place. Days without a photo keep the same tile in heat blue (or
    /// a faint fill for empty ones), so the wall reads as one surface.
    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let day = cal.startOfDay(for: date)
            let active = activeDays.contains(day)
            let isToday = cal.isDateInToday(date)
            let future = isFuture(day)
            let mins = minutesByDay[day] ?? 0
            let strong = active && heatOpacity(mins) >= 0.6
            let isSelected = selectedDay == day
            let photo = cellPhotos[day]
            RoundedRectangle(cornerRadius: 9)
                .fill(active ? AnyShapeStyle(Color.accentColor.opacity(heatOpacity(mins)))
                             : AnyShapeStyle(Color(.systemFill).opacity(future ? 0.3 : 0.55)))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .topLeading) {
                    Text("\(cal.component(.day, from: date))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(future ? AnyShapeStyle(.tertiary)
                                         : (photo != nil || strong ? AnyShapeStyle(.white)
                                            : AnyShapeStyle(.secondary)))
                        .shadow(color: photo != nil ? .black.opacity(0.6) : .clear, radius: 2)
                        .padding(4)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(isSelected ? Color.accentColor
                                      : (isToday ? Color.accentColor.opacity(0.45) : .clear),
                                      lineWidth: isSelected ? 2.5 : 1.5)
                )
                .contentShape(Rectangle())
                .onTapGesture { if !future { selectedDay = day; viewMode = .day } }
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit)
        }
    }

    @ViewBuilder
    private func yearCell(_ date: Date?) -> some View {
        if let date {
            let day = cal.startOfDay(for: date)
            let future = isFuture(day)
            let active = activeDays.contains(day)
            let mins = minutesByDay[day] ?? 0
            let isSelected = selectedDay == day
            RoundedRectangle(cornerRadius: 2)
                // Future days are drawn faint so the grid still reads as a full
                // year, but they're inert.
                .fill(active ? Color.accentColor.opacity(heatOpacity(mins))
                      : Color(.tertiarySystemFill).opacity(future ? 0.4 : 1))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.accentColor,
                                      lineWidth: isSelected ? 1.5 : (cal.isDateInToday(date) ? 1 : 0))
                )
                .contentShape(Rectangle())
                .onTapGesture { if !future { selectedDay = day; viewMode = .day } }
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit)
        }
    }

    /// A day strictly after today — not yet lived, so not selectable.
    private func isFuture(_ day: Date) -> Bool {
        day > cal.startOfDay(for: Date())
    }

    /// Minutes → heat bucket, anchored to the ~10-minute daily-goal scale.
    private func heatOpacity(_ minutes: Int) -> Double {
        switch minutes {
        case ..<1:    return 0.25   // talked, but under a minute
        case 1..<5:   return 0.4
        case 5..<10:  return 0.65
        case 10..<20: return 0.85
        default:      return 1.0
        }
    }

    // MARK: - Day detail (tap a day)

    /// The foot of the day's card: its share card beside the day's numbers.
    /// The day's talks are rows in the list above (tap one for its book),
    /// so they aren't listed again here.
    @ViewBuilder
    private func dayJournal(_ day: Date) -> some View {
        let talks = (sessionsByDay[day] ?? []).count
        let log = PracticeLog.shared.day(day)
        let shadowed = max(log?.shadowReps ?? 0,
                           appState.shadowAttempts.filter { cal.isDate($0.createdAt, inSameDayAs: day) }.count)
        let reviewed = max(log?.drillReps ?? 0,
                           drillCards.filter { c in
                               c.lastReviewedAt.map { cal.isDate($0, inSameDayAs: day) } ?? false
                           }.count)
        let study = studyMinutesByDay[day] ?? 0
        let talkSeconds = talkSecondsByDay[day] ?? 0
        let isEmpty = talkSeconds == 0 && talks == 0 && shadowed == 0 && reviewed == 0 && study == 0
        if !isEmpty {
            HStack(alignment: .top, spacing: 16) {
                cardPreviewRow(day)
                VStack(spacing: 12) {
                    factRow("Talk time", PracticeStats.talkClock(seconds: talkSeconds))
                    if talks > 0 { factRow("Talks", "\(talks)") }
                    if study > 0 { factRow("Study time", explain("\(study) min")) }
                    if shadowed > 0 { factRow("Shadowing", "\(shadowed)") }
                    if reviewed > 0 { factRow("Drills", "\(reviewed)") }
                    Spacer(minLength: 0)
                    Button { cardDay = CardDay(date: day) } label: {
                        Label("Share card", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                .frame(maxWidth: .infinity, minHeight: Self.cardThumbHeight)
            }
        }
    }

    /// One fact beside the card: what it is, then how much of it. Label left,
    /// value right, so the column reads as a table however many rows the day
    /// earned.
    private func factRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    /// "8월 31일 (월)" / "Mon, Aug 31" — in the LEARNER's language, and
    /// without the year unless the day is in another one.
    ///
    /// ABBREVIATED on both fields. `.formatted(date: .complete)` read the
    /// device locale rather than the app's, so a Korean app printed an English
    /// weekday in front of a German date order over two lines; spelling the
    /// month and weekday out then left "Monday, August 31" pressed against
    /// the share button. The month is named in the header directly above, so
    /// the summary only has to say which day of it.
    private func dayTitle(_ day: Date) -> String {
        var style = Date.FormatStyle(locale: uiLocale, calendar: cal)
            .month(.abbreviated).day().weekday(.abbreviated)
        if cal.component(.year, from: day) != cal.component(.year, from: Date()) {
            style = style.year()
        }
        return day.formatted(style)
    }

    // MARK: - Period math

    private var periodTitle: String {
        let f = DateFormatter()
        f.locale = uiLocale
        f.setLocalizedDateFormatFromTemplate(viewMode == .month ? "MMMM yyyy" : "yyyy")
        return f.string(from: displayedMonth)
    }

    /// Every date symbol on this page resolves in the LEARNER's language, not
    /// the phone's — `DateFormatter`, `Calendar`'s symbols and `.formatted()`
    /// all default to the device locale, which is how a Korean app came to
    /// head its calendar "September 2026" over "M T W T F S S".
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }

    /// `cal` with that locale attached — for the symbol arrays only; the
    /// date maths must keep the user's own calendar and first weekday.
    private var symbolCalendar: Calendar {
        var c = cal
        c.locale = uiLocale
        return c
    }

    private var canGoNext: Bool {
        switch viewMode {
        case .day, .month: return !cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
        case .year:  return !cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .year)
        }
    }

    private func shift(_ by: Int) {
        if by > 0, !canGoNext { return }
        let unit: Calendar.Component = viewMode == .month ? .month : .year
        displayedMonth = cal.date(byAdding: unit, value: by, to: displayedMonth) ?? displayedMonth
    }

    private var weekdaySymbols: [String] {
        let s = symbolCalendar.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(s[shift...] + s[..<shift])
    }

    /// Leading blanks + each day of the displayed month.
    private var monthCells: [Date?] { cells(for: displayedMonth) }

    /// Leading blanks + each day of the month `date` falls in.
    private func cells(for date: Date) -> [Date?] {
        let comps = cal.dateComponents([.year, .month], from: date)
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

    /// The 12 months of the displayed year, Jan → Dec.
    private var monthsOfYear: [Date] {
        let comps = cal.dateComponents([.year], from: displayedMonth)
        guard let jan1 = cal.date(from: comps) else { return [] }
        return (0..<12).compactMap { cal.date(byAdding: .month, value: $0, to: jan1) }
    }

    private func monthShortSymbol(_ month: Date) -> String {
        let idx = cal.component(.month, from: month) - 1
        let symbols = symbolCalendar.shortMonthSymbols
        return symbols.indices.contains(idx) ? symbols[idx] : ""
    }

    // MARK: - Summaries

    /// ONE line under the grid: how much of the period was used, then how it
    /// compares. Three unaligned pieces used to sit here — summary left, heat
    /// legend right, comparison on its own line below. The legend went with
    /// them: "darker = more" is read in a second and never needed saying.
    private var periodFooter: String {
        let summary = viewMode == .month ? monthSummary : yearSummary
        guard let comparison = periodComparison else { return summary }
        return summary + " · " + comparison
    }

    private var monthSummary: String {
        let days = monthCells.compactMap { $0 }.map { cal.startOfDay(for: $0) }
        let active = days.filter { activeDays.contains($0) }.count
        let mins = days.reduce(0) { $0 + (minutesByDay[$1] ?? 0) }
        return explain("\(active) active days · \(mins) min")
    }

    private var yearSummary: String {
        let year = cal.component(.year, from: displayedMonth)
        let active = activeDays.filter { cal.component(.year, from: $0) == year }.count
        let mins = periodMinutes(displayedMonth, granularity: .year)
        return explain("\(active) active days · \(mins) min this year")
    }

    /// Minutes spoken in the calendar month/year that `date` falls in.
    private func periodMinutes(_ date: Date, granularity: Calendar.Component) -> Int {
        minutesByDay.reduce(0) { acc, entry in
            cal.isDate(entry.key, equalTo: date, toGranularity: granularity) ? acc + entry.value : acc
        }
    }

    /// "+32 min vs June" / "+120 min vs 2025" — vs the previous period.
    private var periodComparison: String? {
        let unit: Calendar.Component = viewMode == .month ? .month : .year
        guard let prev = cal.date(byAdding: unit, value: -1, to: displayedMonth) else { return nil }
        let prevMins = periodMinutes(prev, granularity: unit)
        guard prevMins > 0 else { return nil }
        let delta = periodMinutes(displayedMonth, granularity: unit) - prevMins
        let f = DateFormatter()
        f.locale = uiLocale
        f.setLocalizedDateFormatFromTemplate(viewMode == .month ? "MMMM" : "yyyy")
        let signed = (delta >= 0 ? "+" : "") + "\(delta)"
        return explain("\(signed) min vs \(f.string(from: prev))")
    }

    // MARK: - Data

    private func load() {
        let sessions = SessionStore.shared.load().filter { $0.endedAt != nil }

        var byDay: [Date: [Session]] = [:]
        for session in sessions.sorted(by: { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }) {
            byDay[cal.startOfDay(for: session.endedAt ?? session.startedAt), default: []].append(session)
        }

        // The streak's own definition of an active day — any language, any
        // activity — so the lit run on this calendar IS the streak.
        let studied = PracticeStats.activeDays(calendar: cal)

        var days = Set(byDay.keys)
        days.formUnion(cardStore.recordedDays().map { cal.startOfDay(for: $0) })
        days.formUnion(studied)

        var seconds: [Date: Int] = [:]
        var study: [Date: Int] = [:]
        for day in days {
            let talk = talkSeconds(on: day)
            seconds[day] = talk
            study[day] = studySeconds(on: day, talk: talk)
        }

        // Shaded and counted only where practice actually happened. Being in
        // `days` is a weaker claim — a day can hold a photo, or nothing but
        // foreground time, and neither is a rep. A frozen card's talk minutes
        // still light a day the meter has since pruned.
        activeDays = studied.union(days.filter { (seconds[$0] ?? 0) > 0 })
        minutesByDay = seconds.mapValues { $0 / 60 }
        talkSecondsByDay = seconds
        studyMinutesByDay = study.mapValues { $0 / 60 }
        sessionsByDay = byDay
        totalTalkSeconds = seconds.values.reduce(0, +)
        drillCards = DrillStore.shared.load()
        // One rule, one implementation. This screen used to count its own
        // "days with any session", which was a third definition of streak
        // alongside PracticeStats' and the Core's — three numbers, one word.
        studiedDays = studied
        PromiseJudge.refresh()
        currentStreak = PracticeStats.snapshot().streakDays
        longestStreak = PracticeStats.longestStreak(calendar: cal)
        // Land on today: the promise card is about today.
        if selectedDay == nil { selectedDay = cal.startOfDay(for: Date()) }
        loadCellPhotos()
        reloadPlanner()
    }

    /// Foreground time, never less than the talk time — `DayCardData.make`'s
    /// rule, so this row and the card printed beside it agree. Falls back to
    /// the frozen card once `AppUsageLog` has pruned the day.
    private func studySeconds(on day: Date, talk: Int) -> Int {
        let usage = AppUsageLog.seconds(on: day)
        if usage > 0 { return max(usage, talk) }
        return max((cardStore.snapshot(for: day)?.studyMinutes ?? 0) * 60, talk)
    }

    /// The day's talk time, read where every other surface reads it: the
    /// METER (`TalkTimeLog`), or the day's frozen card once the log has
    /// pruned that far back.
    ///
    /// This screen used to sum the learner's own turn durations, which is a
    /// different quantity entirely — a call is mostly the fluent self talking
    /// and the learner thinking — so the day summary read 8 min beside a home
    /// ring reading 11 for the same afternoon. `PracticeStats.todayTalkSeconds`
    /// settled that rule for the ring, the widget and the receipt; this was
    /// the one screen never converted. There is no fallback to the old sum:
    /// a second definition is what the bug was.
    private func talkSeconds(on day: Date) -> Int {
        let metered = TalkTimeLog.seconds(on: day)
        if metered > 0 { return metered }
        return (cardStore.snapshot(for: day)?.talkMinutes ?? 0) * 60
    }

}

private extension UIImage {
    /// Center-crop to a small square for a calendar cell — the full cover
    /// photo is 2000 px and 30-odd of them must not be decoded per frame.
    func cellThumb(side: CGFloat) -> UIImage {
        let short = min(size.width, size.height)
        let scale = side / max(short, 1)
        let target = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            let w = size.width * scale, h = size.height * scale
            draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
    }
}
