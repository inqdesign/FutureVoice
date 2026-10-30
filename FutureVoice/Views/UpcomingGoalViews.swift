import SwiftUI

/// One upcoming goal as a row: its kind's glyph, the title, where and when,
/// and the countdown at the trailing edge.
struct UpcomingGoalRow: View {
    let goal: UpcomingGoal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: goal.kind.symbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(goal.kind.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title.isEmpty ? goal.kind.label : goal.title)
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let countdown = goal.countdown() {
                Text(countdown)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(goal.kind.tint)
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        if !goal.place.isEmpty { parts.append(goal.place) }
        if let date = goal.date { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " · ")
    }
}

/// Add or change one upcoming goal.
struct UpcomingGoalEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var goal: UpcomingGoal
    @State private var hasDate: Bool
    @State private var confirmingDelete = false
    private let isNew: Bool

    init(goal: UpcomingGoal?, language: String) {
        let g = goal ?? UpcomingGoal(kind: .interview, title: "", language: language)
        _goal = State(initialValue: g)
        _hasDate = State(initialValue: g.date != nil)
        isNew = goal == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(explain("What is it?"), selection: $goal.kind) {
                        ForEach(UpcomingGoal.Kind.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    TextField(goal.kind.titlePrompt, text: $goal.title, axis: .vertical)
                }
                Section {
                    Toggle(explain("It has a date"), isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker(explain("Date"), selection: dateBinding, in: Calendar.current.startOfDay(for: Date())...,
                                   displayedComponents: .date)
                    }
                    TextField(goal.kind.placePrompt, text: $goal.place)
                }
                Section {
                    TextField(explain("The role, the score you need, who will be there…"),
                              text: $goal.notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Notes")
                } footer: {
                    Text(explain("Your tutor prepares you for this. The more it knows, the closer the practice gets."))
                }
                if !isNew {
                    Section {
                        Button(explain("Delete goal"), role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? chrome("New goal") : chrome("Goal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(explain("Delete this goal?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button(explain("Delete"), role: .destructive) {
                    UpcomingGoalStore.shared.delete(goal.id)
                    dismiss()
                }
            }
        }
    }

    /// A date picked once survives the toggle being flipped off and on.
    private var dateBinding: Binding<Date> {
        Binding(get: { goal.date ?? Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date() },
                set: { goal.date = $0 })
    }

    private func save() {
        var g = goal
        g.title = g.title.trimmingCharacters(in: .whitespacesAndNewlines)
        g.place = g.place.trimmingCharacters(in: .whitespacesAndNewlines)
        g.notes = g.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        g.date = hasDate ? Calendar.current.startOfDay(for: dateBinding.wrappedValue) : nil
        UpcomingGoalStore.shared.save(g)
        dismiss()
    }
}

/// One goal's own page, opened from the tutor's note: the countdown, what
/// the day will most likely ask (tap one to drill it with the tutor), and
/// every day of preparation so far.
struct UpcomingGoalPage: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let goal: UpcomingGoal
    @State private var questions: [GoalPrep.Question]?
    @State private var failed = false
    @State private var reading: TutorReading?
    @State private var editing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    UpcomingGoalRow(goal: goal)
                    if !goal.notes.isEmpty {
                        Text(goal.notes).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if let questions {
                        ForEach(questions) { q in
                            Button { drill(q.text) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(q.text).foregroundStyle(.primary)
                                        if !q.looksFor.isEmpty {
                                            Text(q.looksFor).font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "graduationcap.fill")
                                        .foregroundStyle(goal.kind.tint)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } else if failed {
                        Button("Try again") { failed = false; Task { await load() } }
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Working out what they'll ask…").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Likely questions")
                } footer: {
                    if questions != nil {
                        Text("Tap one to practice it with your tutor until it comes out clean.")
                    }
                }
                let days = GoalPrep.days(for: goal)
                if !days.isEmpty {
                    Section("Prepared so far") {
                        ForEach(days) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.focus).font(.subheadline.weight(.semibold))
                                Button { open(day, .reading) } label: {
                                    Label(day.reading.title, systemImage: "text.book.closed.fill")
                                }
                                Button { open(day, .speech) } label: {
                                    Label(day.speech.question ?? day.speech.title, systemImage: "music.mic")
                                }
                            }
                            .buttonStyle(.borderless)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle(goal.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") { editing = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $reading) { r in
                TutorReadingSheet(reading: r).environmentObject(appState)
            }
            .sheet(isPresented: $editing, onDismiss: {
                // Saved or deleted: the page shows a goal that may be gone.
                if !UpcomingGoalStore.shared.goals.contains(where: { $0.id == goal.id && $0.updatedAt == goal.updatedAt }) {
                    dismiss()
                }
            }) {
                UpcomingGoalEditor(goal: goal, language: goal.language).environmentObject(appState)
            }
        }
        .task { await load() }
    }

    private func load() async {
        if let cached = GoalPrep.cachedQuestions(for: goal) { questions = cached; return }
        do {
            questions = try await GoalPrep.questions(for: goal, appState: appState)
        } catch {
            failed = true
        }
    }

    private func open(_ day: GoalPrepDay, _ part: GoalPrep.Part) {
        reading = TutorReading(script: day.script(part), goal: goal, part: part)
    }

    /// A tutor-mode call on this one question. The page goes first: the
    /// call is a full-screen cover on the Talk home, which can't rise over
    /// a sheet.
    private func drill(_ question: String) {
        Analytics.capture("upcoming_goal_question_drill", ["kind": goal.kind.rawValue])
        dismiss()
        let call = TutorBot.GoalCall(topic: "\u{201C}\(question)\u{201D} — \(goal.title)",
                                     blurb: "Preparing for: " + goal.promptLine())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { TutorBot.shared.goalCall = call }
    }
}
