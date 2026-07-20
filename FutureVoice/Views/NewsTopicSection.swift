import SwiftUI

/// Shared "In the news" section — recent stories matched to the persona's
/// interests, backed by `NewsTopicEngine` + `NewsTopicStore`. Used by both
/// the Talk topic picker (`ScenariosListSheet`) and the Watch topic picker
/// (`WatchTopicSheet`); what happens on tap is the caller's `onPick`.
/// Must be placed inside a `List`/`Form`.
struct NewsTopicSection: View {
    /// Footer copy — each host phrases the payoff differently (talk vs watch).
    let footer: String
    let onPick: (SuggestedTopic) -> Void

    @EnvironmentObject private var appState: AppState

    @State private var newsTopics: [SuggestedTopic] = []
    @State private var loadingNews = false
    @State private var newsError: String?
    @State private var showingInterests = false

    private var interests: [String] { appState.persona?.interests ?? [] }

    var body: some View {
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
                        onPick(item)
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
            // Presentation + lifecycle hang off the header (not the Section
            // itself) so List keeps recognizing this as a plain section.
            .sheet(isPresented: $showingInterests, onDismiss: reloadNewsForInterests) {
                InterestsEditorSheet()
                    .environmentObject(appState)
            }
            .task {
                // Stories come from the shared platform pool (cheap read), so
                // auto-load on open; the local cache skips even the network
                // hop within the same day.
                guard newsTopics.isEmpty, !interests.isEmpty else { return }
                if let cached = NewsTopicStore.shared.valid(for: interests) {
                    newsTopics = displaySelection(from: cached)
                } else {
                    await fetchNews()
                }
            }
        } footer: {
            if !interests.isEmpty {
                Text(footer)
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
}
