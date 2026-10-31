import SwiftUI

/// The goals under each picked purpose, as tick rows — setup's "Imagine your
/// future" step and the Me → Profile editor draw the same rows. As many as
/// the learner likes.
struct FutureGoalRows: View {
    let purposes: [LearningPurpose]
    @Binding var picked: [FutureGoal]

    var body: some View {
        ForEach(purposes) { purpose in
            Section {
                ForEach(FutureGoal.options(for: purpose)) { goal in
                    row(goal)
                }
            } header: {
                Text(purpose.title)
            }
        }
    }

    private func row(_ goal: FutureGoal) -> some View {
        let on = picked.contains(goal)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                if on { picked.removeAll { $0 == goal } }
                else { picked.append(goal) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Color.themeAccent : Color(.tertiaryLabel))
                    .accessibilityHidden(true)
                Text(goal.title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Me → Profile: change the goals later. Shows the purposes the learner
/// picked, or every purpose when there are none on file.
struct FutureGoalsEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [FutureGoal] = []

    private var purposes: [LearningPurpose] {
        var list = LearningPurposeStore.purposes
        // A goal already on file keeps its purpose on screen.
        for g in appState.persona?.futureGoals ?? [] where !list.contains(g.purpose) {
            list.append(g.purpose)
        }
        return list.isEmpty ? LearningPurpose.allCases : list
    }

    var body: some View {
        NavigationStack {
            Form {
                FutureGoalRows(purposes: purposes, picked: $picked)
                Section {} footer: {
                    Text(explain("Pick as many as you like. Your fluent self already lives them."))
                }
            }
            .navigationTitle(chrome("My future"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BarCloseButton(title: "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .onAppear { picked = appState.persona?.futureGoals ?? [] }
    }

    private func save() {
        guard var p = appState.persona else { dismiss(); return }
        p.goals = picked.map(\.rawValue)
        p.updatedAt = Date()
        appState.savePersona(p)
        dismiss()
    }
}
