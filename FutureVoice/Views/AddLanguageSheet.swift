import SwiftUI

/// "Add a language" — pick a new practice target and a starting level, then
/// enroll & switch (`AppState.addLanguage`). Deliberately seconds-long: the
/// existing voice clone speaks the new language too, so there's no recording
/// step, no second onboarding — that's the multi-language promise
/// (docs/multi-language-plan.md).
struct AddLanguageSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var level: CEFRLevel = .a2

    /// Targets still open to this user: not their native language, not
    /// already enrolled.
    private var choices: [String] {
        LanguageCatalog.targets.map(\.code).filter {
            $0 != appState.nativeLanguage && !appState.enrolledLanguages.contains($0)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(choices, id: \.self) { c in
                        Button { code = c } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LanguageCatalog.endonym(c))
                                        .foregroundStyle(.primary)
                                    Text(LanguageCatalog.englishName(c))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if code == c {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Which language next?")
                }
                if let code {
                    Section {
                        Picker("Starting level", selection: $level) {
                            ForEach(CEFRLevel.allCases, id: \.self) { lvl in
                                Text(LanguageCatalog.levelLabel(lvl, target: code))
                                    .tag(lvl)
                            }
                        }
                    } footer: {
                        Text("Your cloned voice already speaks \(LanguageCatalog.englishName(code)) — no new recording needed. Your \(LanguageCatalog.englishName(appState.targetLanguage)) progress stays untouched.")
                    }
                }
            }
            .navigationTitle("Add a language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start") {
                        if let code { appState.addLanguage(code, level: level) }
                        dismiss()
                    }
                    .disabled(code == nil)
                }
            }
        }
    }
}
