import SwiftUI

/// Talk — the speaking launcher. Today's status up top, then everything you
/// can talk about, one tap to start the call: Free talk, your scenarios
/// (with + to build one), and stories in the news (refresh in its header).
/// Watching/creating scenes lives in the Watch tab; review in Practice;
/// measurement in Progress.
struct ConversationHome: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme
    @State private var snapshot = PracticeStats.Snapshot(
        streakDays: 0, totalSessions: 0, lastScorecard: nil,
        lastSessionEndedAt: nil, lastSevenDayScores: Array(repeating: 0, count: 7),
        shadowableLineCount: 0
    )
    @State private var sessionCount = 0
    @State private var todaySpokenSeconds = 0
    /// Talks finished TODAY — the Today card counts the day, never lifetime.
    @State private var todayTalks = 0
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
        appState.scenarios.filter { $0.isTopic != true && !$0.isMeetingScene }
    }

    var body: some View {
        NavigationStack {
            // A plain ScrollView with hand-built cards (same pattern as
            // Practice/Progress), NOT a List — the discover rail needs the
            // full screen width, and a List cell would box it into the inset
            // section margins.
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
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
            // Root visibility → RootTabView shows the free-talk morph proxy
            // only while docking (the ring below is the resting CTA now).
            .onAppear { appState.talkRootVisible = true }
            .onDisappear { appState.talkRootVisible = false }
            .contentMargins(.bottom, 24, for: .scrollContent)
            // No navigation title: the hero's time-of-day question IS the
            // greeting (a large title above it doubled the greeting). The
            // inline bar carries just the chips: language · streak · account.
            .navigationBarTitleDisplayMode(.inline)
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
                // Streak chip, centered — the one Today stat that lives in the
                // header. Tapping opens the activity calendar (the old Today
                // card's tap target).
                ToolbarItem(placement: .principal) {
                    streakChip
                }
            }
            .sheet(isPresented: $showingAddLanguage) {
                AddLanguageSheet().environmentObject(appState)
            }
            .onAppear { reload(); drawRing() }
            // Ring-path calls live in RootTabView's overlay — this view never
            // disappears, so onAppear can't refresh the stats. The token
            // bumps at call close, while the backdrop still covers the home.
            // The hero line moves on to the next one here — a finished call is
            // the only moment the home is covered (by the call's backdrop), so
            // the swap is never seen happening.
            .onChange(of: appState.talkHomeReloadToken) { _, _ in
                HeroGreeting.advanceRotation()
                reload()
            }
            // The reveal after a call: the ring re-draws itself from zero as
            // the backdrop lifts, instead of popping in fully drawn.
            .onChange(of: appState.talkRingProxyActive) { _, active in
                if !active { drawRing() }
            }
            // Warm the free-talk opener pool + its audio while the user is
            // still on the launcher — the first "Let's talk" then greets
            // from cached audio instead of blocking on live calls.
            .task { await prewarmFreeTalkOpenerAudio() }
            .sheet(isPresented: $showingPaywall, onDismiss: refreshAccount) {
                PaywallView()
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
            .fullScreenCover(item: $callLaunch, onDismiss: {
                HeroGreeting.advanceRotation()
                reload()
                drawRing()
                maybePromptDeepen()
                // The call just consumed a warmed greeting — top the cache
                // back up so the NEXT call opens instantly too (no-op once
                // every pool line is cached).
                Task { await prewarmFreeTalkOpenerAudio() }
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

    // MARK: - Hero (welcome question + the goal ring / call button)

    /// The ring's 100% is the learner's OWN daily talk goal (Me → goal,
    /// default 10 min), for every tier.
    ///
    /// It briefly became "today's allowance" for Daily subscribers on
    /// 2026-08-20, while the plan was metered per day and carry-over made
    /// that number move. Monthly pools ended both premises the same evening:
    /// nothing is metered per day any more, so there is no "today's
    /// allowance" to show. Plans decide what you CAN talk; the goal is what
    /// you INTEND to talk, and only the learner sets that. What's left of the
    /// month lives on the avatar ring in the header instead.
    private var effectiveGoalMinutes: Int {
        dailyGoalMinutes
    }

    private var goalProgress: Double {
        min(1, Double(todaySpokenSeconds) / Double(max(1, effectiveGoalMinutes * 60)))
    }
    /// The arc fraction the ring actually draws — animated: it sweeps from 0
    /// up to `goalProgress` whenever the ring (re)takes the stage, instead
    /// of popping in fully drawn.
    @State private var displayedProgress: Double = 0
    private var goalProgress0to1: Double { displayedProgress }

    /// Sweep the arc from zero to today's value. Called on first appear and
    /// every time the ring is revealed again (call close, cover dismiss).
    /// The reset must NOT animate (and must land in its own transaction) or
    /// the sweep starts mid-flight — hence the explicit two-step.
    private func drawRing() {
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { displayedProgress = 0 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.easeOut(duration: 0.55)) {
                displayedProgress = goalProgress
            }
        }
    }

    /// The page's opening move: a time-of-day question in the display face,
    /// and one giant goal ring whose interior is the living Futureself
    /// surface — tapping it IS starting the call (via RootTabView's staged
    /// free-talk transition, same path as the widget deep link).
    ///
    /// The hero owns the whole first viewport: the ring sits at its center
    /// (≈ screen center at rest) and the question floats in the gap between
    /// the header and the ring; the list scrolls up from underneath.
    private var heroSection: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(welcomeQuestion)
                .geistPixel(28)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Spacer(minLength: 0)
            talkRing
                .scaleEffect(ringScale)
                .compositingGroup()
                .opacity(appState.talkRingProxyActive ? 0 : 1)
                // The scroll fade is a WASH of the page background, not an
                // alpha fade: the Metal-backed Futureself layer doesn't
                // reliably inherit ancestor opacity, but nothing escapes
                // being painted over. On the flat background the two are
                // visually identical.
                .overlay(
                    Rectangle()
                        .fill(Color(.systemGroupedBackground))
                        .opacity(1 - ringOpacity)
                        .allowsHitTesting(false)
                )
            // Breathing room under the ring (with the outer stack's 24pt,
            // ≈44pt to the list) — close enough to invite the scroll, far
            // enough not to crowd the ring.
            Color.clear.frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        // Bottom-anchored ring, hero exactly tall enough that the ring's
        // CENTER lands on the DEVICE screen's midline — solved from the
        // hero's measured global top (status bar + nav bar + padding), not
        // guessed from the scroll viewport.
        .frame(height: heroHeight)
        .background(GeometryReader { g in
            Color.clear.preference(key: HeroTopYKey.self,
                                   value: g.frame(in: .global).minY)
        })
        // Layout-transient frames report garbage minY (0 before the nav
        // inset lands, overshoot during settle) — so track the latest report
        // WITHOUT laying out from it, and adopt it once, after the first
        // layout has settled. heroHeight uses only the adopted value.
        // The continuous stream doubles as the scroll link: how far the hero
        // has moved up from rest drives the ring's shrink.
        .onPreferenceChange(HeroTopYKey.self) { y in
            latestHeroTopReport = y
            scrollOffset = max(0, heroTopY - y)
        }
        .onPreferenceChange(TalkRingFrameKey.self) { appState.talkRingFrame = $0 }
        // This task RE-RUNS on every re-appearance — including the daily
        // call's fullScreenCover lifting. A fixed one-shot sample here is
        // what sank the page after an answered call: the 250ms landed
        // mid-dismissal and adopted the pre-inset 0, pushing the hero down
        // by a nav bar until a tab switch re-measured. Adopt only a report
        // that is PLAUSIBLE (a rest top always has a status bar above it)
        // and SETTLED (unchanged across two samples), waiting as long as
        // that takes.
        .task {
            var previous = CGFloat.nan
            while !Task.isCancelled {
                let current = latestHeroTopReport
                if current > 40, abs(current - previous) < 0.5 {
                    heroTopY = current
                    return
                }
                previous = current
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    /// How far the hero has scrolled up from its at-rest pose.
    @State private var scrollOffset: CGFloat = 0
    /// Two-phase exit. Phase 1 (0–110pt): the ring only SHRINKS, fully
    /// opaque — no premature translucency while it's still mid-page. Phase 2
    /// (110–250pt): it keeps shrinking AND fades to zero, gone before it
    /// could slide under the header chips. The scale floor sits beyond the
    /// fade's end, so the shrink never visibly stops.
    private var ringScale: CGFloat {
        max(0.3, 1 - scrollOffset / 450)
    }
    private var ringOpacity: CGFloat {
        let fadeStart: CGFloat = 110
        let fadeLength: CGFloat = 140
        guard scrollOffset > fadeStart else { return 1 }
        return max(0, 1 - (scrollOffset - fadeStart) / fadeLength)
    }

    /// Where the hero starts in GLOBAL coordinates at rest (scrolled to top)
    /// — everything above it: status bar, inline nav bar, top padding.
    /// Seeded with a close guess so the first frame is near-correct; the
    /// settle-sample above then replaces it with the measured value.
    @State private var heroTopY: CGFloat = 106
    @State private var latestHeroTopReport: CGFloat = 106
    /// Ring center must sit at screenHeight/2. The ring's center is 160pt
    /// above the hero's bottom (140 half-ring + 20 tail), so:
    /// heroTop + heroHeight − 160 = screenHeight/2.
    private var heroHeight: CGFloat {
        max(380, UIScreen.main.bounds.height / 2 + 160 - heroTopY)
    }

    /// See `HeroGreeting`. Cached in state because the hero re-evaluates on
    /// every scroll frame (scrollOffset is @State) — but the FIRST frame
    /// computes the real line itself (`HeroGreeting.live()` reads the stores
    /// directly) rather than painting a placeholder that `onAppear` then
    /// corrects. That correction was visible: a short clock line swapping to
    /// something else a frame later.
    @State private var heroLine = ""

    private var welcomeQuestion: String {
        heroLine.isEmpty ? HeroGreeting.text(for: HeroGreeting.live()) : heroLine
    }

    private func refreshHeroLine() {
        heroLine = HeroGreeting.text(for: HeroGreeting.live())
    }

    /// A fully-closed goal ring (progress from 12 o'clock) around the
    /// Futureself surface. virtualHeight pins the surface's pixel grid to
    /// the call pill's cell size, so the eventual morph onto the call screen
    /// never changes pixel scale.
    private var talkRing: some View {
        ZStack {
            // Whisper of a track: primary at 1.5% — all but invisible. The
            // full circle is merely SENSED against the background on a good
            // display, never seen as a shape of its own.
            Circle()
                .stroke(Color.primary.opacity(0.015), lineWidth: 20)
            // Accent, even at goal — the ring follows the app's palette
            // (green-at-goal clashed with non-green Futureself themes).
            // ONE gradient stroke: the tail FADES IN from near-transparent
            // at 12 o'clock to full accent by ~55% of the arc — comet-style
            // depth, no black overlay. (Angles are PRE-rotation; 0° lands on
            // the tail once the -90° below spins the layer.)
            // Both arc layers render UNCONDITIONALLY (hidden via opacity at
            // zero) — an `if` around them re-INSERTS the view when progress
            // moves off zero, and inserted views fade in at final length
            // instead of animating their trim: the draw-on sweep only works
            // on a view that already exists.
            //
            // The tail ALWAYS fades — but only over the REAR of the arc: at
            // most 90° of circle, never past the arc's halfway point. The
            // head half stays solid accent, so a short arc reads as a crisp
            // little comet instead of a smeared translucent pill. (Zero
            // progress also needs the hide below: a near-empty trim under
            // the angular gradient renders as a half-cut dot at 12.)
            //
            // At zero the ring is just its faint track. A start-line dot at
            // 12 marked the start for a while and was removed (2026-08-31): on
            // the home screen it read as a stray mark, not a marker.
            let fadeEnd = min(0.5, 0.25 / max(goalProgress0to1, 0.001))
            Circle()
                .trim(from: 0, to: goalProgress0to1)
                .stroke(
                    AngularGradient(
                        stops: [
                            .init(color: Color.accentColor.opacity(0.15), location: 0),
                            .init(color: Color.accentColor, location: fadeEnd),
                        ],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * goalProgress0to1)),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(goalProgress0to1 > 0.005 ? 1 : 0)
            // At full progress the circle closes and the stroke loses its
            // caps — the seam at 12 turns into a flat butt joint. Re-draw
            // the last sliver with a round cap (NO shadow): its head pokes
            // just past 12 over the faded tail, and its trailing edge is the
            // same full accent as the base arc, so no seam shows.
            Circle()
                .trim(from: max(goalProgress0to1 - 0.02, 0), to: goalProgress0to1)
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(goalProgress0to1 > 0.97 ? 1 : 0)

            Button {
                // The gate lives in RootTabView's `startFreeTalk`, which is
                // where BOTH paths into a free talk meet (this ring and the
                // widget's deep link). Checking here as well would ask the
                // server the same question twice for one tap.
                appState.pendingFreeTalk = true
            } label: {
                ZStack {
                    Futureself(mode: .idle, level: 0, virtualHeight: 64)
                    // Wash the surface toward the page background so the
                    // circle sits IN the page instead of glowing against it
                    // (the shader's own base runs brighter than grouped bg).
                    Color(.systemGroupedBackground).opacity(0.35)
                    // Uniform inner shadow — a blurred inner ring, masked to
                    // the circle so the vignette hugs the whole edge evenly
                    // (a one-sided shadow here reads as a lighting mistake).
                    // Light mode gets a MUCH gentler pass: on the airy light
                    // surface the dark-mode strength reads as a hole.
                    // Tight spread: a narrow stroke + small blur keeps the
                    // vignette hugging the rim instead of flooding inward.
                    Circle()
                        .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.45 : 0.15),
                                      lineWidth: 10)
                        .blur(radius: 6)
                        .mask(Circle())
                    VStack(spacing: 6) {
                        Text("Let's talk")
                            .geistPixel(20)
                            .foregroundStyle(.primary)
                        Text(goalHeadline)
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                // 260 = the 280 frame minus the 20 pt stroke: the surface
                // meets the ring's inner edge with no gap.
                .frame(width: 260, height: 260)
                // The proxy morph needs the surface's live pose (global) —
                // reported from HERE so it tracks layout, not guesses.
                .background(GeometryReader { g in
                    Color.clear.preference(key: TalkRingFrameKey.self,
                                           value: g.frame(in: .global))
                })
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Let's talk — start a call. \(todaySpokenSeconds / 60) of \(effectiveGoalMinutes) minutes today.")
        }
        .frame(width: 280, height: 280)
    }

    /// Header chip — the one Today stat up here, and the ONLY way into the
    /// activity calendar.
    ///
    /// It used to hide itself entirely until a streak existed, to avoid
    /// printing "0 day streak" at someone. That was right about the number and
    /// wrong about the button: the chip is also the navigation, so a learner
    /// with no streak — exactly the person most likely to be looking for
    /// where they stand — had no route to the page at all.
    ///
    /// So the button is always there and only its CONTENTS change. No zero is
    /// ever shown; with no streak it simply says what it opens.
    private var streakChip: some View {
        Button {
            showingActivity = true
        } label: {
            HStack(spacing: 4) {
                if snapshot.streakDays > 0 {
                    Image(systemName: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("\(snapshot.streakDays) day streak")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Activity")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(.secondarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(snapshot.streakDays > 0
            ? "\(snapshot.streakDays) day streak. Opens activity calendar."
            : "Opens activity calendar.")
    }

    private var goalHeadline: String {
        let secs = todaySpokenSeconds
        let mins = secs / 60
        if goalProgress >= 1 { return chrome("Goal reached · \(mins) min") }
        if secs == 0 { return chrome("Talk \(effectiveGoalMinutes) min today") }
        // A talk that hasn't reached a minute still happened — the ring has
        // already moved for it, so the line must not still be asking for the
        // first word (see PracticeStats.talkTimeText).
        if mins == 0 { return chrome("\(secs) sec of \(effectiveGoalMinutes) min today") }
        return chrome("\(mins) of \(effectiveGoalMinutes) min today")
    }


    private func linkedPersonaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }

    /// Warm the opener pool and every pool greeting's TTS (see
    /// FreeTalkOpeners.warmFirstCall) — so "Let's talk" always opens on
    /// cached audio, whatever the rotation position. (Warming only the next
    /// line left every fresh line in the rotation slow the first time it
    /// came up.)
    private func prewarmFreeTalkOpenerAudio() async {
        await FreeTalkOpeners.shared.warmFirstCall(
            language: appState.targetLanguage,
            personaName: appState.persona?.displayName,
            proficiency: appState.proficiency,
            voiceId: appState.voiceCloneId,
            firstMeeting: appState.persona?.metAt == nil)
    }

    // MARK: - Actions (tap = start the call)

    /// Every card on this page is a launcher, so every card asks the same
    /// question the call button asks: can this account pay for what the tap
    /// starts? Answered here rather than inside the call, which is why the
    /// paywall opens INSTEAD of the call screen and not on top of one.
    private func runScenario(_ s: Scenario) {
        BillingGate.start(orShow: $showingPaywall) {
            appState.markScenarioUsed(id: s.id)
            callLaunch = CallLaunch(topic: s.displayTitle, blurb: s.promptBlurb, isNews: false,
                                    origin: .scenario, scenarioId: s.id)
        }
    }

    private func runNews(_ t: SuggestedTopic) {
        BillingGate.start(orShow: $showingPaywall) {
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
    /// (admin sees the real cycling balance too), account things live
    /// together up here. Each half keeps its own tap: balance → billing,
    /// avatar → profile.
    private var headerControl: some View {
        // No number up here — a text chip pushed the streak leftward and put
        // a meter on the home screen. What's left of the month is a RING
        // around the avatar instead: full pool = empty ring, filling as
        // minutes go. The exact figures live one tap away in Me.
        Button { showingProfile = true } label: {
            // Ring INSIDE the 30 pt slot (avatar shrinks to make room) — the
            // header buttons sit in glass capsules, and a ring drawn outside
            // the frame gets clipped into broken arcs by the capsule edge.
            ZStack {
                // Ring for an account with a pool it could plausibly reach the
                // end of. Since the allowances went monthly that includes
                // Light subscribers, not just free accounts — a month-long
                // pool is exactly the thing worth a quiet gauge, and this is
                // the quiet form: an arc, no digits, figures one tap away.
                //
                // NOT on Plus. 1,800 minutes is an hour every single day, so
                // the arc sits near empty all month for almost everyone on it
                // — a gauge that never moves is decoration, and putting one on
                // the home screen of the tier that bought its way out of
                // counting is the taximeter this design exists to avoid. They
                // still have the exact figures in Me, where someone who wants
                // them goes looking.
                if let account, !account.isPlusPlan,
                   account.monthlyCapSeconds != nil || !account.isEntitled {
                    // strokeBorder / inset keep the 3 pt stroke INSIDE the
                    // 30 pt frame — a centered stroke overhangs it by half a
                    // linewidth and the container clips the arc's caps flat.
                    // Tertiary, not systemFill: the track is a groove for the
                    // arc to sit in, and at full systemFill it read as a second
                    // ring competing with the accent one.
                    Circle()
                        .strokeBorder(Color(.tertiarySystemFill), lineWidth: 3)
                    // Usage gauge: the arc grows clockwise from 12 o'clock
                    // as minutes are SPENT — fresh tank = empty ring.
                    Circle()
                        .inset(by: 1.5)
                        .trim(from: 0, to: account.talkTimeUsedFraction)
                        .stroke(account.isLowBalance ? Color.orange : Color.accentColor,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    // 20 pt inside a 24 pt hole: the ring's inner edge would
                    // otherwise sit flush on the avatar, which reads as the
                    // arc being drawn ON the picture rather than around it.
                    ProfileAvatar(initials: appState.persona?.displayName ?? "", size: 20)
                } else {
                    ProfileAvatar(initials: appState.persona?.displayName ?? "", size: 30)
                }
            }
            .frame(width: 30, height: 30)
            .padding(1)
        }
        .buttonStyle(.plain)
        // The label announces the gauge only when the gauge is drawn. On Plus
        // there is no ring, so reading out a balance would describe something
        // that isn't on screen.
        .accessibilityLabel(account.flatMap { a -> String? in
            a.isPlusPlan ? nil
                         : "Profile & settings, \(a.balanceLabel) of \(a.tankMinutes) minutes of talk left"
        } ?? "Profile & settings")
    }

    private func refreshAccount() {
        #if DEBUG
        // Screenshot captures run signed-out — inject an account so the ring
        // renders for design review. `home-light` injects a Light subscriber
        // mid-period, which is the only way to see the allowance ring at an
        // interesting value; `home-plus` is the tier that draws NO ring, and
        // exists so that absence can be reviewed rather than assumed.
        if let capture = UserDefaults.standard.string(forKey: "capture") {
            account = capture.hasPrefix("home-light")
                ? AccountStatus(email: nil, secondsBalance: 0,
                                planId: "light_monthly", subscriptionStatus: "active",
                                secondsUsedPeriod: 3300, monthlyCapSeconds: 9000,
                                scenesUsedPeriod: 12, monthlyScenesCap: 60,
                                fullTankSeconds: 9000)
                : capture.hasPrefix("home-plus")
                ? AccountStatus(email: nil, secondsBalance: 0,
                                planId: "plus_monthly", subscriptionStatus: "active",
                                secondsUsedPeriod: 3300, monthlyCapSeconds: 108_000,
                                scenesUsedPeriod: 12, monthlyScenesCap: 120,
                                fullTankSeconds: 108_000)
                : AccountStatus(email: nil, secondsBalance: 2000,
                                planId: nil, subscriptionStatus: "inactive")
            applyAccountToRing()
            return
        }
        #endif
        // Through the gate, not around it: the ring and the launch decision
        // are the same snapshot, so what the ring shows is what the next tap
        // will be judged against.
        Task {
            account = await BillingGate.shared.snapshot(force: true)
            applyAccountToRing()
        }
    }

    /// The account lands AFTER the first draw. The hero ring no longer
    /// depends on it (the goal is local), so this only exists to keep the
    /// morph proxy's label in step when the snapshot changes anything.
    private func applyAccountToRing() {
        appState.talkRingHeadline = goalHeadline
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
        // The first call now asks these out loud and writes down the answers
        // (`UserPersona.learnedNotes`). Once it has, a form asking the same
        // three questions reads as the app not having listened.
        guard p.learnedNotes.isEmpty else { return false }
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
        // One shared definition of "talked today" — see
        // PracticeStats.todayTalkSeconds. Summing only the learner's turns
        // here made the ring disagree with the billing page on the same day.
        todaySpokenSeconds = PracticeStats.todayTalkSeconds()
        todayTalks = sessions.filter { ($0.endedAt ?? $0.startedAt) >= todayStart }.count
        // Keep the proxy's label copy in sync (see AppState.talkRingHeadline).
        appState.talkRingHeadline = goalHeadline
        // Reads everything above, so it goes last.
        refreshHeroLine()
        backfillTalkTime()
    }

    /// The local meter log only starts filling on the build that introduced
    /// it, so a day metered by an earlier build (or on another device) leaves
    /// the ring at zero while the receipt shows the minutes. Reconcile with
    /// the server's ledger, then re-draw only if the number actually moved —
    /// an unconditional sweep would replay the animation on every appear.
    private func backfillTalkTime() {
        Task { @MainActor in
            await TalkTimeLog.syncFromServer()
            let synced = PracticeStats.todayTalkSeconds()
            guard synced != todaySpokenSeconds else { return }
            todaySpokenSeconds = synced
            appState.talkRingHeadline = goalHeadline
            refreshHeroLine()
            drawRing()
        }
    }
}

/// The Talk hero's at-rest global top edge (see ConversationHome.heroTopY).
private struct HeroTopYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The hero ring surface's live global frame (→ AppState.talkRingFrame).
private struct TalkRingFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
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
        appState.scenarios.filter { $0.isTopic != true && !$0.isMeetingScene }
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


