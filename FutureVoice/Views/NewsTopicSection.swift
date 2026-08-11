import SwiftUI

/// Home's discover block: a chip switch (News · Scenarios) over ONE
/// horizontal card rail. News = recent stories matched to the persona's
/// interests (`NewsTopicEngine` + `NewsTopicStore`); Scenarios = the user's
/// own situations, recency-first. Tapping a card starts the call via the
/// host's closures.
///
/// Lives in a plain ScrollView/VStack (NOT a List) — the rail spans the full
/// screen width naturally, cards align to the shared 20pt grid via inner
/// padding, and nothing can clip them at a section boundary.
struct DiscoverSection: View {
    let onPickNews: (SuggestedTopic) -> Void
    let onPickScenario: (Scenario) -> Void
    let onAllScenarios: () -> Void
    let onBuildScenario: () -> Void

    @EnvironmentObject private var appState: AppState

    @State private var tab: Tab = .news
    @State private var newsTopics: [SuggestedTopic] = []
    @State private var loadingNews = false
    @State private var newsError: String?
    @State private var showingInterests = false

    enum Tab: String, CaseIterable {
        case news = "News"
        case scenarios = "Scenarios"

        /// Chrome, so it follows the TARGET language. The raw value stays an
        /// identifier — localizing it would key state off translated text.
        var label: String {
            switch self {
            case .news:      return chrome("News")
            case .scenarios: return chrome("Scenarios")
            }
        }
    }

    private var interests: [String] { appState.persona?.interests ?? [] }

