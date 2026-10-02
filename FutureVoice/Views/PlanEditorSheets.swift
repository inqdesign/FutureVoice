import SwiftUI

/// One hand-placed timetable block: what, which weekdays, when, how long.
/// A block opened from a one-off day edits that day only.
struct PlanBlockEditor: View {
    enum Target: Identifiable {
        case new(day: Date)
        case existing(blockId: UUID, day: Date)
        var id: String {
            switch self {
            case .new(let d): return "new-\(d.timeIntervalSinceReferenceDate)"
            case .existing(let id, _): return id.uuidString
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
        }
    }
    private var dayKey: String { StudyPlan.dayKey(day) }
    /// Opened from a day that has its own one-off blocks.
    private var isException: Bool { store.plan.exceptions[dayKey] != nil }
    private var existingId: UUID? {
        if case .existing(let id, _) = target { return id }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activity", selection: $kind) {
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
                    Stepper(value: $minutes, in: 5...60, step: 5) {
                        HStack {
                            Text("Length")
                            Spacer()
                            Text(explain("\(minutes) min")).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    if kind != .talk {
                        Toggle("Remind me", isOn: $remind)
                    }
                } footer: {
                    if kind == .talk {
                        Text("A talk block rings as your daily call when the call is on (Me › Call). Up to 4 call times.")
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
                                Text("Length")
                                Spacer()
                                Text(explain("\(store.plan.reviewMinutes) min"))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                } footer: {
                    Text("On every planned day. The review reminder then comes at this time, once something is waiting.")
                }
                Section {
                    Toggle("Say it again after a talk", isOn: binding(\.autoSayItAgain))
                } footer: {
                    Text("Right after the day's first talk.")
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
