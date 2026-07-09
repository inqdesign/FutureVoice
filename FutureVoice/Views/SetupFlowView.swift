import SwiftUI

/// First-run quick-answer setup. One question per screen, mostly taps — the
/// user answers a few things so the app knows what to teach and how to
/// calibrate, BEFORE the heavier voice-clone recording step.
///
/// Grows one card at a time:
///   1. Target language   ← which language the fluent self speaks
///   (next) level, name, interests …
///
/// Flips `appState.setupComplete` on finish; RootView then routes to the
/// voice-clone step.
struct SetupFlowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step: Int = 0
    @State private var targetLanguage: String = "en"

    /// Languages the fluent self can speak — from the central catalog, so
    /// the picker, STT locales, and scoring rules can never disagree.
    private static let targetLanguages = LanguageCatalog.targets.map(\.code)

    private static let totalSteps = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(Self.totalSteps))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Form {
                    switch step {
                    default: languageStep
                    }
                }
                Spacer(minLength: 0)
                bottomBar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { targetLanguage = appState.targetLanguage }
    }

    private var title: String {
        switch step {
        default: return "Which language?"
        }
    }

    // MARK: - Step 1 · Target language

    private var languageStep: some View {
        Section {
            ForEach(Self.targetLanguages, id: \.self) { code in
                Button {
                    targetLanguage = code
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.endonym(code))
                                .foregroundStyle(.primary)
                            Text(Self.englishName(code))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if targetLanguage == code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("What do you want to practice?")
        } footer: {
            Text("Your fluent self speaks this. You can change it later in settings.")
        }
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
        } else {
            finish()
        }
    }

    private func finish() {
        // Persist the answers, then open the gate so RootView moves on to the
        // voice-clone step (which names the clone after this language).
        appState.targetLanguage = targetLanguage
        appState.setupComplete = true
    }
}
