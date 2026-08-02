import SwiftUI

/// First-run quick-answer setup. One question per screen, mostly taps — the
/// user answers a few things so the app knows what to teach and how to
/// calibrate, BEFORE the heavier voice-clone recording step.
///
/// Two cards, one tap each:
///   1. Native language   ← explanations/translations speak this
///   2. Level             ← CEFR self-rating; calibrates every conversation
///
/// Native language leads — it's a plain fact with an obvious answer, so the
/// very first question never reads like a test. The level self-rating comes
/// second, once the user is already moving.
///
/// The practice target is fixed to English — the multi-language engine stays
/// in `LanguageCatalog`, it's just not offered as a choice here.
///
/// Flips `appState.setupComplete` on finish; RootView then routes to the
/// persona cards (voice clone comes last).
struct SetupFlowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @State private var step: Int = 0
    @State private var level: CEFRLevel = .b1
    @State private var nativeLanguage: String = LanguageCatalog.defaultNative
    /// Backing out of step one crosses the auth boundary (Welcome lives
    /// before sign-in), so it asks first instead of silently signing out.
    @State private var confirmingSignOut = false

    /// The one language the fluent self speaks. Fixed to English; the catalog
    /// still supports others, they're just not user-selectable.
    private let targetLanguage = "en"

    /// Languages offered as a native language — the catalog's wide native
    /// list, minus the (fixed) English target for safety.
    private static let nativeChoices = LanguageCatalog.nativeLanguages.filter { $0 != "en" }

    private static let totalSteps = 2

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(Self.totalSteps))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Form {
                    switch step {
                    case 0: nativeStep
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
            level = appState.proficiency
            // English can't be a native choice (it's the fixed target), so a
            // legacy "en" native default would leave no row checked — flip it
            // to the device's language instead (Korean if that's not offered).
            if nativeLanguage == targetLanguage {
                nativeLanguage = LanguageCatalog.defaultNative == targetLanguage
                    ? "ko" : LanguageCatalog.defaultNative
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
        default: return "Your level?"
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
            Text(explain("How comfortable are you right now?"))
        } footer: {
            Text(explain("You're about to build your fluent self — another you that already speaks fluent \(Self.englishName(targetLanguage)). This sets how it will speak and what it corrects. Not sure? Pick the closest — the app adjusts as you talk."))
        }
    }

    /// Plain-language read of each CEFR band, from the learner's chair.
    private static func levelBlurb(_ level: CEFRLevel) -> String {
        switch level {
        case .a1: return explain("Just starting — a few words and set phrases")
        case .a2: return "Basic — simple, everyday exchanges"
        case .b1: return explain("Conversational — I get by on familiar topics")
        case .b2: return explain("Independent — I discuss most things with some ease")
        case .c1: return explain("Advanced — I express myself fluently and precisely")
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
            Text(explain("What's your native language?"))
        } footer: {
            Text(explain("Explanations and translations come in this language."))
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
            Text(explain("This signs you out. Your answers stay on this device."))
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
            step += 1
        } else {
            finish()
        }
    }

    private func finish() {
        // Persist the answers, then open the gate so RootView moves on to
        // the persona cards (the clone, recorded later, is named after this
        // language).
        appState.targetLanguage = targetLanguage
        appState.nativeLanguage = nativeLanguage
        appState.proficiency = level
        appState.setupComplete = true
    }
}
