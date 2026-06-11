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
    @State private var newsTopics: [SuggestedTopic] = []
    @State private var loadingNews = false
    @State private var newsError: String?

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
            scenariosSection
            newsSection
        }
        .listStyle(.insetGrouped)
        .task {
            // Show today's cached batch instantly; fetching is an explicit
            // tap because search-grounded calls cost more than plain ones.
            if newsTopics.isEmpty, let cached = NewsTopicStore.shared.valid(for: interests) {
                newsTopics = cached
            }
        }
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

    // MARK: - In the news

    @ViewBuilder
    private var newsSection: some View {
        Section {
            if interests.isEmpty {
                Text("Add interests in Me → Profile and current stories you'd actually talk about show up here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if newsTopics.isEmpty {
                if loadingNews {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Finding stories…").foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task { await fetchNews() }
                    } label: {
                        Label("Get today's stories", systemImage: "newspaper")
                            .font(.subheadline)
                    }
                }
            } else {
                ForEach(newsTopics) { item in
                    Button {
                        applyNewsAndDismiss(item)
                    } label: {
                        newsRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let e = newsError {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        } header: {
            HStack {
                Text("In the news")
                Spacer()
                if !newsTopics.isEmpty {
                    Button {
                        Task { await fetchNews() }
                    } label: {
                        if loadingNews {
                            ProgressView().controlSize(.mini)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                    }
                    .disabled(loadingNews)
                }
            }
        } footer: {
            if !interests.isEmpty {
                Text("Recent stories matched to your interests — talk about something that actually happened this week.")
            }
        }
    }

    private func newsRow(_ item: SuggestedTopic) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "newspaper.fill")
                .foregroundStyle(.tint)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !item.blurb.isEmpty {
                    Text(item.blurb)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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

    private func fetchNews() async {
        loadingNews = true
        newsError = nil
        defer { loadingNews = false }
        do {
            let fresh = try await NewsTopicEngine.suggest(
                interests: interests,
                targetLanguage: appState.targetLanguage
            )
            newsTopics = fresh
            NewsTopicStore.shared.save(fresh, interests: interests)
        } catch {
            newsError = error.localizedDescription
        }
    }

    private func applyNewsAndDismiss(_ item: SuggestedTopic) {
        topic = item.title
        // The blurb is factual context from the search results — hand it to
        // the avatar as starting context so the conversation sticks to what
        // actually happened.
        topicBlurb = "Recent news to discuss (facts from coverage): \(item.blurb)"
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
