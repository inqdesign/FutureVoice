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
    /// Drives the free-talk pill's outline + orbiting highlight so the chrome
    /// matches whichever Futureself palette the surface is wearing.
    @AppStorage("futureselfTheme") private var storedTheme = FutureselfTheme.blue.rawValue
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

    enum Tab: Hashable {
        case home, watch, practice, progress
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
                    .tabItem { Label("Practice", systemImage: "books.vertical.fill") }
                    .tag(Tab.practice)

                ProgressTab()
                    .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                    .tag(Tab.progress)
            }

            // The free-talk call: fades in around the pill while the pill
            // slides down into its mic-pill pose.
            if let id = freeTalkCallId {
                ConversationView(onClose: closeFreeTalk)
                    .id(id)
                    .transition(.opacity)
                    .zIndex(1)
            }

            // Floating Free talk pill — Talk tab's ROOT only: pushed pages
            // (Activity, scenario list) drop it via talkRootVisible. It lives
            // HERE (not in ConversationHome) so it can ride above the tab bar
            // and above the call layer during the morph.
            if selection == .home && !pillHidden && appState.talkRootVisible {
                freeTalkPill
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
        }
        // Free Talk widget tap while the app is already up.
        .onChange(of: appState.pendingFreeTalk) { _, _ in consumeFreeTalk() }
        // Study widget taps land in the Practice tab — futurevoice://vocab
        // additionally pushes the vocabulary notebook once the tab is up.
        // Note the transcript word links (futurevoice://word/…) are
        // intercepted locally by ConversationDetailView's OpenURLAction and
        // never reach here.
        .onOpenURL { url in
            guard url.scheme == "futurevoice" else { return }
            // A tapped widget note carries its item as ?q=… so we open that
            // exact word/phrase; absent, we open the plain list.
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value
            switch url.host {
            case "freetalk":
                selection = .home
                appState.pendingFreeTalk = true
            case "practice":
                selection = .practice
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
    }

    // MARK: - Free talk (floating pill → call morph)

    /// Resting pose: 180×56, 12pt above the standard 49pt tab bar. Docked
    /// pose: 156×64 sitting exactly on the call screen's mic pill (whose
    /// bottom edge is 20pt padding + 16pt hint + 10pt spacing = 46pt above
    /// the safe area — keep in sync with ConversationView.bottomBar).
    private var freeTalkPill: some View {
        Button(action: startFreeTalk) {
            ZStack {
                Futureself(mode: .idle, level: 0)
                Text("Let's talk")
                    .geistPixel(18)
                    .foregroundStyle(.primary)
                    .opacity(pillDocked ? 0 : 1)
            }
            .frame(width: pillDocked ? 156 : 180, height: pillDocked ? 64 : 56)
            .clipShape(Capsule())
            // Base outline: the full edge is always defined, in the palette's
            // own color so the frame belongs to the surface it wraps.
            .overlay(Capsule().strokeBorder(pillTint.opacity(0.55), lineWidth: 1))
            // What makes the resting pill catch the eye: a light reflection
            // orbiting that outline — quiet surface, living edge, same hue.
            .overlay(ReflectiveOutline(tint: pillTint).opacity(pillDocked ? 0 : 1))
            .shadow(color: .black.opacity(pillDocked ? 0 : 0.18), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(freeTalkCallId == nil && !freeTalkClosing)
        .accessibilityLabel("Let's talk — start a call")
        .accessibilityHidden(freeTalkCallId != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, pillDocked ? 46 : 61)
    }

    /// The live Futureself palette's tint, driving the pill's outline chrome.
    private var pillTint: Color {
        (FutureselfTheme(rawValue: storedTheme) ?? .blue).tint
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
        guard freeTalkCallId == nil, !freeTalkClosing else { return }
        // One spring drives everything: the call fades in while the pill
        // slides/reshapes into the mic-pill pose. Once docked, the proxy
        // fades and the call's own (identical) pill takes over.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            freeTalkCallId = UUID()
            pillDocked = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard freeTalkCallId != nil else { return }   // closed mid-open
            withAnimation(.easeOut(duration: 0.15)) { pillHidden = true }
        }
    }

    private func closeFreeTalk() {
        guard freeTalkCallId != nil, !freeTalkClosing else { return }
        freeTalkClosing = true
        // Reverse hand-off: proxy reappears over the mic pill, then carries
        // the morph back up while the call fades away underneath.
        withAnimation(.easeIn(duration: 0.1)) { pillHidden = false }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                freeTalkCallId = nil
                pillDocked = false
            }
            // Let the call layer finish fading before the pill takes taps
            // again — a fresh call mounted now would overlap the teardown.
            try? await Task.sleep(nanoseconds: 450_000_000)
            freeTalkClosing = false
        }
    }
}

/// A specular highlight orbiting a capsule's border — an angular-gradient
/// stroke segment (tint → soft core → tint) rotating on the animation
/// timeline. The rest of the outline stays clear so the base outline keeps
/// defining the shape. `tint` follows the live Futureself palette so the
/// sheen shares the surface's hue instead of a fixed blue.
private struct ReflectiveOutline: View {
    var tint: Color

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(t.truncatingRemainder(dividingBy: 3.5) / 3.5 * 360)
            Capsule()
                .strokeBorder(
                    AngularGradient(
                        // Transparent stops are tint-at-zero-alpha, NOT
                        // .clear — interpolating toward clear (transparent
                        // BLACK) drags the fade through muddy grays that
                        // read as a dark smudge on light backgrounds. The
                        // core is a lightened tint rather than pure white so
                        // the sheen reads as a soft gleam, not a hard spark.
                        gradient: Gradient(stops: [
                            .init(color: tint.opacity(0), location: 0.00),
                            .init(color: tint.opacity(0.9), location: 0.08),
                            // Bright core = the moving gleam. White gives it
                            // the specular pop; the tinted flanks keep the
                            // whole sheen in the palette's hue.
                            .init(color: .white, location: 0.12),
                            .init(color: tint.opacity(0.9), location: 0.16),
                            .init(color: tint.opacity(0), location: 0.24),
                            .init(color: tint.opacity(0), location: 1.00),
                        ]),
                        center: .center,
                        angle: angle),
                    lineWidth: 1.6)
        }
        .allowsHitTesting(false)
    }
}