    /// News-born topic books stay out of here — they belong to the news
    /// taxonomy, not the scenario rail.
    private var scenarios: [Scenario] {
        appState.scenarios.filter { $0.isTopic != true && !$0.isMeetingScene }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch tab {
            case .news:      newsContent
            case .scenarios: scenariosContent
            }
        }
        .sheet(isPresented: $showingInterests, onDismiss: reloadNewsForInterests) {
            InterestsEditorSheet()
                .environmentObject(appState)
        }
        .task {
            // Stories come from the shared platform pool (cheap read), so
            // auto-load on open; the local cache skips even the network hop
            // within the same day.
            guard newsTopics.isEmpty, !interests.isEmpty else { return }
            guard let cached = NewsTopicStore.shared.valid(for: interests) else {
                await fetchNews()
                return
            }
            // Paint the cache instantly, then top up in the background if it
            // was saved while some categories were still generating.
            newsTopics = displaySelection(from: cached)
            let covered = Set(cached.compactMap(\.category))
            if covered.count < interests.count { await fetchNews() }
        }
    }

    // MARK: - Header (chips + per-tab accessories)

    private var header: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { t in
                chip(t)
            }
            Spacer()
            if tab == .news {
                Button { showingInterests = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Edit interests")
                if !newsTopics.isEmpty {
                    Button {
                        Task { await refreshNews() }
                    } label: {
                        if loadingNews {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(loadingNews)
                    .accessibilityLabel("Refresh stories")
                }
            } else {
                Button(action: onBuildScenario) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Build a scenario")
            }
        }
        .padding(.horizontal, 20)
    }

    private func chip(_ t: Tab) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { tab = t } } label: {
            Text(t.label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(tab == t ? Color(.label) : Color(.secondarySystemGroupedBackground)))
                .foregroundStyle(tab == t ? Color(.systemBackground) : Color.primary)
        }
        .buttonStyle(.plain)
    }

    /// The one list both tabs share: full-width stacked cards on the 20pt
    /// grid (the old horizontal rail read as posters; these read as a list).
    private func list<Content: View>(@ViewBuilder _ cards: () -> Content) -> some View {
        VStack(spacing: 10) { cards() }
            .padding(.horizontal, 20)
    }

    /// One list card — leading icon in a tinted circle, title + caption,
    /// chevron. The shared row anatomy for news stories and scenarios.
    private func listCard(title: String, caption: String?,
                          @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                icon()
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
    }

    /// Best-effort glyph for a free-form interest category ("ai / tech" →
    /// cpu). Fallback is the newspaper — every story is at least news.
    private static func categoryIcon(_ category: String?) -> String {
        guard let c = category?.lowercased() else { return "newspaper.fill" }
        if c.contains("ai") || c.contains("tech") { return "cpu" }
        if c.contains("cook") || c.contains("food") { return "fork.knife" }
        if c.contains("sport") || c.contains("fitness") { return "figure.run" }
        if c.contains("music") { return "music.note" }
        if c.contains("travel") { return "airplane" }
        if c.contains("science") { return "atom" }
        if c.contains("business") || c.contains("finance") { return "chart.line.uptrend.xyaxis" }
        if c.contains("film") || c.contains("movie") || c.contains("tv") { return "film" }
        if c.contains("game") { return "gamecontroller" }
        if c.contains("health") { return "heart" }
        return "newspaper.fill"
    }

    // MARK: - News

    @ViewBuilder
    private var newsContent: some View {
        if interests.isEmpty {
            Button { showingInterests = true } label: {
                Label("Add interests", systemImage: "plus.circle")
                    .font(.subheadline)
            }
            .padding(.horizontal, 20)
        } else if newsTopics.isEmpty {
            if loadingNews {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding stories…").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            } else {
                // Auto-load happens on open; this is the retry path when
                // that failed or returned nothing.
                Button {
                    Task { await fetchNews() }
                } label: {
                    Label("Load stories", systemImage: "newspaper")
                        .font(.subheadline)
                }
                .padding(.horizontal, 20)
            }
        } else {
            list {
                ForEach(newsTopics) { item in
                    Button { onPickNews(item) } label: {
                        listCard(title: item.title,
                                 caption: item.category?.capitalized) {
                            Image(systemName: Self.categoryIcon(item.category))
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if let e = newsError {
            Text(e).font(.caption).foregroundStyle(.red)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Scenarios

    @ViewBuilder
    private var scenariosContent: some View {
        if scenarios.isEmpty {
            Button(action: onBuildScenario) {
                Label("Build your first scenario", systemImage: "plus")
                    .font(.subheadline)
            }
            .padding(.horizontal, 20)
        } else {
            list {
                ForEach(scenarios.prefix(5)) { s in
                    let name = personaName(s)
                    let partner: String? = {
                        if let name { return name }
                        let r = s.role.trimmingCharacters(in: .whitespaces)
                        return r.isEmpty ? nil : r
                    }()
                    Button { onPickScenario(s) } label: {
                        // The tidy summary as the title, NOT the raw prompt.
                        listCard(title: s.cardTitle,
                                 caption: partner.map { chrome("with \($0)") }) {
                            if let name {
                                Text(Books.initials(name))
                                    .font(.caption.weight(.semibold))
                            } else {
                                Image(systemName: s.categoryIcon ?? Books.roleIcon(for: s.role))
                                    .font(.subheadline)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    // Cards don't swipe — long-press to delete.
                    .contextMenu {
                        Button(role: .destructive) {
                            appState.deleteScenario(id: s.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                // List tail — the door to the full collection.
                Button(action: onAllScenarios) {
                    listCard(title: chrome("All scenarios"),
                             caption: "\(scenarios.count)") {
                        Image(systemName: "rectangle.stack")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func personaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }

    // MARK: - News data

    /// The refresh button. Rotating the pool the user hasn't seen yet costs
    /// NOTHING — no network, no generation — so try that first and only ask
    /// the server for new stories once the local pool is exhausted. Most
    /// taps land on the instant path.
    private func refreshNews() async {
        if let cached = NewsTopicStore.shared.valid(for: interests), cached.count > newsTopics.count {
            NewsTopicStore.shared.markSeen(newsTopics.map(\.title), interests: interests)
            let rotated = displaySelection(from: cached)
            if rotated.map(\.title) != newsTopics.map(\.title) {
                newsTopics = rotated
                return
            }
        }
        await fetchNews(refresh: true)
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
            var pool = try await NewsTopicEngine.fetch(
                interests: interests,
                targetLanguage: appState.targetLanguage,
                refresh: refresh
            )
            apply(pool)

            // The server answers with whatever is generated and keeps the
            // rest cooking in the background, so keep asking until every
            // category has landed — each poll paints the ones that finished
            // instead of holding one long request open. A refresh polls
            // until the pool actually grows: its extra batch is generated
            // in the background too.
            var polls = 0
            var target = pool.growing ? pool.topics.count + 1 : 0
            while polls < NewsTopicEngine.maxPolls,
                  !pool.isComplete || pool.topics.count < target {
                try await Task.sleep(for: NewsTopicEngine.pollInterval)
                polls += 1
                pool = try await NewsTopicEngine.fetch(
                    interests: interests,
                    targetLanguage: appState.targetLanguage
                )
                apply(pool)
                // Stop chasing growth once it arrives.
                if pool.topics.count >= target { target = 0 }
            }
        } catch is CancellationError {
            // View went away mid-poll — nothing to report.
        } catch {
            newsError = error.localizedDescription
        }
    }

    /// Paint a fetched pool and cache it. Partial pools are cached too — a
    /// story on screen next open beats an empty section — and the `.task`
    /// re-fetch tops them up.
    private func apply(_ pool: NewsTopicEngine.Pool) {
        guard !pool.topics.isEmpty else { return }
        NewsTopicStore.shared.save(pool.topics, interests: interests)
        newsTopics = displaySelection(from: pool.topics)
        // Stories are up: drop the spinner even though polling continues.
        loadingNews = false
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
