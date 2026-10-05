import AuthenticationServices
import SwiftUI

/// First screen — a short film, not a tutorial (2026-10-05, founder: "strip
/// the tutorial, a quiet gradient and words that animate in"). The fluent
/// self tells the learner's own story back to them — the words that stay
/// in their head, the years of apps — then introduces itself and says what
/// the two of them will do together: talk, get every line back the natural
/// way, keep a book of their own mistakes, review and shadow daily, rehearse
/// speeches. It ends on what the app does, as a short list, and the buttons.
///
/// The captions are the whole film for now; a voice-over is planned
/// (`StoryBeat.hold`). The narrator is the FLUENT SELF, so every line is
/// informal wherever the language marks it (반말, タメ口, du/tu/tú) — the
/// closing list is the app speaking and uses the app's register.
///
/// The old five-slide carousel (WelcomeHeroes.swift) is no longer shown.
struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Index into `beats`; `beats.count` is the closing frame.
    @State private var beat = 0
    @State private var autoplay = true
    /// Bumped on every manual step so the autoplay sleep restarts its clock
    /// instead of firing a beat early.
    @State private var tick = 0
    /// Sign-in is the SECONDARY path (returning users). New users tap
    /// "Get started" and onboard account-free — sign-up comes later, at the
    /// voice-clone moment.
    @State private var showingSignIn = false
    /// The orb has opened into the Get started button.
    @State private var doorOpen = false
    /// The closing frame was reached by Skip or Sign in, not by watching.
    @State private var skipped = false
    @State private var showInvite = false
    @State private var inviteCode = ""

    init() {
        #if DEBUG
        // Screenshot helper: `-welcomePage <n>` holds on one beat
        // (`n == beats.count` is the closing frame).
        let start = UserDefaults.standard.integer(forKey: "welcomePage")
        _beat = State(initialValue: start)
        _autoplay = State(initialValue: start == 0)
        // `-welcomeSignIn 1` opens on the returning-user sign-in buttons.
        if UserDefaults.standard.bool(forKey: "welcomeSignIn") {
            _showingSignIn = State(initialValue: true)
            _beat = State(initialValue: Self.beats.count)
        }
        #endif
    }

    // MARK: - The script

    struct StoryBeat {
        /// The caption, one localized key; `\n` is where the line breathes.
        let text: String
        /// What the app does, said quietly under the line.
        var glimpse: (symbol: String, label: String)? = nil
        /// Seconds on screen. nil = derived from the caption's length; set
        /// it from the clip's duration once the voice-over is recorded.
        var hold: Double? = nil
    }

    /// Computed, not a `let`: a stored static would resolve its strings once
    /// per process, and setup can change the app language behind it.
    static var beats: [StoryBeat] {
        [
            StoryBeat(text: explain("So much you want to say,\nall of it still in your head.")),
            StoryBeat(text: explain("Why is it so hard\njust to start talking...")),
            StoryBeat(text: explain("School, classes, YouTube, books, apps...\nYou tried so hard... didn't you?")),
            StoryBeat(text: explain("Hi. It's me.\nYou, already fluent.")),
            StoryBeat(text: explain("I'll call you.\nLet's talk five minutes a day."),
                      glimpse: ("phone.fill", explain("Talk"))),
            StoryBeat(text: explain("Stumble, get it wrong, that's fine.\nI'll show you how it goes."),
                      glimpse: ("text.viewfinder", explain("Say it again"))),
            StoryBeat(text: explain("Everything we talk about\nbecomes your own textbook."),
                      glimpse: ("book.closed", explain("Your textbook"))),
            StoryBeat(text: explain("What you keep getting wrong comes back every day,\nand you say it until it sticks."),
                      glimpse: ("arrow.triangle.2.circlepath", explain("Review"))),
            StoryBeat(text: explain("Practice while you watch yourself,\nuntil you feel sure, until it feels natural."),
                      glimpse: ("music.mic", explain("Speech"))),
        ]
    }

    /// The closing frame's line — the film's last word, said once, with the
    /// chips gathered under it.
    static var closingLine: String { explain("Until the day you become me,\nlet's do this together.") }

    /// The closing frame's chips: what the app does, by the names the app
    /// itself uses for them.
    static var closingChips: [(symbol: String, label: String)] {
        [
            ("phone.fill", explain("Talk")),
            ("book.closed", explain("Your textbook")),
            ("arrow.triangle.2.circlepath", explain("Review")),
            ("music.mic", explain("Speech")),
            ("text.viewfinder", explain("Say it again")),
        ]
    }

    private var isClosing: Bool { beat >= Self.beats.count }

    // MARK: - Body

    var body: some View {
        ZStack {
            StoryBackdrop(still: reduceMotion)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                story
            }
            .iPadContentPadding()
        }
        // The film is always on its cream ground, whatever the phone's
        // appearance — the buttons below follow it.
        .environment(\.colorScheme, .light)
        // …but the status bar sits on the near-black top, so it asks the
        // window for light content while this screen is up.
        .preferredColorScheme(.dark)
        .tint(FutureselfTheme.blue.tint)
        .task(id: tick) { await play() }
        .onAppear {
            // A story told on a clock can't be read by VoiceOver; give those
            // learners the closing frame, which says the same in a list.
            if UIAccessibility.isVoiceOverRunning { finish() }
        }
        // A soft tap as each line turns over: felt, not heard. A voice-over
        // was tried and removed (2026-10-05).
        .onChange(of: beat) { _, _ in HapticEngine.soft() }
    }

    private func play() async {
        while autoplay && !isClosing && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.duration(of: Self.beats[beat])))
            guard autoplay, !Task.isCancelled else { return }
            step()
        }
    }

    /// Reveal + reading time. Long enough to read twice at a calm pace, short
    /// enough that the whole film stays well under a minute.
    static func duration(of b: StoryBeat) -> Double {
        if let hold = b.hold { return hold }
        let chars = Double(b.text.count)
        return min(6.5, max(3.8, 2.2 + chars * 0.06))
    }

    private func step() {
        withAnimation(.easeInOut(duration: 0.7)) { beat = min(beat + 1, Self.beats.count) }
    }

    /// From the first line again — the closing frame is where the film was
    /// skipped to, or where it ended, and either way it can be seen again.
    private func replay() {
        showingSignIn = false
        skipped = false
        doorOpen = false
        autoplay = true
        withAnimation(.easeInOut(duration: 0.7)) { beat = 0 }
        tick += 1
    }

    private func finish() {
        skipped = true
        autoplay = false
        withAnimation(.easeInOut(duration: 0.7)) { beat = Self.beats.count }
    }

    // MARK: - Story

    private var topBar: some View {
        HStack {
            Spacer()
            if !isClosing {
                Button("Skip") { finish() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            } else {
                Button("Watch again") { replay() }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 20)
                .transition(.opacity)
            }
        }
        .frame(height: 44)
    }

    /// One layout from the first line to the buttons. The caption sits in the
    /// middle; the fluent self sits below it from the first line on, and at
    /// the end it stretches into the Get started button — the same surface
    /// the Talk tab's call button is made of, so the first thing pressed in
    /// the app is the thing that will call.
    private var story: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                // Each beat is its own view, so its words animate in fresh.
                Group {
                    if isClosing {
                        VStack(spacing: 26) {
                            RevealText(text: Self.closingLine, still: reduceMotion)
                            // The film's own chips, gathered.
                            CenteredFlow(spacing: 6, lineSpacing: 8) {
                                ForEach(Array(Self.closingChips.enumerated()), id: \.offset) { i, g in
                                    Glimpse(symbol: g.symbol, label: g.label,
                                            delay: 1.5 + Double(i) * 0.12, still: reduceMotion)
                                }
                            }
                            // Full width, or the chips wrap to the headline's
                            // (narrower, balanced) width and stack one a row.
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        let b = Self.beats[beat]
                        VStack(spacing: 22) {
                            if let g = b.glimpse {
                                Glimpse(symbol: g.symbol, label: g.label, delay: 0.2, still: reduceMotion)
                            }
                            RevealText(text: b.text, still: reduceMotion)
                        }
                    }
                }
                .id(beat)
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .opacity.combined(with: .offset(y: reduceMotion ? 0 : -14))))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .frame(height: 250)
            Spacer(minLength: 0)
            bottom
        }
        .contentShape(Rectangle())
        // Tap anywhere to move on — the film is never a wall.
        .onTapGesture {
            guard !isClosing else { return }
            autoplay = true
            step()
            tick += 1
        }
        .task(id: isClosing) {
            guard isClosing else { doorOpen = false; return }
            // The orb opens into the button once the last line has landed;
            // straight away for someone who skipped or came to sign in.
            let wait = (skipped || showingSignIn || reduceMotion) ? 0.3 : 1.9
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.9)) { doorOpen = true }
        }
    }

    /// The orb, and what sits under it. The orb's row never changes height,
    /// so the orb is in the same place on every line and as a button.
    private var bottom: some View {
        VStack(spacing: 0) {
            ZStack {
                FutureselfDoor(open: doorOpen && !showingSignIn, beat: beat, still: reduceMotion) {
                    appState.onboardingStarted = true
                }
                .opacity(showingSignIn ? 0 : 1)
            }
            .frame(height: 76)
            .padding(.horizontal, 32)

            ZStack(alignment: .top) {
                if !isClosing {
                    VStack(spacing: 0) {
                        progress
                            .padding(.top, 22)
                            .padding(.bottom, 16)
                        Button("Already have an account? Sign in") {
                            showingSignIn = true
                            finish()
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.storyInk.opacity(0.55))
                    }
                    .transition(.opacity)
                } else {
                    signInArea
                        // Below the account buttons when they are up.
                        .padding(.top, showingSignIn ? 84 : 14)
                        .modifier(Arrive(delay: (skipped || showingSignIn) ? 0.3 : 2.5, still: reduceMotion))
                }
            }
            .frame(minHeight: 110, alignment: .top)
        }
        .padding(.bottom, 10)
        .overlay(alignment: .top) {
            // Returning users: the button steps aside for the account buttons.
            if isClosing && showingSignIn {
                signInButtons
                    .transition(.opacity)
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(Self.beats.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.storyInk.opacity(i <= beat ? 0.6 : 0.15))
                    .frame(width: i == beat ? 14 : 5, height: 3)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: beat)
        .accessibilityHidden(true)
    }

    // MARK: - Sign in

    /// Under the button: the returning-user link, the invite code, and in
    /// debug builds the sign-in skip.
    private var signInArea: some View {
        VStack(spacing: 8) {
            if !showingSignIn {
                Button("Already have an account? Sign in") {
                    withAnimation { showingSignIn = true }
                }
                .font(.footnote)
                .foregroundStyle(.tint)

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
    }

    /// Returning users: restore the account (and the voice clone that comes
    /// with it). Sits where the button was.
    private var signInButtons: some View {
        VStack(spacing: 8) {
            SignInWithAppleButton(
                onRequest: { request in
                    // Capture the invite code at the sign-in moment so
                    // it's redeemed as soon as the session lands.
                    savePendingInvite()
                    auth.configure(request)
                },
                onCompletion: { result in auth.handle(result: result) }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(Capsule())

            GoogleSignInButton(height: 52) {
                savePendingInvite()
                auth.signInWithGoogle()
            }

            Button("New here? Get started instead") {
                withAnimation { showingSignIn = false }
            }
            .font(.footnote)
            .foregroundStyle(.tint)
            .padding(.top, 2)
        }
        .padding(.horizontal, 32)
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
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.storyInk.opacity(0.06)))
                    .padding(.horizontal, 32)
                    .onChange(of: inviteCode) { _, _ in savePendingInvite() }
                Text(explain("You'll both get \(ReferralService.bonusMinutes) minutes of talk time when you sign in."))
                    .font(.caption).foregroundStyle(Color.storyInk.opacity(0.6))
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
