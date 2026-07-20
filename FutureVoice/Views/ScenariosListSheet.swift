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
    /// True when the pick came from "In the news" — the conversation then
    /// opens with a search-grounded fact lookup so the avatar knows the story.
    @Binding var topicIsNews: Bool
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showingBuilder = false

    private var interests: [String] { appState.persona?.interests ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if appState.scenarios.isEmpty && interests.isEmpty {
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
                ScenarioBuilderSheet(counterparts: appState.counterparts) { newScenario in
                    appState.saveScenario(newScenario)
                    // Auto-pick the freshly built scenario so the user goes
                    // straight into practicing instead of tapping again.
                    applyAndDismiss(newScenario)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Scenario → Watch (synthetic counterpart)

    /// Builds a throwaway counterpart from the scenario's role so DialogueEngine
    /// can stage a clone-vs-role dialogue. Not saved — see `WatchView.persist`.
    static func watchCounterpart(for s: Scenario) -> Counterpart {
        var c = Counterpart.empty
        c.name = s.role.trimmingCharacters(in: .whitespaces).isEmpty ? "the other person" : s.role
        c.location = s.environment
        c.background = s.notes
        c.voicePresetId = VoicePreset.catalog.first!.id
        return c
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
            scenariosSection
            NewsTopicSection(
                footer: "Recent stories matched to your interests — talk about something that actually happened this week.",
                onPick: applyNewsAndDismiss
            )
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var scenariosSection: some View {
        Section("Your scenarios") {
            if appState.scenarios.isEmpty {
                Button { showingBuilder = true } label: {
                    Label("Build your first scenario", systemImage: "plus")
                        .font(.subheadline)
                }
            } else {
                ForEach(appState.scenarios) { scenario in
                    // Tap → Talk with this scenario. Watching its scene lives
                    // in the book page (Watch tab), not in the Talk picker.
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
        }
    }

    // MARK: - In the news (section itself lives in NewsTopicSection)

    private func applyNewsAndDismiss(_ item: SuggestedTopic) {
        topic = item.title
        // The blurb is factual context from the search results — hand it to
        // the avatar as starting context so the conversation sticks to what
        // actually happened.
        topicBlurb = "Recent news to discuss (facts from coverage): \(item.blurb)"
        topicIsNews = true
        dismiss()
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
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func applyAndDismiss(_ s: Scenario) {
        topic = s.displayTitle
        topicBlurb = s.promptBlurb
        topicIsNews = false
        appState.markScenarioUsed(id: s.id)
        dismiss()
    }
}
