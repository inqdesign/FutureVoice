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

    var body: some View {
        NavigationStack {
            Group {
                if sessionCount == 0 {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            todaySection
                            Divider()
                            practiceSection
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 4)
                        .padding(.bottom, 36)
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(greetingText)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItemGroup { profileButton }
            }
            .onAppear(perform: reload)
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
        }
    }

    private var profileButton: some View {
        Button { showingProfile = true } label: {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2).foregroundStyle(.secondary)
        }
        .accessibilityLabel("Profile & settings")
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
        let sessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        sessionCount = sessions.count
        snapshot = PracticeStats.snapshot()
        let now = Date()
        dueCount = DrillStore.shared.load().filter { $0.nextReviewAt <= now }.count
        vocab.backfillFromSessions()

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
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
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
