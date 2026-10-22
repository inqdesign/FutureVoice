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
    /// Everything this list already holds (plus, for words, the graded pool),
    /// read once when the sheet opens: what the field searches as they type.
    @State private var pool: [Candidate] = []
    /// First-sense gloss per match, the list pages' lookup (free, cached).
    @State private var meanings: [String: String] = [:]
    /// Word keys on the study list without a notebook row (a scene's words).
    @State private var listedKeys: Set<String> = []

    private struct Candidate: Identifiable {
        let text: String
        let key: String
        var id: String { key }
    }

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

                // What's already there, as they type: tapping one opens it
                // (or, for a pool word, keeps it) instead of making a copy.
                let found = matches
                if !found.isEmpty {
                    Section {
                        ForEach(found) { match in
                            matchRow(match)
                        }
                    } header: {
                        Text("Already there")
                    }
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
            .onAppear {
                focused = true
                loadPool()
            }
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

    // MARK: - Matches

    private func loadPool() {
        let store = VocabStore.shared
        var seen = Set<String>()
        var out: [Candidate] = []
        func take(_ text: String) {
            let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            out.append(Candidate(text: text, key: key))
        }
        switch kind {
        case .word:
            let toStudy = WordCatalog.toStudy(scenarios: appState.scenarios, store: store)
            listedKeys = Set(toStudy.map(\.key))
            for item in toStudy + WordCatalog.known(store: store) { take(item.text) }
            for entry in CoreVocabulary.entries { take(entry.word) }
        case .expression:
            for item in ExpressionCatalog.all(scenarios: appState.scenarios, store: store) { take(item.text) }
        case .sentence:
            for card in DrillStore.shared.load().sorted(by: { $0.createdAt > $1.createdAt }) {
                take(card.targetPhrase)
            }
        }
        pool = out
    }

    /// Prefix matches first ("par" → parse before spare), then anything that
    /// contains it; a handful, since this is a check, not a browser.
    private var matches: [Candidate] {
        let q = trimmed.lowercased()
        guard q.count >= (kind == .sentence ? 3 : 1), converted == nil else { return [] }
        let prefix = pool.filter { $0.key.hasPrefix(q) }
        let rest = kind == .word ? [] : pool.filter { !$0.key.hasPrefix(q) && $0.key.contains(q) }
        return Array((prefix.sorted { $0.key.count < $1.key.count } + rest).prefix(6))
    }

    private func matchRow(_ match: Candidate) -> some View {
        let status = status(of: match)
        return Button {
            open(match, onList: status != nil)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind == .sentence ? match.text : ExpressionsView.display(match.text))
                        .font(kind == .sentence ? .body : .system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let meaning = meanings[match.key], !meaning.isEmpty {
                        Text(meaning)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let level = CoreVocabulary.level(of: match.key) {
                    // A pool word nobody has kept yet: tapping it keeps it.
                    Text(level.rawValue.uppercased())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: status == nil ? "plus.circle" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(status == nil ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(kind == .sentence)
        .task(id: match.key) { await loadMeaning(match) }
    }

    /// Where the match already sits, or nil for a pool word not on any list.
    private func status(of match: Candidate) -> String? {
        let store = VocabStore.shared
        switch kind {
        case .word:
            if store.isStudying(match.key) { return explain("Studying") }
            if store.state(of: match.key) != nil { return explain("Known") }
            // A scene's word is on the study list without a notebook row.
            return listedKeys.contains(match.key) ? explain("To study") : nil
        case .expression:
            if store.isStudyingExpression(match.text) { return explain("Studying") }
            return store.hasUsedExpression(match.text) ? explain("Known") : explain("To study")
        case .sentence:
            return explain("Saved")
        }
    }

    private func open(_ match: Candidate, onList: Bool) {
        if kind == .word, !onList {
            VocabStore.shared.addStudying(match.key)
        }
        Analytics.capture("own_item_matched", ["kind": kind.rawValue, "added": !onList])
        dismiss()
        onAdded(kind == .word ? match.key : match.text)
    }

    private func loadMeaning(_ match: Candidate) async {
        guard kind != .sentence, meanings[match.key] == nil else { return }
        // Let a fast typist get past a match before it is looked up.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, meanings[match.key] == nil else { return }
        let entry = await WordLore.entry(for: match.text, native: appState.nativeLanguage,
                                         target: appState.targetLanguage,
                                         kind: kind == .word ? .word : .expression)
        guard !Task.isCancelled else { return }
        meanings[match.key] = entry?.senses.first?.meaning ?? ""
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
