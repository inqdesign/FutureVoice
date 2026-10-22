import SwiftUI

/// A word, an expression or a sentence the learner wants on a list that no
/// talk or scene handed them. They type (or dictate) it; the list does the
/// rest exactly as it does for anything else on it: a word gets its card's
/// meanings, an expression its gloss, a sentence a translation under it.
///
/// Typed in the native language instead ("사과" while learning English), it
/// is turned into the target language first and shown before it is added,
/// so the learner can see what goes on the list. Only a different SCRIPT can
/// tell the two apart; German typed by an English speaker reads as English.
struct AddToListSheet: View {
    enum Kind: String {
        case word, expression, sentence
    }

    let kind: Kind
    /// Called with what went on the list (the word's key, the phrase, the
    /// sentence) after the sheet is dismissed, so the page can open its card.
    var onAdded: (String) -> Void = { _ in }

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// The target-language version of a native-language entry, waiting for
    /// the learner to confirm it.
    @State private var converted: String?
    @State private var working = false
    @State private var failed = false
    @State private var refused = false
    @FocusState private var focused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var needsConverting: Bool {
        appState.targetLanguage != appState.nativeLanguage
            && !TextScript.isInTargetScript(trimmed, language: appState.targetLanguage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(kind == .sentence ? 2...5 : 1...3)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .onChange(of: text) { _, _ in
                            converted = nil
                            failed = false
                            refused = false
                        }
                } footer: {
                    Text(footer)
                }

                if let converted {
                    Section {
                        Text(converted)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                    } header: {
                        Text(LanguageCatalog.name(appState.targetLanguage, in: appState.nativeLanguage))
                    }
                }

                if failed {
                    Section {
                        Label(explain("Couldn't reach the dictionary. Try again."),
                              systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                    }
                } else if refused {
                    Section {
                        Label(explain("That reads like a rule, not something you'd say. Write the sentence itself."),
                              systemImage: "exclamationmark.bubble")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Add", action: add)
                            .disabled(trimmed.isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        switch kind {
        case .word:       return explain("Add a word")
        case .expression: return explain("Add an expression")
        case .sentence:   return explain("Add a sentence")
        }
    }

    private var placeholder: String {
        switch kind {
        case .word:       return explain("A word")
        case .expression: return explain("An expression")
        case .sentence:   return explain("A sentence")
        }
    }

    private var footer: String {
        switch kind {
        case .word, .expression:
            return explain("Write it in either language. Its meanings come with it, like everything else on the list.")
        case .sentence:
            return explain("Write it in either language. It comes with a translation and goes into your review deck.")
        }
    }

    private func add() {
        guard !trimmed.isEmpty, !working else { return }
        // A converted entry the learner has now seen: that is what goes in.
        if let converted {
            commit(converted)
            return
        }
        guard needsConverting else {
            commit(trimmed)
            return
        }
        working = true
        Task {
            let result = await Translator.translate(trimmed, to: appState.targetLanguage)
            working = false
            guard let result else { failed = true; return }
            converted = kind == .sentence ? result : Self.bare(result)
        }
    }

    private func commit(_ entry: String) {
        let store = VocabStore.shared
        switch kind {
        case .word:
            let key = VocabStore.lookupKey(for: Self.bare(entry))
            guard !key.isEmpty else { return }
            store.addStudying(key)
            finish(key)
        case .expression:
            let phrase = Self.bare(entry)
            store.addExpression(phrase)
            finish(phrase)
        case .sentence:
            working = true
            Task {
                // The translation is the card's gloss, the line a sentence
                // card shows under itself on the list and in the deck.
                let gloss = await Translator.translate(entry, to: appState.nativeLanguage) ?? ""
                working = false
                let card = DrillStore.shared.bookmarkSentence(entry, reason: gloss)
                guard card != nil else { refused = true; return }
                finish(entry)
            }
        }
    }

    private func finish(_ entry: String) {
        Analytics.capture("own_item_added", ["kind": kind.rawValue,
                                             "converted": converted != nil])
        dismiss()
        onAdded(entry)
    }

    /// A word or phrase as a list keeps it: no sentence punctuation around it
    /// (a translator answers "Apple." for 사과), lowercased like every key.
    static func bare(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".。!！?？\"“”'‘’"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
