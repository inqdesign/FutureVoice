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
