import SwiftUI

/// First-run quick-answer setup. One question per screen, mostly taps — the
/// user answers a few things so the app knows what to teach and how to
/// calibrate, BEFORE the heavier voice-clone recording step.
///
/// Three cards, one tap each:
///   1. Native language   ← explanations/translations speak this
///   2. Target language   ← what the fluent self speaks (multi-language:
///                          more can be enrolled later from the Talk header)
///   3. Level             ← CEFR self-rating; calibrates every conversation
///
/// Native language leads — it's a plain fact with an obvious answer, so the
/// very first question never reads like a test. The target comes next (it
/// scopes the level labels, e.g. TOPIK for Korean), the self-rating last.
///
/// Flips `appState.setupComplete` on finish; RootView then routes to the
/// persona cards (voice clone comes last).
struct SetupFlowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @State private var step: Int = 0
    @State private var level: CEFRLevel = .b1
    @State private var nativeLanguage: String = LanguageCatalog.defaultNative
    @State private var targetLanguage: String = "en"
    /// Backing out of step one crosses the auth boundary (Welcome lives
    /// before sign-in), so it asks first instead of silently signing out.
    @State private var confirmingSignOut = false

    /// Practice targets on offer — everything the app can deliver end to end
    /// (`LanguageCatalog.selectableTargets`) except the chosen native language.
    private var targetChoices: [String] {
        LanguageCatalog.selectableTargets.map(\.code).filter { $0 != nativeLanguage }
    }

    private static let nativeChoices = LanguageCatalog.nativeLanguages

    private static let totalSteps = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(Self.totalSteps))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Form {
                    switch step {
                    case 0: nativeStep
                    case 1: targetStep
                    default: levelStep
                    }
                }
                Spacer(minLength: 0)
                bottomBar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            nativeLanguage = appState.nativeLanguage
            targetLanguage = appState.targetLanguage
            level = appState.proficiency
            // Native and target can't coincide; targets step re-checks after
            // the native pick too (see advance()). The target moves, not the
            // native — the native seed came from the device and is the better
            // guess of the two.
            if targetLanguage == nativeLanguage {
                targetLanguage = targetChoices.first ?? "en"
            }
            #if DEBUG
            // Screenshot harness: `-onboardingStep <n>` jumps to a card.
            if UserDefaults.standard.object(forKey: "onboardingStep") != nil {
                step = min(Self.totalSteps - 1, max(0, UserDefaults.standard.integer(forKey: "onboardingStep")))
            }
            #endif
        }
    }

    private var title: String {
        switch step {
        case 0: return "Your language?"
        case 1: return "Learn which language?"
        default: return "Your level?"
        }
    }

    // MARK: - Step 2 · Target language

    /// What the fluent self will speak. One row per supported target; more
    /// languages can be enrolled later from the Talk header — this picks the
    /// first one.
    private var targetStep: some View {
        Section {
            ForEach(targetChoices, id: \.self) { code in
                pickRow(
                    title: Self.endonym(code),
                    subtitle: Self.englishName(code),
                    selected: targetLanguage == code
                ) { targetLanguage = code }
            }
        } header: {
            Text("Which language do you want to speak?")
        } footer: {
            Text("Your fluent self speaks this language in your own voice. You can add more languages later — same voice, no extra setup.")
        }
    }

    // MARK: - Step 1 · Level

    /// CEFR self-rating. Every conversation, correction, and word card is
    /// calibrated to this, so it's asked up front rather than defaulted — a
    /// silent B1 default made the very first talk feel wrong for beginners and
    /// advanced users alike. Labels carry TOPIK for Korean via the catalog.
    private var levelStep: some View {
        Section {
            ForEach(CEFRLevel.allCases, id: \.self) { lvl in
                pickRow(
                    title: LanguageCatalog.levelLabel(lvl, target: targetLanguage),
                    subtitle: Self.levelBlurb(lvl),
                    selected: level == lvl
                ) { level = lvl }
            }
        } header: {
            Text("How comfortable are you right now?")
        } footer: {
            Text("You're about to build your fluent self — another you that already speaks fluent \(Self.englishName(targetLanguage)). This sets how it will speak and what it corrects. Not sure? Pick the closest — the app adjusts as you talk.")
        }
    }

    /// Plain-language read of each CEFR band, from the learner's chair.
    private static func levelBlurb(_ level: CEFRLevel) -> String {
        switch level {
        case .a1: return "Just starting — a few words and set phrases"
        case .a2: return "Basic — simple, everyday exchanges"
        case .b1: return "Conversational — I get by on familiar topics"
        case .b2: return "Independent — I discuss most things with some ease"
        case .c1: return "Advanced — I express myself fluently and precisely"
        case .c2: return "Mastery — effortless, near-native"
        }
    }

    // MARK: - Step 2 · Native language

    /// The language the learner already lives in. Drives "Explain in my
    /// language", correction explanations, and word-card translations — a
    /// Japanese learner should read those in Japanese, not English.
    private var nativeStep: some View {
        Section {
            ForEach(Self.nativeChoices, id: \.self) { code in
                pickRow(
                    title: Self.endonym(code),
                    subtitle: Self.englishName(code),
                    selected: nativeLanguage == code
                ) { nativeLanguage = code }
            }
        } header: {
            Text("What's your native language?")
        } footer: {
            Text("Explanations and translations come in this language.")
        }
    }

    // MARK: - Shared pick row

    /// One tappable choice — title + caption on the left, a checkmark on the
    /// right when selected. Same shape on every step so the flow reads as one.
    private func pickRow(title: String, subtitle: String, selected: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Locale display names

    /// Language name in its own language, e.g. "Deutsch", "Español".
    private static func endonym(_ code: String) -> String {
        LanguageCatalog.endonym(code)
    }

    /// Language name in the device UI language (English today).
    private static func englishName(_ code: String) -> String {
        LanguageCatalog.englishName(code)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                if step > 0 {
                    step -= 1
                } else if auth.session == nil {
                    // Account-free onboarding (the normal path now): Welcome
                    // is just the previous screen — no auth boundary to cross.
                    backToWelcome()
                } else {
                    // Signed-in (returning user): going back to Welcome means
                    // signing out, so confirm first.
                    confirmingSignOut = true
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button {
                advance()
            } label: {
                Text(step < Self.totalSteps - 1 ? "Next" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .confirmationDialog("Back to the welcome screen?",
                            isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out & go back", role: .destructive) { backToWelcome() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("This signs you out. Your answers stay on this device.")
        }
    }

    /// Return to Welcome: reopen the gate (and end the session if one
    /// exists; in debug, drop the skip-auth bypass so Welcome actually shows).
    private func backToWelcome() {
        #if DEBUG
        UserDefaults.standard.set(false, forKey: "debugSkipAuth")
        #endif
        appState.onboardingStarted = false
        if auth.session != nil {
            Task { await auth.signOut() }
        }
    }

    private func advance() {
        if step < Self.totalSteps - 1 {
            // The native pick may have collided with the pre-selected target.
            if targetLanguage == nativeLanguage {
                targetLanguage = targetChoices.first ?? "en"
            }
            step += 1
        } else {
            finish()
        }
    }

    private func finish() {
        // Persist the answers and enroll the chosen target as the ONLY
        // language (replacing the fresh install's default enrollment), then
        // open the gate so RootView moves on to the persona cards.
        appState.completeSetup(target: targetLanguage,
                               native: nativeLanguage,
                               level: level)
    }
}
