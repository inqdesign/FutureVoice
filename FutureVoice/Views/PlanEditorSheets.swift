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
        var id: String {
            switch self {
            case .new(let d): return "new-\(d.timeIntervalSinceReferenceDate)"
            case .existing(let id, _): return id.uuidString
            case .newInWeek(let w, let h, let m): return "week-\(w)-\(h)-\(m)"
            case .inWeek(let id): return "week-" + id.uuidString
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
    @State private var loaded = false
    @State private var refused = false

    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }

    private var day: Date {
        switch target {
        case .new(let d), .existing(_, let d): return d
        case .newInWeek, .inWeek: return cal.startOfDay(for: Date())
        }
    }
    private var dayKey: String { StudyPlan.dayKey(day) }
    private var isWeekly: Bool {
        switch target {
        case .newInWeek, .inWeek: return true
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
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .environment(\.locale, uiLocale)
                    // A talk is promised in minutes; everything else in the
                    // count the app actually keeps.
                    Stepper(value: $minutes, in: kind.isTimed ? 5...60 : 1...50, step: kind.isTimed ? 5 : 1) {
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
        } else if case .newInWeek(let wd, let h, let m) = target {
            weekdays = [wd]
            time = cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
            kind = .words
            minutes = StudyPlan.Kind.words.defaultAmount
        } else {
            weekdays = [weekday]
            time = cal.date(bySettingHour: 20, minute: 0, second: 0, of: day) ?? day
            kind = .words
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
        guard store.update(plan) else {
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
        store.update(plan)
        dismiss()
    }
}

/// The toggles that place blocks for the learner — the review slot, say it
/// again — and the week's days off.
struct PlanSettingsSheet: View {
    /// The week on screen, for the days-off list.
    let week: [Date]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StudyPlanStore.shared

    private let cal = Calendar.current
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }

    private func binding<T>(_ path: WritableKeyPath<StudyPlan, T>) -> Binding<T> {
        Binding(get: { store.plan[keyPath: path] },
                set: { var p = store.plan; p[keyPath: path] = $0; store.update(p) })
    }

    private var reviewTime: Binding<Date> {
        Binding(get: {
            cal.date(bySettingHour: store.plan.reviewHour, minute: store.plan.reviewMinute,
                     second: 0, of: Date()) ?? Date()
        }, set: { new in
            let c = cal.dateComponents([.hour, .minute], from: new)
            var p = store.plan
            p.reviewHour = c.hour ?? 21
            p.reviewMinute = c.minute ?? 0
            store.update(p)
        })
    }

    /// Talk planned over the next 30 days, in minutes.
    private var plannedTalkMinutes: Int {
        let today = cal.startOfDay(for: Date())
        return (0..<30).reduce(0) { acc, offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { return acc }
            return acc + store.plan.occurrences(on: day).filter { $0.kind == .talk }.reduce(0) { $0 + $1.minutes }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Review slot", isOn: binding(\.autoReview))
                    if store.plan.autoReview {
                        DatePicker("Time", selection: reviewTime, displayedComponents: .hourAndMinute)
                            .environment(\.locale, uiLocale)
                        Stepper(value: binding(\.reviewMinutes), in: 5...60, step: 5) {
                            HStack {
                                Text(explain("How many"))
                                Spacer()
                                Text(StudyPlan.Kind.review.amountText(store.plan.reviewMinutes))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                } footer: {
                    Text("On every planned day. The review reminder then comes at this time, once something is waiting.")
                }
                Section {
                    ForEach(week.filter { $0 >= cal.startOfDay(for: Date()) }, id: \.self) { day in
                        Toggle(isOn: Binding(
                            get: { store.plan.isRestDay(day) },
                            set: { rest in
                                var p = store.plan
                                let key = StudyPlan.dayKey(day)
                                if rest { p.restDays.insert(key) } else { p.restDays.remove(key) }
                                store.update(p)
                            })) {
                            Text(day.formatted(Date.FormatStyle(locale: uiLocale).weekday(.wide).month().day()))
                        }
                    }
                } header: {
                    Text("Days off this week")
                } footer: {
                    Text("Nothing is planned and nothing rings on a day off.")
                }
                Section {
                    LabeledContent(explain("Talk in the next 30 days"), value: explain("\(plannedTalkMinutes) min"))
                }
            }
            .navigationTitle(explain("Timetable"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// The weekly plan, edited on its own page with room to work: Monday to
/// Sunday with no dates, because what is being changed is the plan every
/// week follows — not a week that already happened. Opened from Activity's
/// Week view ("Edit weekly plan").
struct WeeklyPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StudyPlanStore.shared

    @State private var snapshot: PlannerSnapshot?
    @State private var blockEditor: PlanBlockEditor.Target?
    @State private var showSettings = false
    /// A block that ran on several weekdays had ONE of them dragged to a new
    /// time. That one has already moved; this asks whether the rest follow.
    @State private var pendingFollow: PendingFollow?
    @State private var refused = false
    @State private var noDay: Date?

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
                                        },
                                        onAdd: { start in
                                            let c = cal.dateComponents([.weekday, .hour, .minute], from: start)
                                            blockEditor = .newInWeek(weekday: c.weekday ?? 2,
                                                                     hour: c.hour ?? 20, minute: c.minute ?? 0)
                                        })
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                        .overlay(alignment: .topLeading) {
                            // Scroll anchor at 7:00.
                            Color.clear.frame(height: 1)
                                .offset(y: (7 - CGFloat(snapshot.startHour)) * Self.hourHeight)
                                .id("seven")
                        }
                    }
                }
                .onAppear {
                    reload()
                    DispatchQueue.main.async { proxy.scrollTo("seven", anchor: .top) }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    promiseToggle
                    weekdayHeader
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Text("Tap an empty spot to add. Hold a block and drag to move it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
            .navigationTitle(explain("Weekly plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Label("Plan settings", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $blockEditor) { PlanBlockEditor(target: $0) }
            .sheet(isPresented: $showSettings) {
                PlanSettingsSheet(week: weekForSettings)
            }
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

    /// The switch that turns this plan into a promise: from today the
    /// streak counts only days the plan is kept. Off, the streak counts any
    /// day studied — which is where every learner starts.
    private var promiseToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { store.plan.streakSince != nil },
                set: { on in
                    var p = store.plan
                    p.streakSince = on ? cal.startOfDay(for: Date()) : nil
                    store.update(p)
                    Analytics.capture("plan_promise", ["on": on])
                })) {
                Text("Make this plan my promise").font(.subheadline.weight(.semibold))
            }
            Text(store.plan.streakSince != nil
                 ? explain("From today, a day keeps your streak when you do everything planned for it.")
                 : explain("Your streak counts every day you study. Turn this on to hold yourself to this plan."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Stays put above the scrolling hours.
    private var weekdayHeader: some View {
        HStack(spacing: PlannerWeekCard.gap) {
            Color.clear.frame(width: PlannerWeekCard.labelWidth, height: 1)
            ForEach(snapshot?.days ?? [], id: \.self) { day in
                Text(day.formatted(Date.FormatStyle(locale: uiLocale).weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// This week's dates, for the days-off list in the settings sheet.
    private var weekForSettings: [Date] {
        let start = PlannerSnapshot.startOfWeek(Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func reload() {
        snapshot = PlannerSnapshot.master(plan: store.plan)
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
                  store.update(moved) else {
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

    private func applyFollow(_ follow: PendingFollow) {
        pendingFollow = nil
        let c = cal.dateComponents([.hour, .minute], from: follow.newStart)
        guard let new = store.plan.following(blockId: follow.remainingId,
                                             toHour: c.hour ?? 0, minute: c.minute ?? 0),
              store.update(new) else {
            refused = true
            return
        }
        reload()
        HapticEngine.light()
        Analytics.capture("plan_block_moved", ["scope": "all_days"])
    }
}
