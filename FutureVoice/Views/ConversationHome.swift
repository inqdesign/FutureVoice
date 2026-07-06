import SwiftUI

/// Home — Notion-simple: white space, hairline dividers, minimal text. Plain
/// section headers instead of heavy cards; one accent only on the primary
/// action. Today (goal + start a talk) and Practice (bookmarked words).
struct ConversationHome: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @ObservedObject private var vocab = VocabStore.shared

    @State private var snapshot = PracticeStats.Snapshot(
        streakDays: 0, totalSessions: 0, lastScorecard: nil,
        lastSessionEndedAt: nil, lastSevenDayScores: Array(repeating: 0, count: 7),
        shadowableLineCount: 0
    )
    @State private var sessionCount = 0
    @State private var dueCount = 0
    @State private var todaySpokenSeconds = 0
    @AppStorage("futurevoice.dailyGoalMinutes") private var dailyGoalMinutes = 10
    @State private var showingCall = false
    @State private var showingTopics = false
    @State private var showingProfile = false
    @State private var launchTopic = ""
    @State private var launchBlurb = ""
    @State private var launchIsNews = false
    /// "Up next" feed: today's most useful follow-ups after talking.
    @State private var topShadowPick: PracticeStats.ShadowPick?
    @State private var lastSession: Session?
    @State private var shadowingPick: PracticeStats.ShadowPick?
    /// Server-side credit balance — shown in the header so running low is
    /// never a surprise mid-conversation. nil until the first fetch lands.
    @State private var account: AccountStatus?
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if sessionCount == 0 {
                    emptyState
                } else {
                    // Card layout, same idiom as ProgressTab's panels: grouped
                    // background, one rounded card per content block.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            card { todaySection }
                            if hasUpNext {
                                card { upNextSection }
                            }
                            card { practiceSection }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                        .padding(.bottom, 36)
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(greetingText)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                // Credits moved into the Today card — the chip up here was
                // squeezing the large title into "Good mor…".
                ToolbarItemGroup {
                    profileButton
                }
            }
            .onAppear(perform: reload)
            .sheet(isPresented: $showingPaywall, onDismiss: refreshAccount) {
                // Only pitch the trial to someone who still has free credits;
                // a spent balance means they've already used the free tier.
                PaywallView(offerTrial: (account?.creditBalance ?? 0) > 0)
            }
            .sheet(isPresented: $showingProfile) {
                MeTab().environmentObject(appState).environmentObject(auth)
            }
            .sheet(isPresented: $showingTopics, onDismiss: launchIfTopicPicked) {
                ScenariosListSheet(topic: $launchTopic, topicBlurb: $launchBlurb,
                                   topicIsNews: $launchIsNews)
                    .environmentObject(appState)
            }
            .fullScreenCover(isPresented: $showingCall, onDismiss: reload) {
                ConversationView(initialTopic: launchTopic, initialBlurb: launchBlurb,
                                 initialIsNews: launchIsNews)
                    .environmentObject(appState)
            }
            .sheet(item: $shadowingPick, onDismiss: reload) { pick in
                ShadowDrillView(turn: pick.turn, targetLanguage: appState.targetLanguage)
                    .environmentObject(appState)
            }
        }
    }

    private var profileButton: some View {
        Button { showingProfile = true } label: {
            ProfileAvatar(initials: appState.persona?.displayName ?? "", size: 30)
        }
        .accessibilityLabel("Profile & settings")
    }

    private func refreshAccount() {
        Task { account = await AccountStatus.fetch() }
    }

    /// One home card — mirrors ProgressTab's `panel` so both dashboards read
    /// as the same design system.
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hello"
        }
    }

    // MARK: - Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink {
                ActivityView()
            } label: {
                HStack {
                    Text("Today").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(todaySpokenSeconds / 60) of \(dailyGoalMinutes) min")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                progressBar
            }

            HStack(spacing: 18) {
                stat(icon: "flame.fill", text: "\(snapshot.streakDays) streak",
                     tint: snapshot.streakDays > 0 ? .orange : .secondary)
                stat(icon: "bubble.left.and.bubble.right.fill",
                     text: "\(appState.learnerProfile.totalSessions) talks", tint: .secondary)
                // Balance lives here now (not the nav bar — it was squeezing
                // the greeting title). Quiet while healthy, orange when low;
                // tap opens the plans. Hidden until the first fetch so it
                // never flashes a wrong "0".
                if let account {
                    Button { showingPaywall = true } label: {
                        stat(icon: "bolt.fill",
                             text: "\(account.creditBalance)",
                             tint: account.creditBalance <= 10 ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(account.creditBalance) credits")
                }
            }

            talkStarter
        }
    }

    private var progressBar: some View {
        let goal = max(1, dailyGoalMinutes * 60)
        let progress = min(1.0, Double(todaySpokenSeconds) / Double(goal))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill))
                Capsule().fill(progress >= 1 ? Color.green : Color.accentColor)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 6)
    }

    private func stat(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var talkStarter: some View {
        HStack(spacing: 10) {
            Button {
                launchTopic = ""; launchBlurb = ""; launchIsNews = false; showingCall = true
            } label: {
                Text("Free talk").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)

            Button {
                launchTopic = ""; launchBlurb = ""; launchIsNews = false; showingTopics = true
            } label: {
                Text("Topics").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Up next

    private var hasUpNext: Bool {
        dueCount > 0 || topShadowPick != nil || lastSession != nil
    }

    /// The day's follow-ups after talking — due review cards, one curated
    /// shadow line, and the last conversation's post-mortem. Each is a single
    /// quiet row; the heavy lifting stays in the Practice tab.
    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Up next")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 10)

            if dueCount > 0 {
                NavigationLink {
                    DrillView()
                        .navigationTitle("Review")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    upNextRow(icon: "rectangle.stack.fill",
                              title: "Review due",
                              subtitle: dueCount == 1 ? "1 card waiting" : "\(dueCount) cards waiting")
                }
                .buttonStyle(.plain)
            }

            if let pick = topShadowPick {
                Button {
                    shadowingPick = pick
                } label: {
                    upNextRow(icon: "waveform.badge.mic",
                              title: "Shadow a line",
                              subtitle: pick.turn.transcript)
                }
                .buttonStyle(.plain)
            }

            if let last = lastSession {
                NavigationLink {
                    ConversationDetailView(session: last)
                } label: {
                    upNextRow(icon: "text.bubble",
                              title: last.displayTitle,
                              subtitle: lastSessionSubtitle(last))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func upNextRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func lastSessionSubtitle(_ session: Session) -> String {
        let when = Self.relativeFormatter.localizedString(
            for: session.endedAt ?? session.startedAt, relativeTo: Date())
        if let top = session.summary?.scorecard?.topLine, !top.isEmpty {
            return "\(when) · \(top)"
        }
        return "\(when) · read it back, shadow any line"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    // MARK: - Practice

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Practice").font(.title3.weight(.semibold))
                Spacer()
                NavigationLink { VocabularyView() } label: {
                    Text("Notebook").font(.subheadline).foregroundStyle(.tint)
                }
            }

            if vocab.studying.isEmpty {
                Text("Bookmark words while you study and they'll show up here.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(vocab.studying.prefix(6)), id: \.self) { word in
                        StudyWordCard(word: word, native: appState.nativeLanguage)
                    }
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Talk with your fluent self", systemImage: "phone.bubble")
        } description: {
            Text("Start a conversation and it shows up here.")
        } actions: {
            Button("Free talk") { launchTopic = ""; launchBlurb = ""; launchIsNews = false; showingCall = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Logic

    private func launchIfTopicPicked() {
        if !launchTopic.isEmpty { showingCall = true }
    }

    private func reload() {
        refreshAccount()   // talks spend credits — keep the header honest
        let sessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        sessionCount = sessions.count
        snapshot = PracticeStats.snapshot()
        let now = Date()
        dueCount = DrillStore.shared.load().filter { $0.nextReviewAt <= now }.count
        vocab.backfillFromSessions()
        lastSession = sessions.first
        topShadowPick = PracticeStats.shadowPicks(
            sessions: sessions,
            attempts: appState.shadowAttempts,
            level: appState.proficiency
        ).first

        let todayStart = Calendar.current.startOfDay(for: now)
        var todayMs = 0
        for session in sessions where (session.endedAt ?? session.startedAt) >= todayStart {
            for turn in session.turns where turn.role == .user {
                todayMs += turn.durationMs
            }
        }
        todaySpokenSeconds = todayMs / 1000
    }
}

/// A bookmarked word — minimal block; tap to swap the word for its meaning.
private struct StudyWordCard: View {
    let word: String
    let native: String
    @State private var flipped = false
    @State private var meaning: String?
    @State private var loading = false

    var body: some View {
        Button { toggle() } label: {
            Text(flipped ? (meaning ?? (loading ? "…" : "—")) : word)
                .font(flipped ? .footnote : .callout.weight(.medium))
                .foregroundStyle(flipped ? Color.secondary : Color.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .padding(.horizontal, 10)
                // tertiarySystemFill stays visible on the card's
                // secondarySystemGroupedBackground in BOTH light and dark —
                // secondarySystemBackground matched the card color in dark.
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator).opacity(0.6), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: flipped)
    }

    private func toggle() {
        flipped.toggle()
        guard flipped, meaning == nil, !loading else { return }
        loading = true
        Task {
            let entry = await WordLore.entry(for: word, native: native)
            meaning = entry?.senses.first?.meaning ?? "—"
            loading = false
        }
    }
}
