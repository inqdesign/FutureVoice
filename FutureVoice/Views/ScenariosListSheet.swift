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
    @State private var showingInterests = false
    @State private var newsTopics: [SuggestedTopic] = []
    @State private var loadingNews = false
    @State private var newsError: String?
    /// Set when the user taps a scenario's "Watch" — pushes WatchView with a
    /// synthetic counterpart built from the scenario's role.
    @State private var watchScenario: Scenario?

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
            .sheet(isPresented: $showingInterests, onDismiss: reloadNewsForInterests) {
                InterestsEditorSheet()
                    .environmentObject(appState)
            }
            .navigationDestination(item: $watchScenario) { s in
                WatchView(counterpart: Self.watchCounterpart(for: s),
                          customScenario: Self.watchScenarioText(s))
                    .environmentObject(appState)
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

    /// One-line scenario description handed to DialogueEngine as the topic.
    static func watchScenarioText(_ s: Scenario) -> String {
        let notes = s.notes.trimmingCharacters(in: .whitespaces)
        let base = "At \(s.environment), a conversation with the \(s.role)"
        return notes.isEmpty ? base : "\(base). \(notes)"
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
            // Stories come from the shared platform pool (cheap read), so
            // auto-load on open; the local cache skips even the network hop
            // within the same day.
            guard newsTopics.isEmpty, !interests.isEmpty else { return }
            if let cached = NewsTopicStore.shared.valid(for: interests) {
                newsTopics = displaySelection(from: cached)
            } else {
                await fetchNews()
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
                    HStack(spacing: 10) {
                        // Tap the row body → Talk (speak it yourself), the
                        // existing primary action.
                        Button {
                            applyAndDismiss(scenario)
                        } label: {
                            row(scenario)
                        }
                        .buttonStyle(.plain)
                        // Trailing pill → Watch (listen to your clone vs the
                        // role play it out).
                        Button {
                            watchScenario = scenario
                        } label: {
                            Label("Watch", systemImage: "play.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
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
                Button { showingInterests = true } label: {
                    Label("Add interests", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            } else if newsTopics.isEmpty {
                if loadingNews {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Finding stories…").foregroundStyle(.secondary)
                    }
                } else {
                    // Auto-load happens on open; this row is the retry path
                    // when that failed or returned nothing.
                    Button {
                        Task { await fetchNews() }
                    } label: {
                        Label("Load stories", systemImage: "newspaper")
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
            HStack(spacing: 16) {
                Text("In the news")
                Spacer()
                Button { showingInterests = true } label: {
                    Label("Edit interests", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
                if !newsTopics.isEmpty {
                    Button {
                        Task { await fetchNews(refresh: true) }
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

    private func fetchNews(refresh: Bool = false) async {
        loadingNews = true
        newsError = nil
        defer { loadingNews = false }
        if refresh {
            // What's on screen right now has been seen — rotate it back so
            // the refreshed list actually looks different.
            NewsTopicStore.shared.markSeen(newsTopics.map(\.title), interests: interests)
        }
        do {
            let pool = try await NewsTopicEngine.fetch(
                interests: interests,
                targetLanguage: appState.targetLanguage,
                refresh: refresh
            )
            if !pool.isEmpty {
                NewsTopicStore.shared.save(pool, interests: interests)
            }
            newsTopics = displaySelection(from: pool)
        } catch {
            newsError = error.localizedDescription
        }
    }

    /// Pick what to show from the (possibly larger) pool: unseen stories
    /// first, then seen ones that are NOT currently on screen, then the
    /// current list — refresh always changes the screen when the pool allows.
    private func displaySelection(from pool: [SuggestedTopic]) -> [SuggestedTopic] {
        let seen = Set(NewsTopicStore.shared.seenTitles(for: interests))
        let current = Set(newsTopics.map(\.title))
        let unseen = pool.filter { !seen.contains($0.title) }
        let seenOffscreen = pool.filter { seen.contains($0.title) && !current.contains($0.title) }
        let onscreen = pool.filter { seen.contains($0.title) && current.contains($0.title) }
        return Array((unseen + seenOffscreen + onscreen).prefix(NewsTopicEngine.maxShown))
    }

    /// After editing interests, refresh the news list against the new set.
    private func reloadNewsForInterests() {
        guard !interests.isEmpty else { newsTopics = []; return }
        if let cached = NewsTopicStore.shared.valid(for: interests) {
            newsTopics = displaySelection(from: cached)
        } else {
            newsTopics = []
            Task { await fetchNews() }
        }
    }

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
