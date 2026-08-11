import SwiftUI

/// Dedicated surface for the multi-word expressions the user has actually used
/// across their talks — the phrase-level companion to the word cloud. Rows are
/// collected automatically at the end of each session (verified against the
/// user's own transcript), so everything here is something they really said.
/// Tapping a row opens the expression's card as a sheet — same interaction as
/// tapping a word anywhere in the app.
struct ExpressionsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = VocabStore.shared
    @State private var selected: PhraseRef?
    @State private var filter: Filter = .toStudy

    private struct PhraseRef: Identifiable {
        let value: String
        var id: String { value }
    }

    /// Two lenses: what still needs work (default) and what's done. Every
    /// expression is in exactly one — "to study" is simply everything not yet
    /// marked known, so nothing hides behind a third tab.
    enum Filter: String, CaseIterable, Identifiable {
        case toStudy, known
        var id: String { rawValue }
        var label: String {
            switch self {
            case .toStudy: return "To study"
            case .known:   return "Known"
            }
        }
    }

    private var entries: [VocabStore.ExpressionEntry] {
        let all = store.expressionEntries()
        switch filter {
        case .toStudy: return all.filter { !store.isKnownExpression($0.text) }
        case .known:   return all.filter { store.isKnownExpression($0.text) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if entries.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "quote.bubble")
                } description: {
                    Text(emptyMessage)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(entries) { entry in
                            Button {
                                selected = PhraseRef(value: entry.text)
                            } label: {
                                row(entry)
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text(filter == .toStudy
                             ? "Captured automatically from what you say. Mark the ones you've got down as known."
                             : "\(entries.count) known")
                    }
                }
            }
        }
        .navigationTitle("\(store.expressionCount) expressions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            // Opened from a widget note tap → jump straight to that phrase.
            if let p = appState.focusPhrase {
                selected = PhraseRef(value: p)
                appState.focusPhrase = nil
            }
        }
        // A later widget tap (page already open) opens the new phrase.
        .onChange(of: appState.focusPhrase) { _, p in
            guard let p else { return }
            selected = PhraseRef(value: p)
            appState.focusPhrase = nil
        }
        .sheet(item: $selected) { ref in
            ExpressionSheet(initialPhrase: ref.value, phrases: entries.map(\.text))
                .environmentObject(appState)
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .toStudy: return "Nothing to study yet"
        case .known:   return "Nothing marked known"
        }
    }
    private var emptyMessage: String {
        switch filter {
        case .toStudy: return explain("Expressions you use in your talks will collect here.")
        case .known:   return explain("Mark expressions you've got down as known.")
        }
    }

    private func row(_ entry: VocabStore.ExpressionEntry) -> some View {
        let studying = store.isStudyingExpression(entry.text)
        let known = store.isKnownExpression(entry.text)
        return HStack(spacing: 12) {
            // Status badge, same grammar as the word cloud: bookmark = studying,
            // check = known.
            if studying || known {
                Image(systemName: studying ? "bookmark.fill" : "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(studying ? Color.accentColor : Color.green)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.display(entry.text))
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("Used \(entry.count) time\(entry.count == 1 ? "" : "s") · \(entry.lastAt.formatted(.dateTime.month().day()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// Stored keys are lowercased; show with a capitalized first letter.
    static func display(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}

/// Hosts the expression card in a sheet with its own current-phrase state —
/// the WordSheet pattern: header chevrons swap the phrase in place, the sheet
/// item never changes identity, so navigating doesn't close and reopen it.
struct ExpressionSheet: View {
    let initialPhrase: String
    /// Sibling phrases in display order for the header chevrons; empty →
    /// no navigation, just the one card.
    let phrases: [String]
    @State private var current: String?

    var body: some View {
        NavigationStack {
            ExpressionCard(phrase: current ?? initialPhrase,
                           currentPhrase: Binding(
                               get: { current ?? initialPhrase },
                               set: { if let p = $0 { current = p } }
                           ),
                           navigationPhrases: phrases.isEmpty ? nil : phrases)
        }
    }
}

/// One expression's card — the same treatment (and layout) a word gets on its
/// WordCard: big headline + pronounce button, meaning in the user's native
/// language (via the shared `word_entry` dictionary cache — WordLore handles
/// phrases like single words), examples with translations, the sentences
/// where they actually said it, chevron navigation top-right, and the action
/// bar pinned at the bottom.
struct ExpressionCard: View {
    let phrase: String
    @Binding var currentPhrase: String?
    /// Sibling list the header chevrons walk; nil hides them.
    var navigationPhrases: [String]? = nil
    /// Title as "3 of 10" instead of the collection count — the daily
    /// expressions session walks a dealt hand, not the collection, so the
    /// collection's count would be a lie there.
    var titleByPosition: Bool = false
    /// Fires on an AFFIRMATIVE judgment only — Study or I know it, never
    /// their un-taps. Mirrors `WordCard.onJudged`.
    var onJudged: ((String) -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = VocabStore.shared
    @StateObject private var player = AudioPlayer()

    @State private var entry: WordEntry?
    @State private var loading = false
    @State private var speaking = false
    @State private var sentences: [VocabStore.SourceSentence] = []
    @State private var shadowing: Turn?

    private var navList: [String] { navigationPhrases ?? [] }
    private var navIndex: Int? { navList.firstIndex(of: phrase) }
    private var isKnown: Bool { store.isKnownExpression(phrase) }
    private var isStudying: Bool { store.isStudyingExpression(phrase) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center, spacing: 14) {
                    Text(ExpressionsView.display(phrase))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if appState.voiceCloneId != nil { pronounceButton }
                }

                section("Meaning") {
                    if let senses = entry?.senses, !senses.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(senses) { s in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(s.meaning)
                                        .font(.title3.weight(.semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let note = s.note, !note.isEmpty {
                                        Text(note).font(.footnote).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    } else {
                        Text(loading ? "…" : "—").font(.body).foregroundStyle(.secondary)
                    }
                }

                section(entry?.examples.count == 1 ? "Example" : "Examples") {
                    if let examples = entry?.examples, !examples.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(examples) { exampleRow($0) }
                        }
                    } else {
                        Text(loading ? "…" : "—").font(.body).foregroundStyle(.secondary)
                    }
                }

                if !sentences.isEmpty {
                    section("From your talks") {
                        VStack(spacing: 8) { ForEach(sentences) { sentenceRow($0) } }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(titleByPosition && navIndex != nil
                         ? Text("\((navIndex ?? 0) + 1) of \(navList.count)")
                         : Text("My expressions · \(store.expressionCount)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let i = navIndex {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { currentPhrase = navList[i - 1] } label: { Image(systemName: "chevron.up") }
                        .disabled(i == 0)
                    Button { currentPhrase = navList[i + 1] } label: { Image(systemName: "chevron.down") }
                        .disabled(i + 1 >= navList.count)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .task(id: phrase) { await load() }
        .onDisappear { player.stop() }
        .fullScreenCover(item: $shadowing) { turn in
            NavigationStack {
                ShadowDrillView(turn: turn, targetLanguage: appState.targetLanguage)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Pieces

    private var pronounceButton: some View {
        Button {
            Task { await speakPhrase() }
        } label: {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 46, height: 46)
                if speaking {
                    ProgressView()
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3).foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(speaking)
    }

    private func exampleRow(_ e: WordEntry.Example) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let m = e.meaning, !m.isEmpty {
                    Text(m).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                shadowing = Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                                 transcript: e.text, durationMs: 0,
                                 timestamp: Date(), suggestion: nil)
            } label: {
                Label("Shadow this", systemImage: "waveform.badge.mic")
            }
        }
    }

    private func sentenceRow(_ s: VocabStore.SourceSentence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(highlighted(s.text)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Text(s.source).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let url = s.audioURL {
                    Button { play(url) } label: { Label("Listen", systemImage: "play.circle") }
                }
                Button { shadowing = makeTurn(s) } label: { Label("Shadow", systemImage: "waveform.badge.mic") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            blurButton(isStudying ? "Studying" : "Study",
                       icon: isStudying ? "bookmark.fill" : "bookmark",
                       tint: isStudying ? .accentColor : .primary) {
                // Bookmark to keep studying — mirrors adding a word to the
                // notebook; the phrase then shows on the Expressions widget.
                // (Capture the pre-toggle state: isStudying is computed off
                // the store, so it flips the moment the set lands.)
                let wasStudying = isStudying
                store.setStudyingExpression(phrase, !wasStudying)
                if !wasStudying { onJudged?(phrase) }
            }
            blurButton(isKnown ? "Known" : "I know it",
                       icon: isKnown ? "checkmark.circle.fill" : "checkmark.circle",
                       tint: isKnown ? .green : .primary) {
                // Toggle known — stay on the phrase so it visibly flips, same
                // as WordCard.
                let wasKnown = isKnown
                store.setKnownExpression(phrase, !wasKnown)
                if !wasKnown { onJudged?(phrase) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Same style as WordCard's action bar: native Liquid Glass on iOS 26, a
    /// bordered capsule fallback below.
    private func blurButton(_ title: String, icon: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .tint(tint)
        if #available(iOS 26.0, *) {
            return AnyView(button.buttonStyle(.glass))
        } else {
            // .bordered alone is a translucent tint with NO blur — a material
            // capsule underneath keeps the label readable over the sheet's
            // scrolling content on pre-26 OSes (seen on iPad).
            return AnyView(button.buttonStyle(.bordered)
                .background(.regularMaterial, in: Capsule()))
        }
    }

    // MARK: - Logic

    private func load() async {
        entry = nil
        sentences = store.sentences(containing: phrase)
        loading = true
        entry = await WordLore.entry(for: phrase, native: appState.nativeLanguage)
        loading = false
    }

    private func makeTurn(_ s: VocabStore.SourceSentence) -> Turn {
        Turn(id: UUID(), role: .fluentSelf, audioURL: s.audioURL,
             transcript: s.text, durationMs: 0, timestamp: Date(), suggestion: nil)
    }

    private func play(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        try? player.play(data, forceSessionReset: true)
    }

    private func speakPhrase() async {
        guard let voiceId = appState.voiceCloneId else { return }
        if let data = PhraseAudioStore.shared.data(text: phrase, voiceId: voiceId) {
            try? player.play(data, forceSessionReset: true)
            return
        }
        speaking = true
        defer { speaking = false }
        do {
            let data = try await ElevenLabsClient.shared.synthesize(voiceId: voiceId, text: phrase, purpose: "library")
            PhraseAudioStore.shared.save(data, text: phrase, voiceId: voiceId)
            try? player.play(data, forceSessionReset: true)
        } catch {
            // network/credits failure — leave the button idle, nothing to play
        }
    }

    /// Bold the expression inside the sentence so it stands out.
    private func highlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        if let r = attr.range(of: phrase, options: .caseInsensitive) {
            attr[r].font = .subheadline.bold()
        }
        return attr
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            content()
        }
    }
}
