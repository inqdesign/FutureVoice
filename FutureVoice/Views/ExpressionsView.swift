import SwiftUI

/// Dedicated surface for the multi-word expressions in the learner's orbit —
/// the phrase-level companion to the word cloud. Rows are collected
/// automatically at the end of each session and each is one of three things,
/// said out loud by the row itself: a phrase they USED, a phrase their fluent
/// self used in a call and they didn't yet, or one a watched scene taught.
/// Tapping a row opens the expression's card as a sheet — same interaction as
/// tapping a word anywhere in the app.
struct ExpressionsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = VocabStore.shared
    @State private var selected: PhraseRef?
    @State private var filter: Filter = .toStudy
    @State private var searchText = ""
    /// First-sense gloss per phrase, filled lazily as rows appear — the words
    /// page's pattern. "" = looked up, nothing to show; the row falls back to
    /// its origin line and the session won't retry.
    @State private var meanings: [String: String] = [:]

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
            // Through `explain` — a `String` never sees the locale on its own
            // (the words page's rule; these two read as English in Korean).
            switch self {
            case .toStudy: return explain("To study")
            case .known:   return explain("Known")
            }
        }
    }

    /// Every source in one list — phrases you SAID (VocabStore), the ones your
    /// fluent self used in a call, and the ones your Watch books handed you.
    /// They used to be separate worlds: a book could show six expressions that
    /// this page had never heard of, while the daily deck dealt them anyway.
    private var entries: [ExpressionCatalog.Item] {
        let all = ExpressionCatalog.all(scenarios: appState.scenarios, store: store)
        if !searchQuery.isEmpty {
            // Search reads BOTH lenses, whatever is up — the words page's rule.
            let q = searchQuery.lowercased()
            return all.filter { $0.text.lowercased().contains(q) }
                .sorted { l, r in
                    let lp = l.text.lowercased().hasPrefix(q), rp = r.text.lowercased().hasPrefix(q)
                    if lp != rp { return lp }
                    return l.text < r.text
                }
        }
        switch filter {
        case .toStudy: return all.filter { !store.hasUsedExpression($0.text) }
        case .known:   return all.filter { store.hasUsedExpression($0.text) }
        }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            // The search drawer above brings its own air; the list below
            // brings none — same row as the words page.
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            List {
                if entries.isEmpty {
                    Section {
                        if !searchQuery.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            ContentUnavailableView {
                                Label(emptyTitle, systemImage: "quote.bubble")
                            } description: {
                                Text(emptyMessage)
                            }
                        }
                    }
                } else {
                    Section {
                        ForEach(entries) { entry in
                            Button {
                                selected = PhraseRef(value: entry.text)
                            } label: {
                                row(entry)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) { keepAction(entry) }
                            .swipeActions(edge: .trailing) { knownAction(entry) }
                            .task(id: entry.text) { await loadMeaning(entry) }
                        }
                    } header: {
                        // What this lens adds up to — same grammar as the
                        // words page.
                        Text("\(entries.count) expressions")
                    } footer: {
                        if filter == .toStudy, searchQuery.isEmpty {
                            Text(explain("Captured from what you say, what your fluent self says back, and the expressions your watched scenes teach. Mark the ones you've got down as known."))
                        }
                    }
                }
            }
        }
        .navigationTitle("Expressions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search expressions"))
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
        case .toStudy: return explain("Expressions from your calls — yours and your fluent self's — and the ones your watched scenes hand you collect here.")
        case .known:   return explain("Mark expressions you've got down as known.")
        }
    }

    /// The card's two verdicts, a swipe away — the words page's rule, to
    /// the letter (right = Keep, left = I know), with the same store calls as
    /// `ExpressionSheet.actionBar`.
    private func keepAction(_ entry: ExpressionCatalog.Item) -> some View {
        let studying = store.isStudyingExpression(entry.text)
        return Button {
            store.setStudyingExpression(entry.text, !studying)
        } label: {
            Label("Keep", systemImage: studying ? "bookmark.slash" : "bookmark")
        }
        .tint(studying ? .gray : .accentColor)
    }

    private func knownAction(_ entry: ExpressionCatalog.Item) -> some View {
        let known = store.isKnownExpression(entry.text)
        return Button {
            store.setKnownExpression(entry.text, !known)
        } label: {
            Label("I know", systemImage: known ? "arrow.uturn.backward" : "checkmark.circle")
        }
        .tint(known ? .gray : .green)
    }

    private func row(_ entry: ExpressionCatalog.Item) -> some View {
        let studying = store.isStudyingExpression(entry.text)
        let known = store.hasUsedExpression(entry.text)
        let confirmed = store.isConfirmedExpression(entry.text)
        return HStack(spacing: 12) {
            // Status badge, same grammar as the word cloud: bookmark = studying,
            // check = known, filled check = said in a talk (confirmed).
            if studying || known {
                Image(systemName: studying ? "bookmark.fill" : (confirmed ? "checkmark.circle.fill" : "checkmark"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(studying ? Color.accentColor : Color.green)
                    .frame(width: 16)
                    .accessibilityLabel(studying ? explain("Studying")
                                        : (confirmed ? explain("Used in a talk") : explain("Marked known")))
            }
            VStack(alignment: .leading, spacing: 3) {
                // Same rounded face as the card and the words page's rows.
                Text(Self.display(entry.text))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                subtitle(entry)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// The phrase's meaning, like the words page. Until the gloss is in (or
    /// when there is none) the row says where it came from — "Used N times"
    /// on a scene phrase the learner hasn't spoken would be a lie, which is
    /// why scene expressions aren't simply copied into the store.
    @ViewBuilder
    private func subtitle(_ entry: ExpressionCatalog.Item) -> some View {
        if let meaning = meanings[entry.text], !meaning.isEmpty {
            Text(meaning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            switch entry.origin {
            case .said(let count):
                Text("Used \(count) time\(count == 1 ? "" : "s") · \(entry.at.formatted(.dateTime.month().day()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .scene(let title):
                Label(title, systemImage: "film")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .heard(let title):
                // Says where it came from AND that it's still unsaid — the
                // whole difference between this row and a "Used 3 times" one.
                Label(title.isEmpty ? explain("Heard in a call") : title,
                      systemImage: "quote.bubble")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Same lookup the expression card runs (`WordLore`, `.expression` — the
    /// word prompt would gloss one word out of the middle of a phrase), fired
    /// per row as it appears; the card's own tap then hits the warm cache.
    private func loadMeaning(_ entry: ExpressionCatalog.Item) async {
        guard meanings[entry.text] == nil else { return }
        let fetched = await WordLore.entry(for: entry.text, native: appState.nativeLanguage,
                                           target: appState.targetLanguage, kind: .expression)
        guard !Task.isCancelled else { return }
        meanings[entry.text] = fetched?.senses.first?.meaning ?? ""
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
    /// Where each phrase came from, when the caller knows: the scene cue and
    /// the line that used it. A book has this; the library doesn't.
    var context: [String: ExpressionCard.Context] = [:]
    @State private var current: String?

    var body: some View {
        NavigationStack {
            let phrase = current ?? initialPhrase
            ExpressionCard(phrase: phrase,
                           currentPhrase: Binding(
                               get: { current ?? initialPhrase },
                               set: { if let p = $0 { current = p } }
                           ),
                           navigationPhrases: phrases.isEmpty ? nil : phrases,
                           context: context[phrase])
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
    /// What the book already knows about this phrase. A scenario's curriculum
    /// is generated WITH its scene, so it holds the one thing a dictionary
    /// can never have: when this chunk came up here, and the line that used
    /// it. Shown above the generic entry — the card used to drop it on the
    /// floor and lead with a lookup.
    struct Context: Equatable {
        var note: String
        var example: String?
    }

    let phrase: String
    @Binding var currentPhrase: String?
    /// Sibling list the header chevrons walk; nil hides them.
    var navigationPhrases: [String]? = nil
    var context: Context? = nil

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = VocabStore.shared
    @StateObject private var player = AudioPlayer()

    @State private var entry: WordEntry?
    @State private var loading = false
    /// Same as the word card: a nil lookup means the generation round trip
    /// failed, which deserves a retry rather than a dash.
    @State private var failed = false
    @State private var speaking = false
    @State private var sentences: [VocabStore.SourceSentence] = []
    @State private var shadowing: Turn?
    /// Sentences already on file (`DrillStore.sentenceKeys`), read once —
    /// the example's long-press says "Saved" instead of offering it again.
    @State private var savedSentences: Set<String> = []

    private var navList: [String] { navigationPhrases ?? [] }
    private var navIndex: Int? { navList.firstIndex(of: phrase) }
    private var isKnown: Bool { store.isKnownExpression(phrase) }
    private var isStudying: Bool { store.isStudyingExpression(phrase) }

    var body: some View {
        bodyContent
            // A parked voice (see `VoiceParking`) can't make new audio;
            // the answer to the tap is the paywall, not a dead button.
            .sheet(isPresented: $parkedPaywall) { PaywallView(source: "expression_audio") }
    }

    @State private var parkedPaywall = false

    @ViewBuilder private var bodyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        // The word card's headline face; a size down because
                        // a phrase is several words and still has to fit.
                        Text(ExpressionsView.display(phrase))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        // What kind of chunk it is + its register — the
                        // expression's answer to a word's part of speech.
                        if let pos = entry?.pos, !pos.isEmpty {
                            Text(pos).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    if appState.voiceCloneId != nil { pronounceButton }
                }

                if let c = context, !c.note.isEmpty || !(c.example ?? "").isEmpty {
                    section("In this scene") {
                        VStack(alignment: .leading, spacing: 8) {
                            if !c.note.isEmpty {
                                Text(c.note)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let ex = c.example, !ex.isEmpty {
                                Text("“\(ex)”")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                section("Meaning") {
                    if let senses = entry?.senses, !senses.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(senses.enumerated()), id: \.element.id) { i, s in
                                senseRow(i + 1, s)
                            }
                        }
                    } else {
                        lookupPlaceholder
                    }
                }

                // Same rule as the word card: one failure, one retry.
                if !failed {
                    section(entry?.examples.count == 1 ? "Example" : "Examples") {
                        if let examples = entry?.examples, !examples.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(examples) { exampleRow($0) }
                            }
                        } else {
                            lookupPlaceholder
                        }
                    }
                }

                // Near-variants — the same move said another way, for when
                // this phrasing doesn't fit. Same slot a word card gives to
                // "Common phrases".
                if let variants = entry?.phrases, !variants.isEmpty {
                    section("Another way to say it") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(variants) { phraseRow($0) }
                        }
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
        // Walking a dealt list titles by position — the word card's rule —
        // and the library's count otherwise.
        .navigationTitle(navIndex != nil
                         ? Text("\((navIndex ?? 0) + 1) of \(navList.count)")
                         : Text("My expressions · \(store.expressionCount)"))
        .navigationBarTitleDisplayMode(.inline)
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

    /// Numbered like the word card's senses; the register line stands in
    /// for a part of speech and is skipped when the entry has none.
    private func senseRow(_ index: Int, _ s: WordEntry.Sense) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                if !s.pos.isEmpty {
                    Text(s.pos)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                Text(s.meaning)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let note = s.note, !note.isEmpty {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The word card's "Common phrases" tile, so a variant reads as the same
    /// kind of thing there and here: saveable, shadowable, on a long press.
    private func phraseRow(_ p: WordEntry.Phrase) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(p.phrase)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(p.meaning).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .contentShape(Rectangle())
        .contextMenu { saveActions(for: p.phrase) }
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
        .contextMenu { saveActions(for: e.text) }
        .onAppear { if savedSentences.isEmpty { savedSentences = DrillStore.shared.sentenceKeys() } }
    }

    /// Long-press actions on an example — the word card's pair: save the
    /// sentence to study later, or shadow it right now.
    @ViewBuilder
    private func saveActions(for text: String) -> some View {
        if savedSentences.contains(DrillStore.sentenceKey(text)) {
            Label("Saved to sentences", systemImage: "checkmark")
        } else {
            Button {
                if DrillStore.shared.bookmarkSentence(text, reason: explain("Example for “\(phrase)”")) != nil {
                    savedSentences.insert(DrillStore.sentenceKey(text))
                    HapticEngine.drillCorrect()
                }
            } label: {
                Label("Save to sentences", systemImage: "text.bubble")
            }
        }
        if store.isStudyingExpression(text) {
            Label("Saved to expressions", systemImage: "checkmark")
        } else {
            Button {
                store.addExpression(text)
                HapticEngine.drillCorrect()
            } label: {
                Label("Save to expressions", systemImage: "bookmark")
            }
        }
        Button {
            shadowing = Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                             transcript: text, durationMs: 0, timestamp: Date(),
                             suggestion: nil)
        } label: {
            Label("Shadow this", systemImage: "waveform.badge.mic")
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

    /// The word card's bar, to the letter: Keep · I know · ↑ · ↓
    /// (`CardButtons.swift`). The state rides on the icon and tint, never on
    /// the label, so the two capsules keep one width each.
    private var actionBar: some View {
        HStack(spacing: 8) {
            CardActionButton(title: "Keep",
                             icon: isStudying ? "bookmark.fill" : "bookmark",
                             tint: isStudying ? .accentColor : .primary) {
                // Bookmark to keep studying — mirrors adding a word to the
                // notebook; the phrase then shows on the Expressions widget.
                store.setStudyingExpression(phrase, !isStudying)
            }
            .accessibilityLabel(isStudying ? "Studying this expression" : "Keep studying this expression")

            CardActionButton(title: "I know",
                             icon: isKnown ? "checkmark.circle.fill" : "checkmark.circle",
                             tint: isKnown ? .green : .primary) {
                // Toggle known — stay on the phrase so it visibly flips, same
                // as WordCard.
                store.setKnownExpression(phrase, !isKnown)
            }
            .accessibilityLabel(isKnown ? "Marked as known" : "Mark as known")

            if let i = navIndex {
                CardStepButton(icon: "chevron.up", label: "Previous expression") { currentPhrase = navList[i - 1] }
                    .disabled(i == 0)
                CardStepButton(icon: "chevron.down", label: "Next expression") { currentPhrase = navList[i + 1] }
                    .disabled(i + 1 >= navList.count)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Logic

    private func load() async {
        // `loading` FIRST: clearing the entry before flipping it flashed the
        // "—" no-entry glyph for a frame on every phrase swap.
        loading = true
        failed = false
        entry = nil
        sentences = store.sentences(containing: phrase)
        // .expression, always — this card only ever holds multi-word chunks,
        // and the word prompt would gloss one word out of the middle of it.
        let fetched = await WordLore.entry(for: phrase, native: appState.nativeLanguage,
                                           target: appState.targetLanguage, kind: .expression)
        // Same rule as the word card: a cancelled lookup must not clear the
        // loading flag for the phrase that replaced it.
        guard !Task.isCancelled else { return }
        entry = fetched
        failed = fetched == nil
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


    /// While a dictionary entry is being generated, say so — with the same
    /// spinner every other generation in the app uses. A bare "…" was
    /// pixel-identical to the "—" no-entry state, so a slow first lookup
    /// (a cold word runs a full LLM generation server-side) read as a frozen
    /// screen rather than as work in progress.
    @ViewBuilder
    private var lookupPlaceholder: some View {
        if loading {
            LookupProgress()
        } else if failed {
            LookupFailure { Task { await load() } }
        } else {
            Text("—").font(.body).foregroundStyle(.secondary)
        }
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
            if error.isOutOfCredits { parkedPaywall = true }
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
