import SwiftUI

/// Talk tab home — a launchpad + a light dashboard. Instead of a bare history
/// list, it surfaces what the past conversations add up to: momentum, the last
/// talk's read-out, the recurring things to work on, and a one-tap way to start
/// another conversation. The immersive talk seat (`ConversationView`) opens as a
/// full-screen call, mirroring Watch.
struct ConversationHome: View {
    @EnvironmentObject private var appState: AppState

    @State private var snapshot = PracticeStats.Snapshot(
        streakDays: 0, totalSessions: 0, lastScorecard: nil,
        lastSessionEndedAt: nil, lastSevenDayScores: Array(repeating: 0, count: 7),
        shadowableLineCount: 0
    )
    @State private var lastSession: Session?
    @State private var sessionCount = 0
    @State private var showingCall = false
    @State private var showingTopics = false
    @State private var launchTopic = ""
    @State private var launchBlurb = ""

    var body: some View {
        NavigationStack {
            Group {
                if sessionCount == 0 {
                    emptyState
                } else {
                    GeometryReader { geo in
                        ScrollView {
                            VStack(spacing: 16) {
                                momentumStrip
                                if let s = lastSession { lastTalkCard(s) }
                                focusCard
                                weeklyTrendCard
                                historyLink
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                            // Pin content to the viewport width so a stray wide
                            // child can't make the page scroll sideways.
                            .frame(width: geo.size.width)
                        }
                    }
                }
            }
            .navigationTitle("Talk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        launchTopic = ""; launchBlurb = ""; showingTopics = true
                    } label: {
                        Label("Topic", systemImage: "list.bullet.rectangle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { startBar }
            .onAppear(perform: reload)
            .sheet(isPresented: $showingTopics, onDismiss: launchIfTopicPicked) {
                ScenariosListSheet(topic: $launchTopic, topicBlurb: $launchBlurb)
                    .environmentObject(appState)
            }
            .fullScreenCover(isPresented: $showingCall, onDismiss: reload) {
                ConversationView(initialTopic: launchTopic, initialBlurb: launchBlurb)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Momentum

    private var momentumStrip: some View {
        HStack(spacing: 12) {
            statTile(icon: "flame.fill",
                     value: snapshot.streakDays > 0 ? "\(snapshot.streakDays)" : "0",
                     label: "day streak",
                     tint: snapshot.streakDays > 0 ? .orange : .secondary)
            statTile(icon: "mic.fill",
                     value: speakingMinutes,
                     label: "spoken",
                     tint: .accentColor)
            statTile(icon: "bubble.left.and.bubble.right.fill",
                     value: "\(appState.learnerProfile.totalSessions)",
                     label: appState.learnerProfile.totalSessions == 1 ? "talk" : "talks",
                     tint: .accentColor)
        }
    }

    private func statTile(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(tint)
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private var speakingMinutes: String {
        let m = appState.learnerProfile.totalSpeakingSeconds / 60
        return m >= 1 ? "\(m)m" : "\(appState.learnerProfile.totalSpeakingSeconds)s"
    }

    // MARK: - Last talk

    private func lastTalkCard(_ s: Session) -> some View {
        NavigationLink {
            ConversationDetailView(session: s)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Your last talk").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let sc = s.summary?.scorecard {
                        scoreBadge(overallScore(sc))
                    }
                }
                Text(s.displayTitle).font(.headline).foregroundStyle(.primary).lineLimit(1)
                if let note = s.summary?.scorecard?.topLine ?? s.summary?.overallNote, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Tap to review what it taught you")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    private func scoreBadge(_ score: Int) -> some View {
        Text("\(score)")
            .font(.subheadline.weight(.bold)).monospacedDigit()
            .foregroundStyle(scoreColor(score))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(scoreColor(score).opacity(0.15)))
    }

    // MARK: - Focus (analysis across conversations)

    @ViewBuilder
    private var focusCard: some View {
        let mistakes = Array(appState.learnerProfile.recurringMistakes.prefix(3))
        let weak = appState.learnerProfile.weakVocabAreas
        if !mistakes.isEmpty || !weak.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What to work on").font(.headline)
                ForEach(mistakes) { p in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.footnote).foregroundStyle(.orange).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(p.mistake).strikethrough().foregroundStyle(.secondary)
                                Text(p.correction).foregroundStyle(.primary)
                            }
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            if p.frequency > 1 {
                                Text("came up \(p.frequency)×").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                if !weak.isEmpty {
                    Text("Weak spots").font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(weak, id: \.self) { w in
                            Text(w)
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
    }

    // MARK: - Weekly trend

    private var weeklyTrendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week").font(.headline)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(snapshot.lastSevenDayScores.enumerated()), id: \.offset) { _, score in
                    let h = max(0.06, score / 100.0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(score > 0 ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56 * h + 4)
                }
            }
            .frame(height: 60, alignment: .bottom)
            Text("Daily conversation score").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private var historyLink: some View {
        NavigationLink {
            ConversationsListView()
                .navigationTitle("All conversations")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack {
                Text("All conversations").font(.subheadline)
                Spacer()
                Text("\(sessionCount)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Start bar

    private var startBar: some View {
        Button {
            launchTopic = ""; launchBlurb = ""; showingCall = true
        } label: {
            Label("Start talking", systemImage: "phone.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Talk with your fluent self", systemImage: "phone.bubble")
        } description: {
            Text("Pick a scenario or just free-talk. Every conversation gets analyzed — score, recurring slips, review cards — and shows up here.")
        } actions: {
            Button("Start talking") { launchTopic = ""; launchBlurb = ""; showingCall = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Logic

    private func launchIfTopicPicked() {
        if !launchTopic.isEmpty { showingCall = true }
    }

    private func overallScore(_ sc: SessionScorecard) -> Int {
        var scores = [sc.vocabulary.score, sc.grammar.score, sc.expressiveness.score, sc.fluency.score]
        if let p = sc.pronunciation { scores.append(p.score) }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .accentColor
        default: return .orange
        }
    }

    private func reload() {
        let sessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        sessionCount = sessions.count
        lastSession = sessions.first
        snapshot = PracticeStats.snapshot()
    }
}
