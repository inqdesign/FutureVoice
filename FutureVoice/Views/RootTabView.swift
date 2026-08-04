import SwiftUI

/// Native four-tab structure around the do → create → review → measure loop:
/// Talk (the speaking launcher — status + everything talkable), Watch (the
/// creation surface — pick who, describe the situation, watch the scene),
/// Practice (the review home: books + dictionaries), and Progress (measured
/// CEFR + skills + activity).
struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: Tab = .home
    /// Beta intro shows ONCE, right after onboarding — in place of a paywall
    /// (no subscription during the beta). Explains the free quota + invites.
    @AppStorage("futurevoice.betaWelcomeSeen") private var betaWelcomeSeen = false
    @State private var showingBetaWelcome = false
    /// Non-nil while the free-talk call is up. A fresh UUID per call gives
    /// ConversationView a clean view identity each time (same reason
    /// ConversationHome presents by item, not Bool).
    @State private var freeTalkCallId: UUID?
    /// The floating pill is a PROXY that RootTabView animates between two
    /// explicit poses — resting above the tab bar, and docked exactly on the
    /// call screen's mic-pill frame. (Cross-hierarchy matchedGeometryEffect
    /// broke here: the counterpart inside the inserted NavigationStack
    /// measured at the origin, so the pill flew to the top-left.)
    @State private var pillDocked = false
    /// Proxy faded out after docking — the call's own mic pill (same
    /// Futureself surface, same frame) has taken over.
    @State private var pillHidden = false
    /// True while the closing morph + fade-out is still playing. Blocks a
    /// re-tap from mounting a second ConversationView on top of the one
    /// that's tearing down (overlapping sessions).
    @State private var freeTalkClosing = false
    /// Opaque backdrop behind the call, raised fast on open so the home never
    /// shows through the call's opacity fade, dropped on close.
    @State private var callBackdropShown = false

    enum Tab: Hashable {
        case home, watch, practice, progress
    }

    /// Analytics label for a tab (see `screen_viewed`).
    private static func screenName(_ tab: Tab) -> String {
        switch tab {
        case .home:     return "talk"
        case .watch:    return "watch"
        case .practice: return "practice"
        case .progress: return "progress"
        }
    }

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                ConversationHome()
                    .tabItem { Label("Talk", systemImage: "waveform") }
                    .tag(Tab.home)

                WatchTab()
                    .tabItem { Label("Watch", systemImage: "play.circle.fill") }
                    .tag(Tab.watch)

                PracticeTab()
                    .tabItem { Label("Practice", systemImage: "book.fill") }
                    .tag(Tab.practice)

                ProgressTab()
                    .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                    .tag(Tab.progress)
            }

            // Opaque cover that snaps in ahead of the call's fade so the home
            // (and tab bar) don't bleed through the half-transparent call
            // screen mid-transition — the call content then resolves cleanly on
            // this backdrop instead of double-exposing over the feed behind it.
            Color(.systemBackground)
                .ignoresSafeArea()
                .opacity(callBackdropShown ? 1 : 0)
                .allowsHitTesting(false)
                .zIndex(0.5)

            // The free-talk call: fades in around the pill while the pill
            // slides down into its mic-pill pose.
            if let id = freeTalkCallId {
                ConversationView(onClose: closeFreeTalk)
                    .id(id)
                    .transition(.opacity)
                    .zIndex(1)
            }

            // Free-talk morph proxy — the hero ring's Futureself detaches
            // and flies down into the call's mic-pill pose (and back on
            // close). Rect-driven by hand: the proxy starts on the ring's
            // reported global frame and springs to the docked pill frame —
            // cross-hierarchy matchedGeometryEffect broke here (see the
            // original pill morph notes). It lives HERE (not in
            // ConversationHome) so it can ride above the call layer.
            if selection == .home && !pillHidden && appState.talkRingProxyActive {
                freeTalkProxy
                    .zIndex(2)
            }
        }
        .onAppear {
            if !betaWelcomeSeen { showingBetaWelcome = true }
            // Populate the home-screen widgets on first entry. The scenePhase
            // refresh only fires on background↔active transitions, so a cold
            // launch that goes straight to foreground wouldn't otherwise
            // publish a fresh snapshot.
            StudyWidgetRefresher.refresh()
            consumeFreeTalk()   // cold launch from the Free Talk widget
            Analytics.capture("screen_viewed", ["screen": Self.screenName(selection)])
        }
        // Feature usage: which tab the user is on.
        .onChange(of: selection) { _, tab in
            Analytics.capture("screen_viewed", ["screen": Self.screenName(tab)])
        }
        // Free Talk widget tap while the app is already up.
        .onChange(of: appState.pendingFreeTalk) { _, _ in consumeFreeTalk() }
        // In-app jumps to Practice (Home's Practice row) stage a route instead
        // of opening a URL — see ConversationHome.practiceProgressRow. Bring
        // the tab along; PracticeTab consumes the route once it's up.
        .onChange(of: appState.pendingPracticeRoute) { _, route in
            if route != nil { selection = .practice }
        }
        // Study widget taps land in the Practice tab — futurevoice://vocab
        // additionally pushes the vocabulary notebook once the tab is up.
        // Note the transcript word links (futurevoice://word/…) are
        // intercepted locally by ConversationDetailView's OpenURLAction and
        // never reach here.
        .onOpenURL { url in
            guard url.scheme == "futurevoice" else { return }
            Analytics.capture("widget_opened", ["kind": url.host ?? "unknown"])
            // A tapped widget note carries its item as ?q=… so we open that
            // exact word/phrase; absent, we open the plain list.
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value
            switch url.host {
            case "freetalk":
                selection = .home
                appState.pendingFreeTalk = true
            case "talk":
                // Streak widget: open the Talk tab so the user does an activity.
                selection = .home
            case "practice":
                selection = .practice
                appState.pendingPracticeRoute = .studying   // land on the Studying shelf, not wherever it was left
            case "book":
                // Continue widget: open a specific book's detail page.
                let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let type = comps?.queryItems?.first(where: { $0.name == "type" })?.value ?? "talk"
                if let idString = comps?.queryItems?.first(where: { $0.name == "id" })?.value,
                   let id = UUID(uuidString: idString) {
                    selection = .practice
                    appState.pendingPracticeRoute = .book(kind: type, id: id)
                } else {
                    selection = .practice
                    appState.pendingPracticeRoute = .studying
                }
            case "vocab":
                selection = .practice
                appState.pendingPracticeRoute = .vocabulary(word: q)
                appState.focusWord = q          // opens the card even if the page is already up
            case "expressions":
                selection = .practice
                appState.pendingPracticeRoute = .expressions(phrase: q)
                appState.focusPhrase = q
            default:
                break
            }
        }
        .fullScreenCover(isPresented: $showingBetaWelcome, onDismiss: { betaWelcomeSeen = true }) {
            BetaWelcomeView()
        }
        .sheet(item: $appState.levelUpAnnouncement) { announcement in
            LevelUpSheet(announcement: announcement)
        }
    }

    // MARK: - Free talk (ring → call morph)

    /// Start pose: the hero ring's Futureself circle, exactly where the
    /// home drew it. Docked pose: 156×64 sitting exactly on the call
    /// screen's mic pill (whose bottom edge is 20pt padding + 16pt hint +
    /// 10pt spacing = 46pt above the safe area — keep in sync with
    /// ConversationView.bottomBar). One surface, frame+corner animated
    /// between the two.
    private var freeTalkProxy: some View {
        GeometryReader { geo in
            // The ring frame is GLOBAL; convert into this container.
            let container = geo.frame(in: .global)
            let dock = CGRect(x: geo.size.width / 2 - 78,
                              y: geo.size.height - 46 - 64,
                              width: 156, height: 64)
            let ringGlobal = appState.talkRingFrame
            let start = ringGlobal == .zero
                ? dock   // no measured ring (cold widget launch) — no fly-in
                : ringGlobal.offsetBy(dx: -container.minX, dy: -container.minY)
            let rect = pillDocked ? dock : start
            let corner: CGFloat = pillDocked ? 32 : rect.height / 2
            ZStack {
                Futureself(mode: .idle, level: 0, virtualHeight: 64)
                // At the ring pose the surface wears the ring's exact
                // dressing — background wash + uniform inner shadow — and
                // sheds it while docking (the call pill is bare). Without
                // this the hand-off visibly swapped surface treatments.
                Color(.systemGroupedBackground).opacity(0.35)
                    .opacity(pillDocked ? 0 : 1)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.45 : 0.15),
                                  lineWidth: 10)
                    .blur(radius: 6)
                    .mask(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .opacity(pillDocked ? 0 : 1)
                // The label clears quickly while docked and nothing replaces
                // it: the call's own pill is glyph-free while on call (the
                // living surface IS the state). At the ring pose the label
                // is the EXACT two-line stack the home ring renders, so the
                // hand-off never shifts "Let's talk" vertically.
                VStack(spacing: 6) {
                    Text("Let's talk")
                        .geistPixel(20)
                        .foregroundStyle(.primary)
                    Text(appState.talkRingHeadline)
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .opacity(pillDocked ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: pillDocked)
            }
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
            .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Honour a pending Free Talk request from the widget deep link — only on
    /// the Talk tab's root, and never on top of a live call.
    private func consumeFreeTalk() {
        guard appState.pendingFreeTalk else { return }
        appState.pendingFreeTalk = false
        guard freeTalkCallId == nil, !freeTalkClosing else { return }
        startFreeTalk()
    }

    private func startFreeTalk() {
        guard freeTalkCallId == nil, !freeTalkClosing, !pillDocked else { return }
        // Stage 0 — the proxy mounts ON the ring's pose (the home ring hides
        // itself the same tick), and the backdrop starts covering the home.
        appState.talkRingProxyActive = true
        withAnimation(.easeOut(duration: 0.22)) { callBackdropShown = true }
        Task { @MainActor in
            // Stage 1 — one frame later (so the proxy exists at its start
            // pose and the dock change actually ANIMATES), fly it down.
            // Mounting ConversationView in this same animation used to drop
            // the spring's frames, so the spring animates nothing heavier
            // than a Color and the proxy.
            try? await Task.sleep(nanoseconds: 30_000_000)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                pillDocked = true
            }
            // Stage 2 — mount the call only after the morph has visually
            // settled, fading it in over the now-static backdrop; its mount
            // cost can't stutter an animation that has already finished.
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard pillDocked, !freeTalkClosing else { return }   // closed mid-open
            withAnimation(.easeOut(duration: 0.2)) { freeTalkCallId = UUID() }
            // Stage 3 — proxy hands off to the call's own identical mic pill.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard freeTalkCallId != nil else { return }
            withAnimation(.easeOut(duration: 0.15)) { pillHidden = true }
        }
    }

    private func closeFreeTalk() {
        guard freeTalkCallId != nil, !freeTalkClosing else { return }
        freeTalkClosing = true
        // Refresh the home's stats NOW, behind the backdrop — the minutes
        // line (here on the proxy and on the ring underneath) is already
        // up to date by the time anything is revealed.
        appState.talkHomeReloadToken = UUID()
        // Reverse hand-off: proxy reappears over the mic pill, then carries
        // the morph back up to the ring while the call fades underneath.
        withAnimation(.easeIn(duration: 0.1)) { pillHidden = false }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            // The call dissolves on its own SHORT fade while the proxy rises
            // on its spring — but the BACKDROP stays up: the morph plays on
            // a clean stage, not over the reappearing home UI.
            withAnimation(.easeOut(duration: 0.2)) {
                freeTalkCallId = nil
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                pillDocked = false
            }
            // Only after the spring has landed on the ring does the home
            // fade back in around it — transition first, THEN the UI.
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(.easeOut(duration: 0.25)) { callBackdropShown = false }
            try? await Task.sleep(nanoseconds: 250_000_000)
            // Backdrop cleared with the proxy still ON the ring pose — the
            // swap to the real ring underneath is pixel-identical.
            appState.talkRingProxyActive = false
            freeTalkClosing = false
            // The call consumed a warmed greeting — top the cache back up so
            // the NEXT call opens instantly too (no-op once every pool line
            // is cached).
            await FreeTalkOpeners.shared.warmAudio(
                language: appState.targetLanguage,
                personaName: appState.persona?.displayName,
                voiceId: appState.voiceCloneId)
        }
    }
}
