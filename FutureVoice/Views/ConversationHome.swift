import SwiftUI

/// Home — designed like a phone's front door, not a dashboard. The hero is a
/// breathing VoiceGlow call pill (same shader as the Talk screen's mic) that
/// starts a free talk; everything else — today's goal, follow-ups, words — sits
/// below it in light cards. One glow, one accent, no competing chrome.
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
    /// "Up next" feed: today's most useful follow-ups after talking.
    @State private var topShadowPick: PracticeStats.ShadowPick?
    @State private var lastSession: Session?
    @State private var shadowingPick: PracticeStats.ShadowPick?
    /// Server-side account/billing snapshot — drives the credit chip. Credits
    /// live WITH the plan (not as a bare stat) so tapping goes to the
    /// subscription page. nil until the first fetch lands.
    @State private var account: AccountStatus?
    @State private var showingPaywall = false
    /// Tapped notebook word → opens the full detail sheet (not an inline flip,
    /// which was a dead end — you saw the meaning but couldn't act on it).
    @State private var wordSheet: WordRef?

    struct WordRef: Identifiable { let value: String; var id: String { value } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    if sessionCount == 0 {
                        firstRunHint
                    } else {
                        card { todaySection }
                        if hasReviewRows {
                            card { upNextSection }
                        }
                        card { wordsSection }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(greetingText)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
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
            .fullScreenCover(item: $callLaunch, onDismiss: reload) { launch in
                ConversationView(initialTopic: launch.topic, initialBlurb: launch.blurb,
                                 initialIsNews: launch.isNews)
                    .environmentObject(appState)
            }
            .sheet(item: $shadowingPick, onDismiss: reload) { pick in
                ShadowDrillView(turn: pick.turn, targetLanguage: appState.targetLanguage)
                    .environmentObject(appState)
            }
            .sheet(item: $wordSheet, onDismiss: reload) { ref in
                WordSheet(initialWord: ref.value, words: Array(vocab.studying))
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

    // MARK: - Hero (the call button)

    /// The one big action on this screen: a full-width glow pill that starts a
    /// free talk. Same shader + hairline treatment as the Talk screen's mic
    /// pill, scaled up, so Home and the call read as one surface. The topic
    /// picker rides underneath as the quiet alternative.
    private var hero: some View {
        VStack(spacing: 10) {
            Button {
                callLaunch = CallLaunch()
            } label: {
                ZStack {
                    VoiceGlow(mode: .idle, level: 0)
                    HStack(spacing: 10) {
                        Image(systemName: "phone.fill")
                            .font(.headline)
                        Text("Talk to your fluent self")
                            .font(.headline)
                    }
                    .foregroundStyle(.primary)
                }
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start a free talk")

            Button {
                launchTopic = ""; launchBlurb = ""; launchIsNews = false; showingTopics = true
            } label: {
                Label("Choose a topic", systemImage: "square.grid.2x2")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    // MARK: - Today

    /// Compact daily strip: goal bar + minutes on one line, streak/talks row
    /// as the door to the calendar. The start-a-talk buttons moved to the
    /// hero, so this card is purely "how today is going".
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                creditChip
            }

            HStack(spacing: 12) {
                progressBar
                Text("\(todaySpokenSeconds / 60) of \(dailyGoalMinutes) min")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                    .layoutPriority(1)
            }

            NavigationLink {
                ActivityView()
            } label: {
                HStack(spacing: 16) {
                    stat(icon: "flame.fill", text: "\(snapshot.streakDays) streak",
                         tint: snapshot.streakDays > 0 ? .orange : .secondary)
                    stat(icon: "bubble.left.and.bubble.right.fill",
                         text: "\(appState.learnerProfile.totalSessions) talks", tint: .secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Credit balance as a compact chip on the Today line. Opens the right
    /// billing surface: settings (which manages the plan) for paid/admin —
    /// NEVER the trial paywall — and the upgrade pitch for free users.
    @ViewBuilder
    private var creditChip: some View {
        if let account {
            let tint: Color = account.isLowBalance ? .orange : .accentColor
            Button { openBilling(account) } label: {
                HStack(spacing: 4) {
                    Image(systemName: account.unlimited ? "infinity" : "bolt.fill")
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

    // MARK: - Up next

    private var hasReviewRows: Bool {
        dueCount > 0 || topShadowPick != nil || lastSession != nil
    }

    /// Actionable follow-ups after talking: due cards, a shadow line, the last
    /// conversation. Words live in their own card now — this one is only the
    /// "do this next" list, so it disappears entirely when there's nothing due.
    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Up next")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 6)

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
                    // Consistent with the rows above: fixed title, the topic
                    // in the subtitle (not the long topic as the title).
                    upNextRow(icon: "text.bubble",
                              title: "Last conversation",
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

    /// Subtitle = the conversation's topic + when, matching the other rows'
    /// "detail under a fixed title" pattern.
    private func lastSessionSubtitle(_ session: Session) -> String {
        let when = Self.relativeFormatter.localizedString(
            for: session.endedAt ?? session.startedAt, relativeTo: Date())
        return "\(when) · \(session.displayTitle)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    // MARK: - Words

    /// Bookmarked words as a one-line horizontal shelf — lighter than the old
    /// grid, and it never grows the page: overflow scrolls sideways under the
    /// card's rounded edges.
    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Words").font(.title3.weight(.semibold))
                Spacer()
                NavigationLink { VocabularyView() } label: {
                    HStack(spacing: 3) {
                        Text("See all")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline).foregroundStyle(.tint)
                }
            }
            if vocab.studying.isEmpty {
                Text("Bookmark words while you study and they'll show up here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(vocab.studying.prefix(12)), id: \.self) { word in
                            Button { wordSheet = WordRef(value: word) } label: {
                                StudyWordChip(word: word)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // Cancel the card's inset so chips scroll edge-to-edge of
                    // the card instead of clipping mid-air at the padding line.
                    .padding(.horizontal, 18)
                }
                .padding(.horizontal, -18)
            }
        }
    }

    // MARK: - First run

    /// Below the hero before the first conversation — explains what will fill
    /// this screen. The call to action IS the hero pill, so no second button.
    private var firstRunHint: some View {
        card {
            Label("Your fluent self is ready", systemImage: "waveform")
                .font(.subheadline.weight(.semibold))
            Text("Tap the call button above to have your first conversation. Review cards, lines to shadow, and saved words will all land here afterwards.")
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

/// A bookmarked word chip — tapping OPENS the full word sheet (definition,
/// pronunciation, examples, mark-known). Capsule shape to match the shelf's
/// horizontal flow.
private struct StudyWordChip: View {
    let word: String

    var body: some View {
        Text(word)
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            // tertiarySystemFill stays visible on the card's
            // secondarySystemGroupedBackground in BOTH light and dark.
            .background(Capsule().fill(Color(.tertiarySystemFill)))
            .overlay(Capsule().stroke(Color(.separator).opacity(0.6), lineWidth: 0.5))
            .contentShape(Capsule())
    }
}
