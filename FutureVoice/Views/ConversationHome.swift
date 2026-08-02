import SwiftUI

/// Talk — the speaking launcher. Today's status up top, then everything you
/// can talk about, one tap to start the call: Free talk, your scenarios
/// (with + to build one), and stories in the news (refresh in its header).
/// Watching/creating scenes lives in the Watch tab; review in Practice;
/// measurement in Progress.
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
    /// Talks finished TODAY — the Today card counts the day, never lifetime.
    @State private var todayTalks = 0
    /// Today's next actions: the book to pick back up, plus the whole-library
    /// mastery aggregate behind the Practice row (async — see reload()).
    @State private var continueBook: Scenario?
    @State private var overallMastered = 0
    @State private var overallTotal = 0
    @State private var openBook: Scenario?
    @AppStorage("futurevoice.dailyGoalMinutes") private var dailyGoalMinutes = 10
    /// Presenting the call via an item (not a Bool) gives every presentation
    /// a fresh view identity — with `isPresented`, ConversationView's
    /// `State(initialValue:)` kept the FIRST evaluation's empty topic, so the
    /// first topic pick always fell through to free talk.
    @State private var callLaunch: CallLaunch?
    @State private var showingProfile = false
    @State private var showingBuilder = false
    @State private var showingAddLanguage = false
    /// The post-first-talk "tell me more about you" bottom sheet. Auto-shown
    /// ONCE (flag below) right after the first conversation ends; afterwards
    /// the deepenRow re-opens it while the narrative fields stay empty.
    @State private var showingDeepen = false
    @AppStorage("futurevoice.personaDeepenPrompted") private var deepenPrompted = false
    /// Today card → activity calendar (Button-driven so the row shows no
    /// disclosure chevron).
    @State private var showingActivity = false
    /// Discover rail's "All scenarios" card → the full collection page.
    @State private var showingAllScenarios = false

    private struct CallLaunch: Identifiable {
        let id = UUID()
        var topic = ""
        var blurb = ""
        var isNews = false
        var origin: SessionOrigin = .free
        var scenarioId: UUID? = nil
        /// Pool-grounded facts for a news talk — seeds `newsFacts`.
        var newsFacts: [String] = []
    }
    /// Server-side account/billing snapshot — drives the credit chip. Credits
    /// live WITH the plan (not as a bare stat) so tapping goes to the
    /// subscription page. nil until the first fetch lands.
    @State private var account: AccountStatus?
    @State private var showingPaywall = false

    /// News-born topic books live in `appState.scenarios` too — they belong
    /// to the news section's taxonomy, not the scenario list.
    private var scenarios: [Scenario] {
        appState.scenarios.filter { $0.isTopic != true }
    }

    var body: some View {
        NavigationStack {
            // A plain ScrollView with hand-built cards (same pattern as
            // Practice/Progress), NOT a List — the discover rail needs the
            // full screen width, and a List cell would box it into the inset
            // section margins.
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    todayCard
                        .padding(.horizontal, 20)
                    if sessionCount == 0 {
                        firstRunCard
                            .padding(.horizontal, 20)
                    } else if personaNeedsDepth {
                        deepenRow
                            .padding(.horizontal, 20)
                    }
                    DiscoverSection(
                        onPickNews: { runNews($0) },
                        onPickScenario: { runScenario($0) },
                        onAllScenarios: { showingAllScenarios = true },
                        onBuildScenario: { showingBuilder = true })
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            // Root visibility → RootTabView keeps the floating Free-talk pill
            // off pushed pages (Activity, the scenarios list, …).
            .onAppear { appState.talkRootVisible = true }
            .onDisappear { appState.talkRootVisible = false }
            // Room for RootTabView's floating Free talk pill — the last rows
            // can still scroll up past it.
            .contentMargins(.bottom, 96, for: .scrollContent)
            .navigationTitle(greetingText)
            // .large (its own row), NOT .inlineLarge — the toolbar items
            // share the inline row and truncate "Good afternoon".
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Language chip on the leading edge — the one-tap switch
                // between enrolled languages and the discoverable entry point
                // for adding one (docs/multi-language-plan.md).
                ToolbarItem(placement: .topBarLeading) {
                    languageSwitcher
                }
                // ONE header control: credits + avatar as a single unit —
                // account things live together up here, out of the Today card.
                ToolbarItem(placement: .topBarTrailing) {
                    headerControl
                }
            }
            .sheet(isPresented: $showingAddLanguage) {
                AddLanguageSheet().environmentObject(appState)
            }
            .onAppear(perform: reload)
            // Warm the free-talk opener pool while the user is still on the
            // launcher — the first "Let's talk" then greets from a canned
            // line instead of blocking on a live Gemini call.
            .task {
                await FreeTalkOpeners.shared.warmUp(
                    language: appState.targetLanguage,
                    personaName: appState.persona?.displayName,
                    proficiency: appState.proficiency
                )
                await prewarmFreeTalkOpenerAudio()
            }
            .sheet(isPresented: $showingPaywall, onDismiss: refreshAccount) {
                // Only pitch the trial to someone who still has free credits;
                // a spent balance means they've already used the free tier.
                PaywallView(offerTrial: (account?.creditBalance ?? 0) > 0)
            }
            .sheet(isPresented: $showingProfile) {
                MeTab().environmentObject(appState).environmentObject(auth)
            }
            .sheet(isPresented: $showingDeepen) {
                PersonaDeepenSheet().environmentObject(appState)
            }
            .sheet(isPresented: $showingBuilder) {
                ScenarioComposerSheet(person: nil, ctaTitle: "Talk", ctaIcon: "mic.fill") { newScenario in
                    appState.saveScenario(newScenario)
                    // Straight into the conversation with the fresh scenario.
                    runScenario(newScenario)
                }
                .environmentObject(appState)
            }
            .navigationDestination(isPresented: $showingActivity) {
                ActivityView()
            }
            .navigationDestination(isPresented: $showingAllScenarios) {
                TalkScenariosListView(onPick: runScenario)
                    .environmentObject(appState)
            }
            .navigationDestination(item: $openBook) { book in
                ScenarioDetailView(scenarioId: book.id)
                    .environmentObject(appState)
            }
            .fullScreenCover(item: $callLaunch, onDismiss: {
                reload()
                maybePromptDeepen()
            }) { launch in
                ConversationView(initialTopic: launch.topic, initialBlurb: launch.blurb,
                                 initialIsNews: launch.isNews,
                                 initialOrigin: launch.origin,
                                 initialScenarioId: launch.scenarioId,
                                 initialNewsFacts: launch.newsFacts)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Today (activity status)

    private var goalProgress: Double {
        min(1, Double(todaySpokenSeconds) / Double(max(1, dailyGoalMinutes * 60)))
    }

    /// ONE hierarchy: the goal ring anchors the card, the headline tells
    /// today's story in a sentence, and next actions are full-width rows
    /// (never truncating chips). Status block taps into Activity. No "Today"
    /// header — the ring and headline say it themselves.
    private var todayCard: some View {
        VStack(spacing: 0) {
            Button {
                showingActivity = true
            } label: {
                HStack(spacing: 14) {
                    goalRing
                    VStack(alignment: .leading, spacing: 3) {
                        Text(goalHeadline)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        // Plain Image+Text, NOT Label — List quietly drops a
                        // Label's title in this slot.
                        HStack(spacing: 4) {
                            if snapshot.streakDays > 0 {
                                Image(systemName: "flame.fill")
                                    .foregroundStyle(.orange)
                                Text("\(snapshot.streakDays)-day streak")
                                    .foregroundStyle(.secondary)
                                if todayTalks > 0 {
                                    Text("·").foregroundStyle(.tertiary).padding(.horizontal, 1)
                                }
                            }
                            if todayTalks > 0 {
                                Text(todayTalks == 1 ? "1 talk today" : "\(todayTalks) talks today")
                                    .foregroundStyle(.secondary)
                            }
                            if snapshot.streakDays == 0 && todayTalks == 0 {
                                Text("No talk yet today").foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(todaySpokenSeconds / 60) of \(dailyGoalMinutes) minutes today, \(todayTalks) talks today, \(snapshot.streakDays) day streak. Opens activity calendar.")

            // Next actions — one full-width row each, so nothing truncates
            // into garbage. The whole-library mastery bar nudges toward
            // Practice (SRS review itself now lives there, on Studying);
            // the book you're mid-way through opens directly.
            if overallTotal > 0 {
                CardDivider()
                practiceProgressRow
            }
            if let book = continueBook {
                CardDivider()
                todayActionRow(icon: "book",
                               title: "Continue studying",
                               subtitle: book.environment) {
                    openBook = book
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    /// Fitness-style minutes ring — filled arc = progress toward the daily
    /// goal, the number inside = minutes spoken (✓ once the goal is hit).
    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(goalProgress, 0.001))
                .stroke(goalProgress >= 1 ? Color.green : Color.accentColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if goalProgress >= 1 {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)
            } else {
                Text("\(todaySpokenSeconds / 60)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
        }
        .frame(width: 46, height: 46)
    }

    private var goalHeadline: String {
        let mins = todaySpokenSeconds / 60
        if goalProgress >= 1 { return "Goal reached · \(mins) min" }
        if mins == 0 { return "Talk \(dailyGoalMinutes) min today" }
        return "\(mins) of \(dailyGoalMinutes) min today"
    }

    /// A Today action row. With `subtitle`, the title becomes the ACTION
    /// label and the subtitle the target on a second line (so a long book
    /// name wraps instead of truncating into "…").
    /// "연습하라" — how much of ALL the material your talks/watches generated
    /// is mastered, as a bar. Tap hops to Practice (Studying), where the books
    /// and the SRS review live.
    private var practiceProgressRow: some View {
        Button {
            // Stage the route; RootTabView switches the tab. This used to be
            // `openURL("futurevoice://practice")` — moving between two tabs of
            // the SAME app by asking the operating system to open a URL. The
            // OS is free to hand that scheme to any app that claims it, and
            // with a second build of Future Voice side-loaded it did exactly
            // that: tapping Practice launched the other app. Deep links are
            // for arriving from outside; in-app navigation stays in-app.
            appState.pendingPracticeRoute = .studying
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.body)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Practice")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(overallMastered) of \(overallTotal) mastered")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(overallMastered), total: Double(max(overallTotal, 1)))
                        .tint(overallMastered == overallTotal ? .green : .accentColor)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func todayActionRow(icon: String, title: String, subtitle: String? = nil,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    private func linkedPersonaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }

    /// When a book was last actually studied — most recent mastery event,
    /// else last use, else creation (same policy as Practice's Studying tab).
    private func bookLastStudied(_ s: Scenario) -> Date {
        let mastery = s.curriculum.flatMap {
            ($0.words + $0.expressions + $0.shadowLines).compactMap(\.masteredAt).max()
        }
        return mastery ?? s.lastUsedAt ?? s.createdAt
    }

    /// Synthesize the NEXT free-talk greeting while the user is still looking
    /// at the launcher, so tapping "Let's talk" opens on cached audio instead
    /// of waiting out an ElevenLabs round trip — the wait that made the start
    /// of a call feel slow. Deliberately does NOT touch the rotation: the
    /// greeting still differs every call (that variety is the point), only its
    /// audio is ready early.
    ///
    /// Costs nothing extra in the normal case — it synthesizes exactly the
    /// line the call was about to synthesize anyway, under the same
    /// (text, voiceId) cache key and the same model, and no-ops once cached.
    /// The one wasteful case is a user who opens Talk and never calls; that is
    /// bounded at one line per rotation position.
    private func prewarmFreeTalkOpenerAudio() async {
        guard let voiceId = appState.voiceCloneId,
              let line = FreeTalkOpeners.shared.peek(
                  language: appState.targetLanguage,
                  personaName: appState.persona?.displayName),
              // `allowLineage: false` mirrors the live call's lookup — warming
              // a line the call would still consider a miss is pointless.
              PhraseAudioStore.shared.data(text: line, voiceId: voiceId,
                                           allowLineage: false) == nil,
              let audio = try? await ElevenLabsClient.shared.synthesize(
                  voiceId: voiceId, text: line,
                  modelId: ElevenLabsClient.conversationModelId,
                  purpose: "turn")
        else { return }
        PhraseAudioStore.shared.save(audio, text: line, voiceId: voiceId)
    }

    // MARK: - Actions (tap = start the call)

    private func runScenario(_ s: Scenario) {
        appState.markScenarioUsed(id: s.id)
        callLaunch = CallLaunch(topic: s.displayTitle, blurb: s.promptBlurb, isNews: false,
                                origin: .scenario, scenarioId: s.id)
    }

    private func runNews(_ t: SuggestedTopic) {
        // The blurb is factual context from the search results — hand it
        // to the avatar so the conversation sticks to what happened.
        callLaunch = CallLaunch(
            topic: t.title,
            blurb: "Recent news to discuss (facts from coverage): \(t.blurb)",
            isNews: true,
            origin: .news,
            newsFacts: t.facts ?? []
        )
    }

    // MARK: - Chrome

    /// The practice-language chip. Tapping lists enrolled languages (switch
    /// is one tap, whole app follows) plus "Add a language". Always visible
    /// even with a single language — it's how multi-language is discovered.
    private var languageSwitcher: some View {
        Menu {
            ForEach(appState.enrolledLanguages, id: \.self) { code in
                Button {
                    appState.switchLanguage(to: code)
                } label: {
                    if code == appState.targetLanguage {
                        Label(LanguageCatalog.endonym(code), systemImage: "checkmark")
                    } else {
                        Text(LanguageCatalog.endonym(code))
                    }
                }
            }
            Divider()
            Button {
                showingAddLanguage = true
            } label: {
                Label("Add a language", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.caption2.weight(.bold))
                Text(appState.targetLanguage.uppercased())
                    .font(.footnote.weight(.semibold))
            }
        }
        .accessibilityLabel("Practice language: \(LanguageCatalog.englishName(appState.targetLanguage))")
    }

    /// Profile + credits fused into one header unit — credits ALWAYS visible
    /// (∞ on unlimited), account things live together up here. Each half
    /// keeps its own tap: balance → billing, avatar → profile.
    private var headerControl: some View {
        HStack(spacing: 8) {
            if let account {
                let tint: Color = !account.unlimited && account.isLowBalance
                    ? .orange : .accentColor
                Button { openBilling(account) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2.weight(.bold))
                        Text(account.unlimited ? "∞" : account.balanceLabel)
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(account.unlimited
                    ? "Unlimited credits"
                    : "\(account.balanceLabel) credits, \(account.planLabel) plan")
            }
            Button { showingProfile = true } label: {
                ProfileAvatar(initials: appState.persona?.displayName ?? "", size: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile & settings")
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

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hello"
        }
    }

    // MARK: - First run

    /// Under Today before the first conversation — explains the lists below.
    private var firstRunCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your fluent self is ready", systemImage: "waveform")
                .font(.subheadline.weight(.semibold))
            Text(explain("Tap Let's talk — or a scenario or story below — to have your first conversation. Everything you meet becomes review material in Practice."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Persona deepening (post-first-talk)

    /// True while the persona's narrative fields are still blank — the ones
    /// onboarding deliberately skips and `PersonaDeepenSheet` collects.
    private var personaNeedsDepth: Bool {
        guard let p = appState.persona else { return false }
        return [p.occupation, p.household, p.freeNotes]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Auto-present the deepen sheet exactly once, right after the first talk
    /// ends — the moment the "richer persona = more real talks" pitch has
    /// lived evidence behind it. The delay lets the call's fullScreenCover
    /// dismissal settle before a new sheet comes up.
    private func maybePromptDeepen() {
        guard !deepenPrompted, sessionCount > 0, personaNeedsDepth else { return }
        deepenPrompted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            showingDeepen = true
        }
    }

    /// Persistent re-entry under Today once the auto-prompt has passed —
    /// visible only while the narrative fields stay empty.
    private var deepenRow: some View {
        Button {
            showingDeepen = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tell me more about you")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(explain("Talks get more real when I know your life."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func reload() {
        refreshAccount()   // talks spend credits — keep the chip honest
        let sessions = SessionStore.shared.load()
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        sessionCount = sessions.count
        snapshot = PracticeStats.snapshot()
        VocabStore.shared.backfillFromSessions()

        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var todayMs = 0
        var todayCount = 0
        for session in sessions where (session.endedAt ?? session.startedAt) >= todayStart {
            todayCount += 1
            for turn in session.turns where turn.role == .user {
                todayMs += turn.durationMs
            }
        }
        todaySpokenSeconds = todayMs / 1000
        todayTalks = todayCount

        // Today's next actions — the most recently studied unfinished book
        // (progress started, not yet mastered).
        continueBook = appState.scenarios
            .filter { !$0.isArchived && !$0.isMastered && ($0.curriculum?.masteredCount ?? 0) > 0 }
            .max { bookLastStudied($0) < bookLastStudied($1) }

        // Whole-library mastery for the Practice row — same aggregate as
        // Practice's Studying header. Deferred: TalkCurriculum.build's
        // pickup-word extraction is too heavy for first paint.
        Task { @MainActor in
            var mastered = 0, total = 0
            for s in sessions {
                let snap = TalkCurriculum.build(session: s,
                                                proficiency: appState.proficiency,
                                                shadowAttempts: appState.shadowAttempts)
                mastered += snap.masteredCount
                total += snap.totalCount
            }
            for sc in appState.scenarios {
                if let c = sc.curriculum {
                    mastered += c.masteredCount
                    total += c.totalCount
                }
            }
            overallMastered = mastered
            overallTotal = total
        }
    }
}

/// One talkable scenario — role icon for a face, one-line title, partner
/// caption. Notes stay off the row; the call itself carries the context.
struct TalkScenarioRow: View {
    let scenario: Scenario
    let personaName: String?

    private var partnerLabel: String? {
        if let personaName { return personaName }
        let r = scenario.role.trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? nil : r
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 36, height: 36)
                if let name = personaName {
                    Text(Books.initials(name))
                        .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                } else {
                    Image(systemName: Books.roleIcon(for: scenario.role))
                        .font(.subheadline).foregroundStyle(.tint)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                // Watch-minted situations are full sentences — show them
                // whole instead of truncating into identical-looking rows.
                Text(scenario.environment)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let partnerLabel {
                    Text("with \(partnerLabel)")
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
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// The scenario collection, recency-first — pushed from the Talk home's
/// minimal Scenarios row. This list is the app's memory of every situation
/// the user has set up: built in the builder, or minted by watching a scene
/// in Watch. Tapping starts the call; + builds a new one right here.
struct TalkScenariosListView: View {
    @EnvironmentObject private var appState: AppState
    let onPick: (Scenario) -> Void
    @State private var showingBuilder = false

    private var scenarios: [Scenario] {
        appState.scenarios.filter { $0.isTopic != true }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    var body: some View {
        List {
            Section {
                ForEach(scenarios) { s in
                    Button {
                        onPick(s)
                    } label: {
                        TalkScenarioRow(scenario: s, personaName: personaName(s))
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            appState.deleteScenario(id: s.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text(explain("Every situation you build here or watch in Watch is saved as a scenario — tap one to talk it out again. Swipe to delete."))
            }
        }
        .navigationTitle("Scenarios")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingBuilder = true } label: {
                    Label("Build new", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingBuilder) {
            ScenarioComposerSheet(person: nil, ctaTitle: "Talk", ctaIcon: "mic.fill") { newScenario in
                appState.saveScenario(newScenario)
                // Straight into the conversation with the fresh scenario.
                onPick(newScenario)
            }
            .environmentObject(appState)
        }
    }

    private func personaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }
}

/// Manage your voice-cloned personas — the "who" that can play any scenario
/// or topic partner. Reached from Home's header (person.2).
struct PeopleSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onNew: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onNew) {
                        Label("New person", systemImage: "plus.circle.fill")
                            .font(.body.weight(.medium))
                    }
                }
                if !appState.counterparts.isEmpty {
                    Section("Your people") {
                        ForEach(appState.counterparts) { c in
                            NavigationLink {
                                CounterpartDetailView(counterpart: c).environmentObject(appState)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                                        Text(Books.initials(c.name))
                                            .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(c.name).font(.body)
                                        Text(c.relationship).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            for i in idx { appState.deleteCounterpart(id: appState.counterparts[i].id) }
                        }
                    }
                } else {
                    Section {
                        Text(explain("Add someone from your real life — their cloned voice can act out any scenario you build."))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

