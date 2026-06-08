import SwiftUI

/// The Talk tab's "Topic" picker — primary surface for picking what to
/// practice. Shows the user's saved scenarios as the dominant content;
/// building a new one is a secondary action via the "+" toolbar button.
///
/// Mirrors the Counterpart pattern: build a few real situations once, reuse
/// every day. Beats the previous auto-suggested 5 that felt static.
struct ScenariosListSheet: View {
    @Binding var topic: String
    @Binding var topicBlurb: String
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showingBuilder = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.scenarios.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("What to practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingBuilder = true } label: {
                        Label("Build new", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingBuilder) {
                ScenarioBuilderSheet { newScenario in
                    appState.saveScenario(newScenario)
                    // Auto-pick the freshly built scenario so the user goes
                    // straight into practicing instead of tapping again.
                    applyAndDismiss(newScenario)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - States

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No scenarios yet", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Build a scenario you'd actually be in — like Cafe with a stranger, Kita with a parent, or Doctor's office. You'll reuse it.")
        } actions: {
            Button("Build your first") { showingBuilder = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var listContent: some View {
        List {
            ForEach(appState.scenarios) { scenario in
                Button {
                    applyAndDismiss(scenario)
                } label: {
                    row(scenario)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        appState.deleteScenario(id: scenario.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ s: Scenario) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle.fill")
                .foregroundStyle(.tint)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !s.notes.isEmpty {
                    Text(s.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func applyAndDismiss(_ s: Scenario) {
        topic = s.displayTitle
        topicBlurb = s.promptBlurb
        appState.markScenarioUsed(id: s.id)
        dismiss()
    }
}
