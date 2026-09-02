import AuthenticationServices
import SwiftUI

/// First screen — a swipeable, auto-playing carousel that shows the app's value
/// through previews built from the SAME components the real screens use (the
/// Futureself dialer orb, the plain transcript feed, the shadow karaoke
/// timeline, the CEFR level equalizer) — not generic icons or chat bubbles.
/// A pill Sign in with Apple is pinned below.
struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0
    @State private var autoplay = true
    /// Sign-in is the SECONDARY path (returning users). New users tap
    /// "Get started" and onboard account-free — sign-up comes later, at the
    /// voice-clone moment.
    @State private var showingSignIn = false

    init() {
        #if DEBUG
        // Screenshot helper: `-welcomePage <n>` lands directly on one slide.
        let start = UserDefaults.standard.integer(forKey: "welcomePage")
        _page = State(initialValue: start)
        _autoplay = State(initialValue: start == 0)
        // `-welcomeSignIn 1` opens on the returning-user sign-in buttons.
        if UserDefaults.standard.bool(forKey: "welcomeSignIn") {
            _showingSignIn = State(initialValue: true)
        }
        #endif
    }
    @State private var showInvite = false
    @State private var inviteCode = ""

    private struct Feature: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
    }

    /// The pitch. Every line here is `explain()`, not chrome: this is the one
    /// screen that has to be UNDERSTOOD before anything else happens, and a
    /// learner who can't read the claim can't agree with it. Computed, not a
    /// `let` — a stored static would resolve its strings once per process, and
    /// setup's first question can change the learner's language behind it.
    /// The same five beats the landing page's scrollytelling tells, in the
    /// same order — the claim, then when and what you talk about, then the
    /// BOOK the talk leaves, then what it accumulates, then the level. The
    /// carousel used to name five features instead and never showed the book,
    /// which is the one thing the learner keeps.
    private static var features: [Feature] {
        [
            // Slide one carries the whole product in two lines — the user
            // should agree with THIS before anything else: it's your voice,
            // already fluent, and you learn by talking with it.
            Feature(title: explain("Learn the language\nwith the fluent you"),
                    subtitle: explain("It's your own voice, already fluent. Say it however it comes out — every turn comes back the way you'll want to say it next time.")),
            Feature(title: explain("When you want,\nabout what you want"),
                    subtitle: explain("Today's news, a situation you're walking into this week, or nothing in particular. One tap, like placing a call.")),
            // The beat that was missing. A talk isn't spent when it ends —
            // it's bound into a book, and that's what the ribbons show.
            Feature(title: explain("Every talk becomes\nyour own textbook"),
                    subtitle: explain("The words, the expressions, the lines you actually spoke — bound into a book you flip through, shadow and keep.")),
            // Slide four is the ONE place the carousel shows a mouth doing
            // the work. The word cloud sat here first and it was the wrong
            // pick: what a talk accumulates is already visible on the book
            // (its chapters and mastery), while shadowing — the step that
            // turns material into something you can say without thinking —
            // had no picture anywhere.
            Feature(title: explain("The more you say it,\nthe more it's yours"),
                    subtitle: explain("Shadow your fluent self's lines in your own voice. Slow it down, loop the part that trips you, until it comes out without thinking.")),
            Feature(title: explain("A level measured,\nnot guessed"),
                    subtitle: explain("Your level is read from the words you actually used in a talk. No quiz, no self-rating."))
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(Self.features.enumerated()), id: \.offset) { i, f in
                    featurePage(i, f).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { _ in autoplay = false })

            pageDots
                .padding(.top, 2)
                .padding(.bottom, 6)

            signInArea
        }
        .iPadContentPadding()
        // systemBackground (not grouped) — the same ground the real
        // conversation screens use, so DialogueLine's neutral bubble fill in
        // the Talk/Watch heroes reads as a filled bubble, not empty text.
        .background(Color(.systemBackground).ignoresSafeArea())
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_500_000_000)
                if !autoplay { break }
                withAnimation(.easeInOut(duration: 0.5)) {
                    page = (page + 1) % Self.features.count
                }
            }
        }
    }

    private func featurePage(_ i: Int, _ f: Feature) -> some View {
        // One centered column per slide: a fixed-height hero area so the copy
        // never jumps between slides during autoplay, then title + subtitle.
        // maxHeight centers the whole group — no top-heavy void below.
        VStack(spacing: 28) {
            mock(i)
                .frame(height: 410)
                .frame(maxWidth: .infinity)
                // The hero can overrun the available height on small screens.
                // Rather than a hard clip, let it fade out at the very top and
                // bottom edges so the asset dissolves into the ground.
                .mask(
                    LinearGradient(
                        stops: mockFades(i)
                            ? [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.07),
                                .init(color: .black, location: 0.93),
                                .init(color: .clear, location: 1)
                              ]
                            : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            VStack(spacing: 12) {
                Text(f.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                Text(f.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Key visuals — the real components, alive

    /// Each slide is a LIVE composition of the actual app UI (WelcomeHeroes):
    /// the real `Futureself` surface taking a turn, the home's Discover
    /// section, the book on the REAL `BookmarkedPage` with its ribbons being
    /// tapped, the shadow line sweeping over `ShadowTimelinePlayer`'s
    /// scrubber, and the Progress estimate panel. No screenshots.
    @ViewBuilder
    private func mock(_ i: Int) -> some View {
        switch i {
        case 0:  FutureselfHero()  // who is on the other end, and in whose voice
        case 1:  HomeHero()        // and what there is to talk about
        case 2:  BookHero()        // the talk, bound into your own textbook
        case 3:  ShadowHero()      // said back in your voice, until it sticks
        default: LevelHero()       // measured, not guessed
        }
    }

    /// Whether the hero's top and bottom edges dissolve into the ground.
    /// Right for the heroes whose content genuinely CONTINUES past the frame
    /// (a transcript, a list, a cloud); wrong for the two that are cards —
    /// fading a card's own edge reads as a rendering fault, not a window.
    private func mockFades(_ i: Int) -> Bool { i != 2 && i != 4 }

    // MARK: - Page dots + sign in

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(Self.features.indices, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: i == page ? 20 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: page)
            }
        }
    }

    private var signInArea: some View {
        VStack(spacing: 8) {
            if showingSignIn {
                // Returning users: restore the account (and the voice clone
                // that comes with it).
                SignInWithAppleButton(
                    onRequest: { request in
                        // Capture the invite code at the sign-in moment so
                        // it's redeemed as soon as the session lands.
                        savePendingInvite()
                        auth.configure(request)
                    },
                    onCompletion: { result in auth.handle(result: result) }
                )
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(Capsule())
                .padding(.horizontal, 32)

                GoogleSignInButton(height: 52) {
                    savePendingInvite()
                    auth.signInWithGoogle()
                }
                .padding(.horizontal, 32)

                Button("New here? Get started instead") {
                    withAnimation { showingSignIn = false }
                }
                .font(.footnote)
                .foregroundStyle(.tint)
                .padding(.top, 2)
            } else {
                // The primary path: begin account-free. Sign-up comes later,
                // at the voice-clone step — after the app has earned it.
                Button {
                    appState.onboardingStarted = true
                } label: {
                    Text("Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)

                Button("Already have an account? Sign in") {
                    withAnimation { showingSignIn = true }
                }
                .font(.footnote)
                .foregroundStyle(.tint)
                .padding(.top, 2)

                inviteArea
            }

            #if DEBUG
            // Testing only: walk the onboarding flow without Apple sign-in.
            // RootView's debugSkipAuth gate reads this; never compiled into
            // release builds.
            Button("Skip sign-in (debug)") {
                UserDefaults.standard.set(true, forKey: "debugSkipAuth")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
            #endif

            if auth.isWorking { ProgressView().padding(.top, 4) }
            if let err = auth.lastError {
                Text(err).font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var inviteArea: some View {
        if showInvite {
            VStack(spacing: 6) {
                TextField("Invite code", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(.body.weight(.semibold))
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                    .padding(.horizontal, 32)
                    .onChange(of: inviteCode) { _, _ in savePendingInvite() }
                Text(explain("You'll both get \(ReferralService.bonusMinutes) minutes of talk time when you sign in."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } else {
            Button("Have an invite code?") {
                withAnimation { showInvite = true }
            }
            .font(.footnote).foregroundStyle(.tint)
            .padding(.top, 2)
        }
    }

    private func savePendingInvite() {
        let clean = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.isEmpty {
            UserDefaults.standard.removeObject(forKey: AuthService.pendingInviteKey)
        } else {
            UserDefaults.standard.set(clean, forKey: AuthService.pendingInviteKey)
        }
    }
}
