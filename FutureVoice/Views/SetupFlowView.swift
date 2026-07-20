import SwiftUI

/// First-run quick-answer setup. One question per screen, mostly taps — the
/// user answers a few things so the app knows what to teach and how to
/// calibrate, BEFORE the heavier voice-clone recording step.
///
/// Three cards, one tap each:
///   1. Target language   ← which language the fluent self speaks
///   2. Level             ← CEFR self-rating; calibrates every conversation
///   3. Native language   ← explanations/translations speak this
///
/// Flips `appState.setupComplete` on finish; RootView then routes to the
/// voice-clone step.
struct SetupFlowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step: Int = 0
    @State private var targetLanguage: String = "en"
    @State private var level: CEFRLevel = .b1
    @State private var nativeLanguage: String = "ko"

    /// Languages the fluent self can speak — from the central catalog, so
    /// the picker, STT locales, and scoring rules can never disagree.
    private static let targetLanguages = LanguageCatalog.targets.map(\.code)

    private static let totalSteps = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(Self.totalSteps))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Form {
                    switch step {
                    case 0: languageStep
                    case 1: levelStep
                    default: nativeStep
                    }
                }
                Spacer(minLength: 0)
                bottomBar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            targetLanguage = appState.targetLanguage
            nativeLanguage = appState.nativeLanguage
            level = appState.proficiency
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
        case 0: return "Which language?"
        case 1: return "Your level?"
        default: return "Your language?"
        }
    }

    // MARK: - Step 1 · Target language

    private var languageStep: some View {
        Section {
            ForEach(Self.targetLanguages, id: \.self) { code in
                pickRow(
                    title: Self.endonym(code),
                    subtitle: Self.englishName(code),
                    selected: targetLanguage == code
                ) { targetLanguage = code }
            }
        } header: {
            Text("What do you want to practice?")
        } footer: {
            Text("Your fluent self speaks this. You can change it later in settings.")
        }
    }

    // MARK: - Step 2 · Level

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
            Text("This calibrates how your fluent self speaks and what it corrects. Not sure? Pick the closest — the app adjusts as you talk.")
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

    // MARK: - Step 3 · Native language

    /// The language the learner already lives in. Drives "Explain in my
    /// language", correction explanations, and word-card translations — a
    /// Korean-learning American should read those in English, not Korean.
    private var nativeStep: some View {
        Section {
            ForEach(Self.targetLanguages.filter { $0 != targetLanguage }, id: \.self) { code in
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
            if step > 0 {
                Button {
                    step -= 1
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
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
    }

    private func advance() {
        if step < Self.totalSteps - 1 {
            step += 1
            // Entering the native step with native == target (e.g. a Korean
            // learner arrives with the old "ko" default): flip to the likely
            // answer so the checkmark isn't on a nonsensical row.
            if step == Self.totalSteps - 1, nativeLanguage == targetLanguage {
                nativeLanguage = targetLanguage == "en" ? "ko" : "en"
            }
        } else {
            finish()
        }
    }

    private func finish() {
        // Persist the answers, then open the gate so RootView moves on to the
        // voice-clone step (which names the clone after this language).
        appState.targetLanguage = targetLanguage
        appState.nativeLanguage = nativeLanguage
        appState.proficiency = level
        appState.setupComplete = true
    }
}
