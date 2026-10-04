import SwiftUI

/// One hand-placed timetable block: what, which weekdays, when, how long.
/// A block opened from a one-off day edits that day only.
struct PlanBlockEditor: View {
    enum Target: Identifiable {
        /// On a dated day (a one-off plan applies if the day has one).
        case new(day: Date)
        case existing(blockId: UUID, day: Date)
        /// In the weekly plan: no date, only a weekday.
        case newInWeek(weekday: Int, hour: Int, minute: Int)
        case inWeek(blockId: UUID)
        /// In the weekly plan, from the + button: this kind, on every study
        /// day, at the kind's usual time.
        case newOfKind(StudyPlan.Kind)
        var id: String {
            switch self {
            case .new(let d): return "new-\(d.timeIntervalSinceReferenceDate)"
            case .existing(let id, _): return id.uuidString
            case .newInWeek(let w, let h, let m): return "week-\(w)-\(h)-\(m)"
            case .inWeek(let id): return "week-" + id.uuidString
            case .newOfKind(let k): return "kind-" + k.rawValue
            }
        }
    }

    let target: Target
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StudyPlanStore.shared

    @State private var kind: StudyPlan.Kind = .talk
    @State private var weekdays: Set<Int> = []
    @State private var time = Date()
    @State private var minutes = 10
    @State private var remind = true
    @State private var anytime = false
    @State private var loaded = false
    @State private var refused = false

    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }

    private var day: Date {
        switch target {
        case .new(let d), .existing(_, let d): return d
        case .newInWeek, .inWeek, .newOfKind: return cal.startOfDay(for: Date())
        }
    }
    private var dayKey: String { StudyPlan.dayKey(day) }
    private var isWeekly: Bool {
        switch target {
        case .newInWeek, .inWeek, .newOfKind: return true
        default: return false
        }
    }
    /// Opened from a day that has its own one-off blocks.
    private var isException: Bool { !isWeekly && store.plan.exceptions[dayKey] != nil }
    private var existingId: UUID? {
        switch target {
        case .existing(let id, _), .inWeek(let id): return id
        default: return nil
        }
    }

    /// A talk in 5-minute steps; review is every kind of item counted
    /// together, so it runs higher, in fives; a run (say it again) by one.
    private var amountRange: ClosedRange<Int> {
        switch kind {
        case .talk: return 5...60
        case .review: return 5...100
        default: return 1...50
        }
    }
    private var amountStep: Int { kind == .talk || kind == .review ? 5 : 1 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activity", selection: Binding(
                        get: { kind },
                        set: { new in
                            // A new kind starts from its own amount (10 min
                            // of talk is not 10 runs of say it again).
                            if new != kind { minutes = new.defaultAmount }
                            kind = new
                        })) {
                        ForEach(StudyPlan.Kind.placeable) { k in
                            Label(k.label, systemImage: k.symbol).tag(k)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    if kind == .review {
                        Text("Words, expressions, sentence cards and shadow lines all count.")
                    } else if kind == .talk {
                        // The routine's timed talks are the daily call.
                        Text(DailyCallStore.shared.isEnabled
                             ? (anytime ? explain("Any time of day: no call rings for this one.")
                                        : explain("Your daily call rings at this time."))
                             : explain("Your daily call is off, so this one won't ring. Turn it on in Me → Daily call."))
                    }
                }
                if !isException {
                    Section {
                        weekdayPicker
                    } header: {
                        Text("Days")
                    }
                } else {
                    Section {
                        Text(day.formatted(Date.FormatStyle(locale: uiLocale).weekday(.wide).month().day()))
                    } footer: {
                        Text("This day has its own plan, so this change is for this day only.")
                    }
                }
                Section {
                    Toggle("Any time of day", isOn: $anytime)
                    if !anytime {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .environment(\.locale, uiLocale)
                    }
                    // A talk is promised in minutes; everything else in the
                    // count the app actually keeps.
                    Stepper(value: $minutes, in: amountRange, step: amountStep) {
                        HStack {
                            Text(kind.isTimed ? explain("Length") : explain("How many"))
                            Spacer()
                            Text(kind.amountText(minutes).isEmpty ? "1" : kind.amountText(minutes))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    if kind != .talk {
                        Toggle("Remind me", isOn: $remind)
                    }
                } footer: {
                    if kind == .talk {
                        Text("A talk block rings as your daily call when the call is on (Me › Call). Up to 4 call times.")
                    } else if kind == .sayItAgain {
                        Text("When it's time, you pick which recent talk to say again.")
                    }
                }
                if existingId != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: {
                            Text("Delete block")
                        }
                    }
                }
            }
            .navigationTitle(existingId == nil ? explain("New block") : explain("Block"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isException && weekdays.isEmpty)
                }
            }
            .alert("Too many call times", isPresented: $refused) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The daily call can ring at up to 4 times of day. Move this talk to one of them, or remove another.")
            }
            .onAppear(perform: load)
        }
    }

    private var weekdayPicker: some View {
        let symbols = { () -> [String] in
            var c = cal; c.locale = uiLocale
            return c.veryShortWeekdaySymbols
        }()
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        return HStack(spacing: 6) {
            ForEach(order, id: \.self) { wd in
                let on = weekdays.contains(wd)
                Button {
                    if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                } label: {
                    Text(symbols[wd - 1])
                        .font(.subheadline.weight(on ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Circle().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let weekday = cal.component(.weekday, from: day)
        if let id = existingId,
           let block = (isException ? store.plan.exceptions[dayKey] : store.plan.blocks)?
               .first(where: { $0.id == id }) {
            kind = block.kind
            weekdays = block.weekdays
            time = cal.date(bySettingHour: block.hour, minute: block.minute, second: 0, of: day) ?? day
            minutes = block.minutes
            remind = block.remind
            anytime = block.isAnytime
        } else if case .newInWeek(let wd, let h, let m) = target {
            weekdays = [wd]
            time = cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
            kind = .review
            minutes = StudyPlan.Kind.review.defaultAmount
        } else if case .newOfKind(let k) = target {
            let off = store.plan.offWeekdays ?? []
            weekdays = Set(1...7).subtracting(off)
            // A talk in the morning (the daily call's default), say it again
            // right after it, review in the evening.
            let (h, m): (Int, Int) = switch k {
            case .talk: (8, 0)
            case .sayItAgain: (8, 15)
            default: (20, 0)
            }
            time = cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
            kind = k
            minutes = k.defaultAmount
        } else {
            weekdays = [weekday]
            time = cal.date(bySettingHour: 20, minute: 0, second: 0, of: day) ?? day
            kind = .review
            minutes = StudyPlan.Kind.review.defaultAmount
        }
    }

    private func edited(_ base: StudyPlan.Block?) -> StudyPlan.Block {
        let c = cal.dateComponents([.hour, .minute], from: time)
        var b = base ?? StudyPlan.Block(kind: kind, weekdays: [], hour: 0, minute: 0, minutes: minutes)
        b.kind = kind
        b.weekdays = isException ? b.weekdays : weekdays
        b.hour = c.hour ?? 0
        b.minute = c.minute ?? 0
        b.minutes = minutes
        b.remind = kind == .talk ? true : remind
        b.anytime = anytime ? true : nil
        return b
    }

    private func save() {
        var plan = store.plan
        if isException {
            var list = plan.exceptions[dayKey] ?? []
            if let id = existingId, let i = list.firstIndex(where: { $0.id == id }) {
                list[i] = edited(list[i])
            } else {
                list.append(edited(nil))
            }
            plan.exceptions[dayKey] = list
        } else if let id = existingId, let i = plan.blocks.firstIndex(where: { $0.id == id }) {
            plan.blocks[i] = edited(plan.blocks[i])
        } else {
            plan.blocks.append(edited(nil))
        }
        plan.mergeTwins()
        guard store.update(plan, byLearner: true) else {
            refused = true
            return
        }
        Analytics.capture("plan_block_saved", ["kind": kind.rawValue, "new": existingId == nil])
        if kind != .talk, remind {
            Task {
                await PlanReminder.requestPermissionIfNeeded()
                await PlanReminder.reschedule()
            }
        }
        dismiss()
    }

    private func delete() {
        guard let id = existingId else { return }
        var plan = store.plan
        if isException {
            plan.exceptions[dayKey]?.removeAll { $0.id == id }
        } else {
            plan.blocks.removeAll { $0.id == id }
        }
        store.update(plan, byLearner: true)
        dismiss()
    }
}

/// The weekly plan, edited on its own page with room to work: Monday to
/// Sunday with no dates, because what is being changed is the plan every
/// week follows — not a week that already happened. Opened from Activity's
/// Week view ("Edit weekly plan").
struct WeeklyPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StudyPlanStore.shared

    @State private var showTestEditor = false
    @State private var showSettings = false
    /// Whether the routine's reminders can ring at all — only said when they can't.
    @State private var notifications: ReviewNotifications.Status?
    @State private var snapshot: PlannerSnapshot?
    @State private var blockEditor: PlanBlockEditor.Target?
    /// A block that ran on several weekdays had ONE of them dragged to a new
    /// time. That one has already moved; this asks whether the rest follow.
    @State private var pendingFollow: PendingFollow?
    @State private var refused = false
    @State private var noDay: Date?
    /// Where the block being dragged would land — shown at the top of the
    /// timeline while the drag lasts, then gone.
    @State private var dragTarget: Date?
    /// A block just added from the + button: scrolled into view.
    @State private var focusMinute: Int?
    /// The block the + just added, ringed on the grid, and what the top pill
    /// says about where it went — both for a moment only.
    @State private var landedId: UUID?
    @State private var landedNote: String?
    @State private var scrollRequest = 0

    private struct PendingFollow {
        /// The block still holding the other weekdays.
        var remainingId: UUID
        var newStart: Date
    }

    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }
    static let hourHeight: CGFloat = 40

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if let snapshot {
                        PlannerWeekCard(snapshot: snapshot, mode: .master, hourHeight: Self.hourHeight,
                                        selectedDay: $noDay,
                                        onMove: handleMove,
                                        onEdit: { occ, _ in
                                            if let id = occ.blockId { blockEditor = .inWeek(blockId: id) }
                                            else if occ.kind == .test { showTestEditor = true }
                                        },
                                        onAdd: { start in
                                            let c = cal.dateComponents([.weekday, .hour, .minute], from: start)
                                            blockEditor = .newInWeek(weekday: c.weekday ?? 2,
                                                                     hour: c.hour ?? 20, minute: c.minute ?? 0)
                                        },
                                        onDragTarget: { t in
                                            withAnimation(.easeOut(duration: 0.15)) {
                                                dragTarget = t
                                                if t != nil { landedNote = nil; landedId = nil }
                                            }
                                        },
                                        highlightBlockId: landedId)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                        .overlay(alignment: .topLeading) {
                            // Scroll anchor at 7:00.
                            Color.clear.frame(height: 1)
                                .offset(y: (7 - CGFloat(snapshot.startHour)) * Self.hourHeight)
                                .id("seven")
                        }
                        .overlay(alignment: .topLeading) {
                            // Scroll anchor at a block just added.
                            if let focusMinute {
                                Color.clear.frame(height: 1)
                                    .offset(y: (CGFloat(focusMinute) / 60 - CGFloat(snapshot.startHour)) * Self.hourHeight)
                                    .id("focus")
                            }
                        }
                    }
                }
                .onAppear {
                    reload()
                    DispatchQueue.main.async { proxy.scrollTo("seven", anchor: .top) }
                    #if DEBUG
                    // `-planAdd review`: the + menu's pick, for a capture.
                    if let k = UserDefaults.standard.string(forKey: "planAdd").flatMap(StudyPlan.Kind.init(rawValue:)) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { addBlock(k) }
                    }
                    #endif
                }
                .onChange(of: scrollRequest) { _, _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("focus", anchor: .center) }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    notificationsBanner
                    weekdayHeader
                }
            }
            .overlay(alignment: .top) {
                if let dragTarget { dragTimePill(dragTarget) }
                else if let landedNote { pill(landedNote) }
            }
            .overlay(alignment: .bottomTrailing) { addButton }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Text("Tap an empty spot to add. Hold a block and drag to move it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
            .navigationTitle(explain("My routine"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Study days are set once and rarely touched, so they live
                // behind the gear rather than above the week.
                ToolbarItem(placement: .cancellationAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(Text(explain("Study days")))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: reload) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 0) {
                        restDays
                        Text(explain("The other days are rest days: nothing is planned, and they never break your streak."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                        Spacer()
                    }
                    .padding(.top, 8)
                    .navigationTitle(explain("Study days"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
                }
                .presentationDetents([.height(260)])
            }
            // The weekly test is a block like any other: tap it to set its
            // day, time and reminder (it used to hide in a settings sheet).
            .sheet(isPresented: $showTestEditor, onDismiss: reload) {
                NavigationStack {
                    Form { WeeklyTestSettingsSection(notifications: $notifications) }
                        .navigationTitle(explain("Weekly test"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showTestEditor = false }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
            .task { notifications = await ReviewNotifications.status() }
            .sheet(item: $blockEditor) { PlanBlockEditor(target: $0) }
            .confirmationDialog(explain("Move the other days too?"), isPresented: Binding(
                get: { pendingFollow != nil }, set: { if !$0 { pendingFollow = nil } }),
                titleVisibility: .visible) {
                if let follow = pendingFollow {
                    Button(explain("Every day it runs")) { applyFollow(follow) }
                    // Already done: the dragged one moved on release. Tapping
                    // outside means the same.
                    Button(explain("Only on \(weekdayName(follow.newStart))"), role: .cancel) {
                        pendingFollow = nil
                    }
                }
            }
            .alert("Too many call times", isPresented: $refused) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The daily call can ring at up to 4 times of day. Move this talk to one of them, or remove another.")
            }
            .onChange(of: store.plan) { _, _ in reload() }
        }
    }

    /// The time a dragged block will land on, at the top centre of the
    /// timeline (founder: visible while dragging, gone after). Under the
    /// finger the block itself is covered.
    private func dragTimePill(_ t: Date) -> some View {
        let day = t.formatted(Date.FormatStyle(locale: uiLocale).weekday(.abbreviated))
        let c = cal.dateComponents([.hour, .minute], from: t)
        return pill("\(day) \(String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0))")
            .animation(.snappy(duration: 0.15), value: t)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.headline.monospacedDigit())
            .contentTransition(.numericText())
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Color(.label)))
            .foregroundStyle(Color(.systemBackground))
            .padding(.top, 8)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    /// The + in the corner: the three blocks a routine is made of. Picking
    /// one puts it straight on the grid — every study day, at the first free
    /// slot from that kind's usual time — and scrolls to it, so the next move
    /// is a drag (founder: "the table is more direct than a sheet"); a tap on
    /// it then edits it. Tapping an empty spot still adds at that spot.
    private var addButton: some View {
        Menu {
            ForEach(StudyPlan.Kind.placeable) { k in
                Button {
                    addBlock(k)
                } label: {
                    Label(k.label, systemImage: k.symbol)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .accessibilityLabel(Text(explain("Add a block")))
        .padding(.trailing, 20)
        .padding(.bottom, 16)
    }

    private enum RestChoice: Hashable { case none, weekends, custom }

    private var restChoice: RestChoice {
        let off = store.plan.offWeekdays ?? []
        if off.isEmpty { return .none }
        if off == [1, 7] { return .weekends }
        return .custom
    }

    @State private var choosingDays = false

    private func setOff(_ days: Set<Int>) {
        var p = store.plan
        p.offWeekdays = days
        store.update(p, byLearner: true)
    }

    /// Rest is a property of the WEEK, which is one plan that repeats:
    /// every day, weekends off, or the learner's own weekdays.
    private var restDays: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Study days", selection: Binding(
                    get: { choosingDays ? .custom : restChoice },
                    set: { choice in
                        switch choice {
                        case .none: choosingDays = false; setOff([])
                        case .weekends: choosingDays = false; setOff([1, 7])
                        case .custom: choosingDays = true
                        }
                    })) {
                    Text("Every day").tag(RestChoice.none)
                    Text("Weekdays").tag(RestChoice.weekends)
                    Text("Choose").tag(RestChoice.custom)
                }
                .pickerStyle(.segmented)
            }
            if choosingDays || restChoice == .custom {
                HStack(spacing: 6) {
                    let symbols: [String] = {
                        var c = cal; c.locale = uiLocale
                        return c.veryShortWeekdaySymbols
                    }()
                    ForEach((0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }, id: \.self) { wd in
                        // A chip is a STUDY day: lit means "I study on this
                        // day". At least one stays lit — a week of rest is
                        // no routine.
                        let off = (store.plan.offWeekdays ?? []).contains(wd)
                        Button {
                            var days = store.plan.offWeekdays ?? []
                            if off { days.remove(wd) } else if days.count < 6 { days.insert(wd) }
                            setOff(days)
                        } label: {
                            Text(symbols[wd - 1])
                                .font(.subheadline.weight(off ? .regular : .semibold))
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(Capsule().fill(off ? Color(.tertiarySystemFill) : Color.accentColor))
                                .foregroundStyle(off ? Color.primary : Color.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Stays put above the scrolling hours. Under the day names, the
    /// day's "anytime" blocks — no hour, so no place on the grid.
    private var weekdayHeader: some View {
        let days = snapshot?.days ?? []
        let anytime = days.map { d in (snapshot?.planned[d] ?? []).filter(\.anytime) }
        return VStack(spacing: 6) {
            HStack(spacing: PlannerWeekCard.gap) {
                Color.clear.frame(width: PlannerWeekCard.labelWidth, height: 1)
                ForEach(days, id: \.self) { day in
                    Text(day.formatted(Date.FormatStyle(locale: uiLocale).weekday(.abbreviated)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            if anytime.contains(where: { !$0.isEmpty }) {
                // Blocks with no hour. The row is named over its full width —
                // a side label in the 16-pt hour gutter broke into "An / y" —
                // and a chip says icon + number only, which fits a column in
                // every language ("10 items" was cut in all of them).
                Text(explain("Any time of day"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, PlannerWeekCard.labelWidth + PlannerWeekCard.gap)
                HStack(alignment: .top, spacing: PlannerWeekCard.gap) {
                    Color.clear.frame(width: PlannerWeekCard.labelWidth, height: 1)
                    ForEach(Array(days.enumerated()), id: \.offset) { i, _ in
                        VStack(spacing: 3) {
                            ForEach(anytime[i]) { occ in
                                Button {
                                    if let id = occ.blockId { blockEditor = .inWeek(blockId: id) }
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Image(systemName: occ.kind.symbol)
                                        if occ.amount > 1 || occ.kind.isTimed {
                                            Text("\(occ.amount)").monospacedDigit()
                                        }
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(occ.kind.color)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, minHeight: 22)
                                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(occ.kind.color.opacity(0.18)))
                                    .accessibilityLabel(Text(occ.kind.titled(occ.amount)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func reload() {
        snapshot = PlannerSnapshot.master(plan: store.plan)
    }

    /// Said only when the routine's reminders CAN'T ring: when they can,
    /// there is nothing to say (a "Reminders on" row with no switch read as
    /// a setting nobody could change).
    @ViewBuilder
    private var notificationsBanner: some View {
        switch notifications {
        case .notAsked:
            Button {
                Task { notifications = await ReviewNotifications.request() }
            } label: {
                bannerLabel(icon: "bell", tint: .accentColor,
                            text: explain("Allow notifications so your routine can remind you"))
            }
            .buttonStyle(.plain)
        case .denied:
            Button { ReviewNotifications.openSettings() } label: {
                bannerLabel(icon: "bell.slash", tint: .orange,
                            text: explain("Notifications are off, so your routine can't remind you. Turn them on in Settings"))
            }
            .buttonStyle(.plain)
        default:
            EmptyView()
        }
    }

    private func bannerLabel(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.footnote).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func weekdayName(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: uiLocale).weekday(.wide))
    }

    private func handleMove(_ occ: StudyPlan.Occurrence, _ day: Date, _ newStart: Date) {
        let c = cal.dateComponents([.hour, .minute], from: newStart)
        switch occ.source {
        case .review:
            var p = store.plan
            p.reviewHour = c.hour ?? p.reviewHour
            p.reviewMinute = c.minute ?? p.reviewMinute
            store.update(p)
        case .test:
            let settings = WeeklyTestSettings.shared
            settings.weekday = cal.component(.weekday, from: newStart)
            settings.hour = c.hour ?? settings.hour
            settings.minute = c.minute ?? settings.minute
            Task { await WeeklyTestReminder.reschedule() }
            reload()
        case .template(let id):
            let spans = (store.plan.blocks.first { $0.id == id }?.weekdays.count ?? 1) > 1
            let sameDay = cal.isDate(day, inSameDayAs: newStart)
            // The cell lands where it was dropped, at once: this weekday is
            // split off to the new time (or moved, if it was the only one).
            guard let moved = store.plan.moving(blockId: id, on: day, to: newStart, scope: .everyWeek),
                  store.update(moved, byLearner: true) else {
                refused = true
                return
            }
            reload()
            HapticEngine.light()
            Analytics.capture("plan_block_moved", ["kind": occ.kind.rawValue, "scope": "weekday"])
            // Only a time change on a block that also runs on other weekdays
            // leaves a question: should those follow?
            if spans && sameDay { pendingFollow = PendingFollow(remainingId: id, newStart: newStart) }
        case .exception:
            break
        }
    }

    private func addBlock(_ kind: StudyPlan.Kind) {
        var plan = store.plan
        let days = Set(1...7).subtracting(plan.offWeekdays ?? [])
        let length = kind.drawnMinutes(amount: kind.defaultAmount)
        // A talk in the morning (the daily call's default), say it again
        // right after it, review in the evening.
        let usual = switch kind {
        case .talk: 8 * 60
        case .sayItAgain: 8 * 60 + 15
        default: 20 * 60
        }
        func isFree(_ start: Int) -> Bool {
            guard start >= 0, start + length <= 24 * 60 else { return false }
            return plan.blocks.allSatisfy { b in
                b.isAnytime || b.weekdays.isDisjoint(with: days)
                    || start + length <= b.startMinute
                    || b.startMinute + b.kind.drawnMinutes(amount: b.minutes) <= start
            }
        }
        // Later first, then earlier, in half hours.
        let later = stride(from: usual, through: 23 * 60, by: 30)
        let earlier = stride(from: usual - 30, through: 6 * 60, by: -30)
        let start = (Array(later) + Array(earlier)).first(where: isFree) ?? usual
        plan.blocks.append(StudyPlan.Block(kind: kind, weekdays: days, hour: start / 60,
                                           minute: start % 60, minutes: kind.defaultAmount))
        plan.mergeTwins()
        guard store.update(plan, byLearner: true) else {
            refused = true
            return
        }
        reload()
        focusMinute = start
        scrollRequest += 1
        HapticEngine.light()
        // Ring it on the grid and say where it went (merged into a twin, the
        // twin is the one ringed).
        let id = store.plan.blocks.first {
            $0.kind == kind && $0.hour == start / 60 && $0.minute == start % 60 && !$0.isAnytime
        }?.id
        withAnimation(.easeOut(duration: 0.2)) {
            landedId = id
            landedNote = "\(kind.label) · \(String(format: "%d:%02d", start / 60, start % 60))"
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.3)) {
                if landedId == id { landedId = nil; landedNote = nil }
            }
        }
        Analytics.capture("plan_block_saved", ["kind": kind.rawValue, "new": true, "via": "add_button"])
        if kind != .talk {
            Task {
                await PlanReminder.requestPermissionIfNeeded()
                await PlanReminder.reschedule()
            }
        }
    }

    private func applyFollow(_ follow: PendingFollow) {
        pendingFollow = nil
        let c = cal.dateComponents([.hour, .minute], from: follow.newStart)
        guard let new = store.plan.following(blockId: follow.remainingId,
                                             toHour: c.hour ?? 0, minute: c.minute ?? 0),
              store.update(new, byLearner: true) else {
            refused = true
            return
        }
        reload()
        HapticEngine.light()
        Analytics.capture("plan_block_moved", ["scope": "all_days"])
    }
}
