import SwiftUI

/// The language the scripts are in, the learner's own, and their level —
/// what the Speech tab needs to write a script and explain it. One page.
enum SpeechSetup {
    static let doneKey = "speech.setupDone"

    /// Make `code` the active practice language at `level`.
    @MainActor
    static func apply(target code: String, native: String, level: CEFRLevel, to appState: AppState) {
        if appState.enrolledLanguages.contains(code) {
            appState.switchLanguage(to: code)
        } else {
            appState.addLanguage(code, level: level)
        }
        appState.setLevel(level, for: code)
        appState.nativeLanguage = native
    }
}

struct SpeechSetupView: View {
    @EnvironmentObject private var appState: AppState
    let onDone: () -> Void

    @State private var target = "en"
    @State private var native = LanguageCatalog.defaultNative
    @State private var level: CEFRLevel = .b1

    var body: some View {
        NavigationStack {
            Form {
                SpeechLanguageFields(target: $target, native: $native, level: $level)
            }
            .navigationTitle("Your languages")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        SpeechSetup.apply(target: target, native: native, level: level, to: appState)
                        onDone()
                    }
                    .disabled(LanguageCatalog.sameLanguage(target, native))
                }
            }
        }
        .onAppear {
            target = appState.targetLanguage
            native = appState.nativeLanguage
            level = appState.proficiency
            // The practice language can't be the learner's own.
            if LanguageCatalog.sameLanguage(target, native),
               let other = LanguageCatalog.selectableTargets.first(where: {
                   !LanguageCatalog.sameLanguage($0.code, native) }) {
                target = other.code
            }
        }
    }
}

/// The three pickers, shared by setup and settings.
struct SpeechLanguageFields: View {
    @Binding var target: String
    @Binding var native: String
    @Binding var level: CEFRLevel

    var body: some View {
        Section {
            Picker("I practice", selection: $target) {
                ForEach(LanguageCatalog.selectableTargets, id: \.code) { lang in
                    Text(LanguageCatalog.name(lang.code, in: UILanguage.chromeLanguage)).tag(lang.code)
                }
            }
            Picker("My level", selection: $level) {
                ForEach(CEFRLevel.allCases, id: \.self) { l in
                    Text(LanguageCatalog.levelLabel(l, target: target)).tag(l)
                }
            }
        } footer: {
            Text("Scripts are written in this language, at this level.")
        }
        Section {
            Picker("My language", selection: $native) {
                ForEach(LanguageCatalog.nativeChoices, id: \.self) { code in
                    Text(LanguageCatalog.name(code, in: UILanguage.chromeLanguage)).tag(code)
                }
            }
        } footer: {
            if LanguageCatalog.sameLanguage(target, native) {
                Text("Pick a language to practice that isn't your own.")
                    .foregroundStyle(.red)
            } else {
                Text("Explanations and feedback come in this language.")
            }
        }
    }
}
