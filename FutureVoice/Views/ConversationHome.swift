import SwiftUI

/// Home — a dialer, not a dashboard. Three zones, one focal point:
/// the greeting up top, a goal-ringed glow call orb dead center (the ONLY
/// progress element on the screen), and the week's mission shelf anchored at
/// the bottom. Everything that was a bar/row/chip collage (goal bar, week
/// columns, streak row) collapsed into the ring + one quiet caption line.
struct ConversationHome: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService

    @State private var snapshot = PracticeStats.Snapshot(
        streakDays: 0, totalSessions: 0, lastScorecard: nil,
        lastSessionEndedAt: nil, lastSevenDayScores: Array(repeating: 0, count: 7),
        shadowableLineCount: 0
    )
    @State private var sessionCount = 0
    @State private var todaySpokenSeconds = 0
    /// This week's mission counts: words being studied, expressions collected,
    /// lines picked to shadow. Drive the three compact buttons on the shelf.
    @State private var missionWords = 0
    @State private var missionExpressions = 0
    @State private var missionShadow = 0
    @AppStorage("futurevoice.dailyGoalMinutes") private var dailyGoalMinutes = 10
    /// Presenting the call via an item (not a Bool) gives every presentation
    /// a fresh view identity — with `isPresented`, ConversationView's
    /// `State(initialValue:)` kept the FIRST evaluation's empty topic, so the
    /// first topic pick always fell through to free talk.
    @State private var callLaunch: CallLaunch?
    @State private var showingTopics = false
    @State private var showingProfile = false
    @State private var launchTopic = ""
    @State private var launchBlurb = ""
    @State private var launchIsNews = false

    private struct CallLaunch: Identifiable {
        let id = UUID()
        var topic = ""
        var blurb = ""
        var isNews = false
    }
    /// Server-side account/billing snapshot — drives the credit chip. Credits
    /// live WITH the plan (not as a bare stat) so tapping goes to the
    /// subscription page. nil until the first fetch lands.
    @State private var account: AccountStatus?
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 12)

                callOrb

                Text("Talk to your fluent self")
                    .font(.headline)
                    .padding(.top, 20)

                Button {
                    launchTopic = ""; launchBlurb = ""; launchIsNews = false; showingTopics = true
                } label: {
                    Label("Choose a topic", systemImage: "square.grid.2x2")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .padding(.top, 14)

                statsLine
                    .padding(.top, 22)

                Spacer(minLength: 12)

                if sessionCount == 0 {
                    firstRunHint
                } else if missionWords + missionExpressions + missionShadow > 0 {
                    card { missionSection }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(greetingText)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItemGroup {
                    creditChip
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
            .fullScreenCover(item: $callLaunch, onDismiss: reload) { launch in
                ConversationView(initialTopic: launch.topic, initialBlurb: launch.blurb,
                                 initialIsNews: launch.isNews)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Call orb (the centerpiece)

    private var goalProgress: Double {
        min(1, Double(todaySpokenSeconds) / Double(max(1, dailyGoalMinutes * 60)))
    }

    /// The one big action, dialer-style: a breathing VoiceGlow circle (same
    /// shader as the Talk screen's mic pill) wrapped in the daily-goal ring.
    /// Goal progress lives HERE and nowhere else — no second bar to decode.
    private var callOrb: some View {
        Button {
            callLaunch = CallLaunch()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: goalProgress)
                    .stroke(goalProgress >= 1 ? Color.green : Color.accentColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                ZStack {
                    VoiceGlow(mode: .idle, level: 0)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
                .padding(13)
            }
            .frame(width: 208, height: 208)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start a free talk")
        .accessibilityValue("\(todaySpokenSeconds / 60) of \(dailyGoalMinutes) minutes spoken today")
    }

    /// Today in ONE quiet line — minutes toward goal, streak, total talks —
    /// doubling as the door to the activity calendar.
    private var statsLine: some View {
        NavigationLink {
            ActivityView()
        } label: {
            HStack(spacing: 6) {
                Text("\(todaySpokenSeconds / 60) of \(dailyGoalMinutes) min")
                    .monospacedDigit()
                dot
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(snapshot.streakDays > 0 ? Color.orange : Color.secondary)
                Text("\(snapshot.streakDays)")
                    .monospacedDigit()
                dot
                Text("\(appState.learnerProfile.totalSessions) talks")
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(todaySpokenSeconds / 60) of \(dailyGoalMinutes) minutes today, \(snapshot.streakDays) day streak, \(appState.learnerProfile.totalSessions) talks. Opens activity calendar.")
    }

    private var dot: some View {
        Circle().fill(Color(.tertiaryLabel)).frame(width: 2.5, height: 2.5)
    }

    // MARK: - Chrome

    private var profileButton: some View {
        Button { showingProfile = true } label: {
            ProfileAvatar(initials: appState.persona?.displayName ?? "", size: 30)
        }
        .accessibilityLabel("Profile & settings")
    }

    /// Credit balance in the toolbar — SHOWN only when the number can run out
    /// (free/paid balances); an unlimited account gets no chip at all, credits
    /// aren't a daily concern there. Tapping opens the right billing surface:
    /// settings for subscribers (never the trial paywall), the upgrade pitch
    /// for free users.
    @ViewBuilder
    private var creditChip: some View {
        if let account, !account.unlimited {
            let tint: Color = account.isLowBalance ? .orange : .accentColor
            Button { openBilling(account) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2.weight(.bold))
                    Text(account.balanceLabel)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(account.balanceLabel) credits, \(account.planLabel) plan")
        }
    }

    private func openBilling(_ a: AccountStatus) {
        // Admin/subscribers manage in settings; only free users see the
        // upgrade pitch. An unlimited account must never hit the trial paywall.
        if a.unlimited || a.isEntitled { showingProfile = true }
        else { showingPaywall = true }
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

    // MARK: - This week's mission

    /// Three compact count buttons — words to learn, expressions collected,
    /// lines to shadow — framed as "master these this week". Each opens the
    /// full list; a zero item hides so the row never nags about nothing.
    private var missionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Master this week")
                .font(.title3.weight(.semibold))

            HStack(spacing: 10) {
                if missionWords > 0 {
                    missionButton(count: missionWords, title: "Words",
                                  icon: "text.book.closed.fill") {
                        VocabularyView()
                    }
                }
                if missionExpressions > 0 {
                    missionButton(count: missionExpressions, title: "Expressions",
                                  icon: "quote.bubble.fill") {
                        ExpressionsView()
                            .navigationTitle("Expressions")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                if missionShadow > 0 {
                    missionButton(count: missionShadow, title: "Shadow",
                                  icon: "waveform.badge.mic") {
                        ShadowBrowserView()
                            .navigationTitle("Shadow")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
    }

    private func missionButton<D: View>(count: Int, title: String, icon: String,
                                        @ViewBuilder destination: () -> D) -> some View {
        NavigationLink { destination() } label: {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text("\(count)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - First run

    /// Bottom shelf before the first conversation — explains what will fill
    /// this screen. The call to action IS the orb, so no second button.
    private var firstRunHint: some View {
        card {
            Label("Your fluent self is ready", systemImage: "waveform")
                .font(.subheadline.weight(.semibold))
            Text("Tap the call button to have your first conversation. Words, expressions, and lines to shadow will land here afterwards.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Logic

    private func launchIfTopicPicked() {
        guard !launchTopic.isEmpty else { return }
        callLaunch = CallLaunch(topic: launchTopic, blurb: launchBlurb, isNews: launchIsNews)
    }

    private func reload() {
        refreshAccount()   // talks spend credits — keep the chip honest
        let sessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        sessionCount = sessions.count
        snapshot = PracticeStats.snapshot()
        let now = Date()
        VocabStore.shared.backfillFromSessions()
        missionWords = VocabStore.shared.studying.count
        missionExpressions = VocabStore.shared.expressionEntries().count
        // Weekly shadow mission = a bounded set (10), not "every line ever" —
        // masterable, in the same spirit as a Leitner day queue.
        missionShadow = PracticeStats.shadowPicks(
            sessions: sessions,
            attempts: appState.shadowAttempts,
            level: appState.proficiency,
            limit: 10
        ).count

        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        var todayMs = 0
        for session in sessions where (session.endedAt ?? session.startedAt) >= todayStart {
            for turn in session.turns where turn.role == .user {
                todayMs += turn.durationMs
            }
        }
        todaySpokenSeconds = todayMs / 1000
    }
}
