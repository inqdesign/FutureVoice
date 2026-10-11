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
    let onPickExam: (ExamTopic, ExamKind) -> Void
    /// A topic made from the learner's own field (`PurposeTopicEngine`).
    let onPickTopic: (SuggestedTopic) -> Void
    let onPickScenario: (Scenario) -> Void
    let onAllScenarios: () -> Void
    let onBuildScenario: () -> Void

    @EnvironmentObject private var appState: AppState

    @State private var tab: DiscoverChip = .news
    /// The row opens on the first chip once, then stays where the learner put it.
    @State private var tabResolved = false
    /// Exam chip: which slice of the topic list is showing, and the filter.
    @State private var examShift = 0
    @State private var exam: ExamKind = .ielts
    /// Field topics per chip, once loaded; the chips being written now.
    @State private var fieldTopics: [DiscoverChip: [SuggestedTopic]] = [:]
    @State private var writingTopics: Set<DiscoverChip> = []
    @State private var failedTopics: Set<DiscoverChip> = []
    /// Where in a field's pool the shown eight start.
    @State private var fieldShift: [DiscoverChip: Int] = [:]
    @State private var newsTopics: [SuggestedTopic] = []
    @State private var loadingNews = false
    /// The last fetch failed. Painted as a quiet caption, never the raw
    /// error: with a list on screen it means "these may be yesterday's",
    /// with none it means "tap to retry".
    @State private var newsFetchFailed = false
    /// The one settings page for the whole row (`DiscoverSettingsSheet`).
    @State private var showingSettings = false
    /// Bumped when settings close, so the row re-reads its chips.
    @State private var settingsVersion = 0

    /// The row is the learner's purposes (`LearningPurposeStore.chips`):
    /// each purpose's own chip first, in the order picked, then news and
    /// their own situations. Never answered = the row as it always was.
    private var chips: [DiscoverChip] {
        _ = settingsVersion
        return LearningPurposeStore.chips(level: appState.proficiency)
    }

    private var interests: [String] { appState.persona?.interests ?? [] }

    /// News-born topic books stay out of here — they belong to the news
    /// taxonomy, not the scenario rail.
    private var scenarios: [Scenario] {
        appState.scenarios.filter { $0.isTopic != true && !$0.isMeetingScene && $0.starterId == nil }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch tab {
            case .news:      newsContent
            case .scenarios: scenariosContent
            case .exam:      examContent
            case .study, .work, .interview: fieldContent(tab)
            default:         startersContent(tab.starters ?? StarterSituation.all)
            }
        }
        .sheet(isPresented: $showingSettings, onDismiss: settingsClosed) {
            DiscoverSettingsSheet()
                .environmentObject(appState)
        }
        .onAppear {
            exam = LearningPurposeStore.exam(for: appState.targetLanguage)
            if !tabResolved || !chips.contains(tab) {
                tab = chips.first ?? .news
                tabResolved = true
            }
            #if DEBUG
            if DebugCapture.previewScenariosTab { tab = .everyday }
            if let c = UserDefaults.standard.string(forKey: "discoverChip").flatMap(DiscoverChip.init(rawValue:)) { tab = c }
            if UserDefaults.standard.bool(forKey: "discoverSettings") { showingSettings = true }
            if let json = UserDefaults.standard.string(forKey: "seedPurposeDetails"),
               let d = try? JSONDecoder().decode(PurposeDetails.self, from: Data(json.utf8)) {
                LearningPurposeStore.details = d
                settingsVersion += 1
            }
            #endif
        }
        .task {
            // Stories come from the shared platform pool (cheap read), so
            // auto-load on open; the local cache skips even the network hop
            // within the same day.
            guard newsTopics.isEmpty, !interests.isEmpty else { return }
            guard let cached = NewsTopicStore.shared.valid(for: interests) else {
                // No fresh cache: paint whatever was saved last (however old)
                // so the section is never empty on open, then fetch today's
                // behind it. A failed fetch leaves the old list standing.
                if let stale = NewsTopicStore.shared.lastKnown(for: interests) {
                    newsTopics = displaySelection(from: stale)
                }
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
            // Four chips and two buttons don't fit a phone in every
            // language; past three the chips scroll sideways instead.
            if chips.count > 3 {
                // Clipped BEFORE the buttons, and faded at that edge so the
                // cut reads as "slide for more" rather than a chip broken in
                // half. Unclipped, the chips ran under the buttons.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(chips) { chip($0) } }
                        .padding(.trailing, 16)
                }
                .frame(maxWidth: .infinity)
                .mask(
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 20)
                    }
                )
            } else {
                ForEach(chips) { chip($0) }
                Spacer()
            }
            // The row's own buttons as one group, spaced for a thumb — at the
            // row's 8 pt they read as one control and a tap hit the wrong one.
            HStack(spacing: 20) {
                if tab == .exam {
                    Button { examShift += Self.examShown } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Other topics")
                } else if fieldContext(tab) != nil {
                    Button { Task { await loadFieldTopics(tab, fresh: true) } } label: {
                        if writingTopics.contains(tab) {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(writingTopics.contains(tab))
                    .accessibilityLabel("Other topics")
                } else if tab == .news, !newsTopics.isEmpty {
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
                } else if tab == .scenarios {
                    Button(action: onBuildScenario) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Build a scenario")
                }
                // One settings button whatever chip is showing — the chips,
                // the exam and the interests are one page.
                Button { showingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Talk settings")
            }
        }
        .padding(.horizontal, 20)
    }

    private func chip(_ t: DiscoverChip) -> some View {
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
    private func listCard(title: String, caption: String?, done: Bool = false,
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
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Done")
            }
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
            Button { showingSettings = true } label: {
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
        if newsFetchFailed {
            Text(newsTopics.isEmpty ? "Couldn't load stories" : "Showing earlier stories")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Exam

    private static let examShown = 5

    /// Common questions of the picked exam, five at a time; refresh shows the
    /// next five. Same card as a news story — tapping talks it through.
    private var examContent: some View {
        let all = ExamTopics.topics(for: exam, language: appState.targetLanguage)
        let start = all.isEmpty ? 0 : (examShift % all.count)
        let shown = (0..<min(Self.examShown, all.count)).map { all[(start + $0) % all.count] }
        return list {
            ForEach(shown) { topic in
                Button { onPickExam(topic, exam) } label: {
                    listCard(title: topic.title, caption: "\(exam.name) · \(topic.part)") {
                        Image(systemName: "graduationcap.fill")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Field topics (studies, work, interview)

    private var details: PurposeDetails {
        _ = settingsVersion
        return LearningPurposeStore.details
    }

    private func fieldContext(_ chip: DiscoverChip) -> String? { PurposeTopicEngine.field(for: chip, details: details) }

    /// Topics from what the learner wrote about their field, then — for work
    /// and interviews — the ready-made situations under them. Nothing written
    /// yet: one row that says what writing it buys, opening the settings.
    @ViewBuilder
    private func fieldContent(_ chip: DiscoverChip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if fieldContext(chip) == nil {
                list {
                    Button { showingSettings = true } label: {
                        listCard(title: Self.askLine(chip), caption: nil) {
                            Image(systemName: "square.and.pencil").font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else if let pool = fieldTopics[chip], !pool.isEmpty {
                list {
                    ForEach(shownField(chip, pool)) { t in
                        Button {
                            onPickTopic(SuggestedTopic(
                                title: t.title,
                                blurb: PurposeTopicEngine.launchBlurb(t, chip: chip, details: details)))
                        } label: {
                            listCard(title: t.title, caption: nil) {
                                Image(systemName: Self.fieldIcon(chip)).font(.subheadline)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if failedTopics.contains(chip) {
                Button { Task { await loadFieldTopics(chip, fresh: true) } } label: {
                    Label("Couldn't write topics — try again", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .padding(.horizontal, 20)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Writing topics for your field…").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            }
            if let starters = chip.starters { startersContent(starters) }
        }
        .task(id: "\(chip.rawValue)|\(fieldContext(chip) ?? "")|\(appState.targetLanguage)") {
            await loadFieldTopics(chip, fresh: false)
        }
    }

    /// Eight at a time from the shared pool, starting where refresh left off.
    private func shownField(_ chip: DiscoverChip, _ pool: [SuggestedTopic]) -> [SuggestedTopic] {
        let start = (fieldShift[chip] ?? 0) % pool.count
        return (0..<min(PurposeTopicEngine.shown, pool.count)).map { pool[(start + $0) % pool.count] }
    }

    /// `fresh`: the refresh button. Walk on through the pool while it has
    /// unseen topics; at its end, ask the server to grow it (capped there).
    private func loadFieldTopics(_ chip: DiscoverChip, fresh: Bool) async {
        guard fieldContext(chip) != nil, !writingTopics.contains(chip) else { return }
        let lang = appState.targetLanguage, level = appState.proficiency
        if !fresh, let cached = PurposeTopicEngine.cached(for: chip, details: details, language: lang, level: level) {
            fieldTopics[chip] = cached
            return
        }
        if fresh, let pool = fieldTopics[chip] {
            let next = (fieldShift[chip] ?? 0) + PurposeTopicEngine.shown
            if next < pool.count { fieldShift[chip] = next; return }
        }
        writingTopics.insert(chip)
        failedTopics.remove(chip)
        defer { writingTopics.remove(chip) }
        let before = fieldTopics[chip]?.count ?? 0
        if let topics = try? await PurposeTopicEngine.fetch(for: chip, details: details, language: lang,
                                                            level: level, refresh: fresh),
           !topics.isEmpty {
            fieldTopics[chip] = topics
            // Grown: show the new ones. Not grown (the pool is full): start over.
            fieldShift[chip] = fresh ? (topics.count > before ? before : 0) : 0
        } else if fieldTopics[chip] == nil {
            failedTopics.insert(chip)
        }
    }

    private static func askLine(_ chip: DiscoverChip) -> String {
        switch chip {
        case .study:     return explain("Add your school and subject for topics from your field")
        case .interview: return explain("Add the role you're applying for — I'll ask its questions")
        default:         return explain("Add your job and role for topics from your work")
        }
    }

    private static func fieldIcon(_ chip: DiscoverChip) -> String {
        switch chip {
        case .study:     return "book.fill"
        case .interview: return "person.crop.square"
        default:         return "briefcase.fill"
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
            ownScenarios
        }
    }

    /// The Everyday chip: ready-made challenges (`StarterSituation`) on a
    /// chip of their own, so they sit right under the chips instead of below
    /// the learner's own list. A tap starts the call; one already talked
    /// through carries a check.
    private func startersContent(_ starters: [StarterSituation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            list {
                ForEach(starters) { starter in
                    let existing = appState.scenarios.first { $0.starterId == starter.id }
                    Button {
                        onPickScenario(starter.scenario(in: appState.scenarios,
                                                        language: appState.targetLanguage))
                    } label: {
                        listCard(title: starter.title,
                                 caption: starter.showsRole ? chrome("with \(starter.role)") : nil,
                                 done: existing?.lastUsedAt != nil) {
                            Image(systemName: starter.icon)
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ownScenarios: some View {
        Group {
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
        newsFetchFailed = false
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
            // Same thing, other shape: a cancellation that lands while the
            // request is in flight surfaces as `URLError(.cancelled)`, whose
            // description is literally "cancelled" — and painted red under
            // the list every time someone left within the ~30 s poll window.
            guard !Task.isCancelled else { return }
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            newsFetchFailed = true
            // Nothing on screen: fall back to the last batch we ever saved
            // for these interests rather than leaving the slot empty.
            if newsTopics.isEmpty, let stale = NewsTopicStore.shared.lastKnown(for: interests) {
                newsTopics = displaySelection(from: stale)
            }
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

    /// Settings closed: the chips may have changed (stay on the chip if it
    /// is still there, else the new first one), the exam, the interests.
    private func settingsClosed() {
        settingsVersion += 1
        if !chips.contains(tab) { tab = chips.first ?? .news }
        let newExam = LearningPurposeStore.exam(for: appState.targetLanguage)
        if newExam != exam { exam = newExam; examShift = 0 }
        fieldTopics = fieldTopics.filter { fieldContext($0.key) != nil }
        reloadNewsForInterests()
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


