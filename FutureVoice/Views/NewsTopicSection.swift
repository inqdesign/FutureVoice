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
            case .news:      return String(localized: "News")
            case .scenarios: return String(localized: "Scenarios")
            }
        }
    }

    private var interests: [String] { appState.persona?.interests ?? [] }

    /// News-born topic books stay out of here — they belong to the news
    /// taxonomy, not the scenario rail.
    private var scenarios: [Scenario] {
        appState.scenarios.filter { $0.isTopic != true }
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
            if let cached = NewsTopicStore.shared.valid(for: interests) {
                newsTopics = displaySelection(from: cached)
            } else {
                await fetchNews()
            }
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
                        Task { await fetchNews(refresh: true) }
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

    /// The one rail both tabs share: full-width scroll track, cards inset to
    /// the 20pt grid by the HStack's own padding.
    private func rail<Content: View>(@ViewBuilder _ cards: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) { cards() }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
        }
        .scrollClipDisabled()
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
            rail {
                ForEach(newsTopics) { item in
                    Button { onPickNews(item) } label: { newsCard(item) }
                        .buttonStyle(.plain)
                }
            }
        }
        if let e = newsError {
            Text(e).font(.caption).foregroundStyle(.red)
                .padding(.horizontal, 20)
        }
    }

    /// Rail card WIDTH — narrower than a Practice grid card; the rail wants
    /// tall, poster-ish cards you flick through, not wide review tiles.
    private static let cardWidth: CGFloat = 176

    /// A news STORY to start a call about — the Practice card's visual
    /// language (rounded surface, bare tinted glyph, text pinned to the
    /// bottom) but purpose-built for tapping into a conversation, so there's
    /// no mastery strip. Category sits in the top-right, opposite the glyph.
    private func newsCard(_ item: SuggestedTopic) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: "newspaper.fill").font(.title2).foregroundStyle(.tint)
                Spacer()
                if let category = item.category, !category.isEmpty {
                    Text(category.capitalized)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 14)
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if !item.blurb.isEmpty {
                Text(item.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    // Breathing room between headline and its detail.
                    .padding(.top, 7)
            }
        }
        .padding(14)
        .frame(width: Self.cardWidth, alignment: .leading)
        .frame(minHeight: 190, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
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
            rail {
                ForEach(scenarios.prefix(8)) { s in
                    Button { onPickScenario(s) } label: { scenarioCard(s) }
                        .buttonStyle(.plain)
                        // Horizontal cards can't swipe — long-press to delete.
                        .contextMenu {
                            Button(role: .destructive) {
                                appState.deleteScenario(id: s.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                allScenariosCard
            }
        }
    }

    /// A SITUATION to talk out — same visual language as the news card
    /// (Practice's surface + bare glyph), no mastery strip: tapping starts
    /// the call, it isn't a review book here.
    private func scenarioCard(_ s: Scenario) -> some View {
        let name = personaName(s)
        let partner: String? = {
            if let name { return name }
            let r = s.role.trimmingCharacters(in: .whitespaces)
            return r.isEmpty ? nil : r
        }()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                if let name {
                    Text(Books.initials(name)).font(.title3.weight(.bold)).foregroundStyle(.tint)
                } else {
                    Image(systemName: s.categoryIcon ?? Books.roleIcon(for: s.role))
                        .font(.title2).foregroundStyle(.tint)
                }
                Spacer()
                if let category = s.category, !category.isEmpty {
                    Text(category)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 14)
            // The tidy summary, NOT the raw prompt the user typed.
            Text(s.cardTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if let partner {
                Text("with \(partner)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 7)
            }
        }
        .padding(14)
        .frame(width: Self.cardWidth, alignment: .leading)
        .frame(minHeight: 190, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
    }

    private func personaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }

    /// Rail tail — the door to the full collection (browse, build, delete).
    private var allScenariosCard: some View {
        Button(action: onAllScenarios) {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.title2).foregroundStyle(.tint)
                Text("All scenarios")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(scenarios.count)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 120)
            .frame(minHeight: 190)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - News data

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
